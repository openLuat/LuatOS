--[[
@module  airui_sleep
@summary AirUI 休眠管理示例，演示 AirUI + TP + 模组三级联动休眠与唤醒
@version 1.0
@date    2026.05.25
@author  江访
@usage
本文件为 AirUI 休眠管理功能模块，核心业务逻辑为：
1、通过 UI 界面配置休眠参数（开关、超时时间、休眠类型、唤醒类型）
2、监测触摸空闲时间，超时后自动执行三级休眠：AirUI休眠 → TP休眠 → 模组休眠
3、唤醒顺序：先唤醒模组 → 再唤醒TP → 最后唤醒AirUI

休眠类型说明：
- AIRUI_SLEEP：仅 AirUI 休眠，禁用触摸，用户代码仍可运行
- AIRUI_SLEEP_TOUCH_WAKE：AirUI 休眠，触摸可唤醒（TP INT 引脚配置为中断）
- MODULE_LOWPOWER：模组常规低功耗模式（pm.WORK_MODE = 1），代码继续运行
- MODULE_PSM_PLUS：模组超低功耗模式（pm.WORK_MODE = 3），唤醒后设备重启
- TP_SLEEP：仅触摸屏休眠（GT911 发送 0x05 休眠命令）

唤醒类型说明：
- TOUCH_WAKE：依赖 TP INT 引脚硬件中断唤醒模组（需为 WAKEUP 引脚），GT911 触摸时自动退出休眠
- TIMER_WAKE：通过定时器唤醒（低功耗模式下用 sys.timerStart，PSM+ 下用 pm.dtimerStart）
- 禁用触摸：通过 airui.touch_unsubscribe() 取消 airui 层触摸订阅，airui.sleep() 同时停止渲染和输入处理

注意事项：
1、休眠模式下需要保持屏幕 VCC 供电和 RST 引脚高电平，否则屏幕无法恢复显示
2、模组超低功耗休眠模式（PSM+）下 VDD-EXT 会间歇性掉电，如果设备需要进入低功耗模式，
   不能使用模组的 VDD-EXT 供电，应使用独立电源或 VBAT 供电
3、触摸休眠目前仅支持 GT911 触摸芯片

本文件的对外接口有3个：
1、sys.subscribe("AIRUI_SLEEP_START", ...)：订阅休眠启动消息
2、sys.subscribe("AIRUI_SLEEP_WAKEUP", ...)：订阅唤醒消息
3、airui_sleep.init()：初始化休眠管理模块
]]

-- ==================== 常量定义 ====================

-- 休眠类型常量
local SLEEP_TYPE_AIRUI_ONLY = 1            -- 仅 AirUI 休眠，禁用触摸
local SLEEP_TYPE_AIRUI_TOUCH_WAKE = 2      -- AirUI 休眠，触摸可唤醒
local SLEEP_TYPE_MODULE_LOWPOWER = 3       -- 模组常规低功耗模式
local SLEEP_TYPE_MODULE_PSM_PLUS = 4       -- 模组超低功耗模式（PSM+）
local SLEEP_TYPE_TP_ONLY = 5               -- 仅 TP 休眠

-- 唤醒类型常量
local WAKE_TYPE_TOUCH = 1                  -- 触摸唤醒
local WAKE_TYPE_TIMER = 2                  -- 定时唤醒
local WAKE_TYPE_TOUCH_AND_TIMER = 3        -- 触摸 + 定时唤醒
local WAKE_TYPE_NONE = 4                   -- 不禁用外部唤醒（依赖底层默认行为）

-- 默认配置参数
local DEFAULT_SLEEP_ENABLE = true           -- 默认开启休眠
local DEFAULT_SLEEP_TIMEOUT = 30            -- 默认30秒无操作自动休眠
local DEFAULT_SLEEP_TYPE = SLEEP_TYPE_MODULE_LOWPOWER  -- 默认模组常规低功耗
local DEFAULT_WAKE_TYPE = WAKE_TYPE_TOUCH   -- 默认触摸唤醒
local DEFAULT_TIMER_WAKE_SEC = 300          -- 默认定时唤醒间隔300秒

-- ==================== 模块状态变量 ====================

-- 休眠配置参数
local sleep_enable = DEFAULT_SLEEP_ENABLE
local sleep_timeout_sec = DEFAULT_SLEEP_TIMEOUT
local sleep_type = DEFAULT_SLEEP_TYPE
local wake_type = DEFAULT_WAKE_TYPE
local timer_wake_sec = DEFAULT_TIMER_WAKE_SEC

-- 运行时状态
local is_sleeping = false                   -- 是否处于休眠状态
local tp_is_sleeping = false                -- TP 是否已休眠
local idle_check_timer = nil                -- 空闲检测定时器
local wake_timer_id = nil                   -- 唤醒定时器ID
-- UI 控件引用（模块级，供定时器回调更新）
local ui_status_label = nil
local ui_idle_label = nil

-- 硬件引脚配置（根据实际硬件修改）
local TP_INT_PIN = 7                        -- TP 中断引脚
local TP_RST_PIN = 28                       -- TP 复位引脚
local I2C_SCL_PIN = 0                       -- I2C SCL 引脚
local I2C_SDA_PIN = 1                       -- I2C SDA 引脚


-- ==================== 内部函数 ====================

-- 空闲秒数计数器（每秒+1，触摸时归零），避免依赖 mcu.ticks2 时间戳
local idle_seconds = 0

-- 记录触摸事件，重置空闲计数器
local function record_touch_event()
    idle_seconds = 0
end

-- 检查是否空闲超时
local function is_idle_timeout()
    if not sleep_enable then return false end
    if is_sleeping then return false end
    return idle_seconds >= sleep_timeout_sec
end

-- 触摸订阅回调（TP_DOWN 时记录触摸时间用于空闲检测，必须在 airui_touch_enable 之前定义）
local function touch_subscribe_callback(state, x, y, track_id, timestamp)
    if state == airui.TP_DOWN then record_touch_event() end
end

-- 启用 AirUI 触摸
local function airui_touch_enable()
    log.info("airui_sleep", "启用 AirUI 触摸监控")
    airui.touch_subscribe(touch_subscribe_callback)
end

-- 禁用 AirUI 触摸监控（软件层）
local function airui_touch_disable()
    log.info("airui_sleep", "禁用 AirUI 触摸监控")
    airui.touch_unsubscribe()
end

-- 配置 TP INT 引脚为 GPIO 中断（硬件层触摸唤醒）
-- 在低功耗模式下，TP INT 引脚下降沿（GT911 触摸时拉低 INT）唤醒模组
local function setup_touch_wakeup()
    log.info("airui_sleep", "配置触摸唤醒，INT引脚:", TP_INT_PIN)
    gpio.debounce(TP_INT_PIN, 50)
    gpio.setup(TP_INT_PIN, function(level, pin_id)
        log.info("airui_sleep", "触摸唤醒触发")
        sys.publish("AIRUI_SLEEP_WAKEUP", "touch")
    end, gpio.PULLUP, gpio.FALLING)
end

-- 释放 TP INT 引脚 GPIO 中断配置（唤醒后需要恢复给 TP 驱动使用）
local function disable_touch_wakeup()
    log.info("airui_sleep", "释放触摸唤醒引脚")
    gpio.close(TP_INT_PIN)
end

-- 唤醒后重新初始化 TP（因 setup_touch_wakeup 覆盖了 INT 引脚配置，需 tp.init 恢复）
local function tp_reinit()
    if not _G.tp_sleep_device then return false end
    -- Air8101: 软件 I2C
    local i2c_obj = i2c.createSoft(I2C_SCL_PIN, I2C_SDA_PIN)
    if type(i2c_obj) ~= "userdata" then
        log.error("airui_sleep", "I2C 初始化失败")
        return false
    end
    _G.tp_sleep_device = tp.init("gt911", {
        port = i2c_obj, pin_rst = TP_RST_PIN, pin_int = TP_INT_PIN, w = 320, h = 480,
    })
    if _G.tp_sleep_device then
        airui.device_bind_touch(_G.tp_sleep_device)
        log.info("airui_sleep", "TP 恢复成功")
        return true
    end
    log.error("airui_sleep", "TP 恢复失败")
    return false
end

-- 设置定时唤醒定时器
-- 低功耗模式下使用 sys.timerStart 定时发布唤醒消息
local function setup_timer_wakeup()
    if wake_timer_id then
        sys.timerStop(wake_timer_id)
        wake_timer_id = nil
    end

    log.info("airui_sleep", "配置定时唤醒，间隔:", timer_wake_sec, "秒")

    wake_timer_id = sys.timerStart(function()
        log.info("airui_sleep", "定时唤醒触发")
        sys.publish("AIRUI_SLEEP_WAKEUP", "timer")
    end, timer_wake_sec * 1000)
end

-- 禁用定时唤醒
local function disable_timer_wakeup()
    if wake_timer_id then
        sys.timerStop(wake_timer_id)
        wake_timer_id = nil
        log.info("airui_sleep", "已禁用定时唤醒")
    end
end

-- 更新空闲检测定时器
local function update_idle_check_timer()
    if idle_check_timer then
        sys.timerStop(idle_check_timer)
        idle_check_timer = nil
    end

    if not sleep_enable then
        return
    end

    -- 每秒递增空闲计数并检测是否超时
    idle_check_timer = sys.timerLoopStart(function()
        idle_seconds = idle_seconds + 1
        if is_idle_timeout() then
            log.info("airui_sleep", "空闲超时", sleep_timeout_sec, "秒，进入休眠流程")
            sys.publish("AIRUI_SLEEP_START")
        end
    end, 1000)
end


-- ==================== 休眠与唤醒核心流程 ====================

-- 休眠流程：AirUI休眠 → TP休眠 → 模组休眠
-- 严格按照此顺序执行，确保各层级正确进入休眠状态
local function execute_sleep_sequence()
    if is_sleeping then
        log.info("airui_sleep", "已在休眠状态，跳过")
        return
    end

    is_sleeping = true
    log.info("airui_sleep", "========== 开始休眠流程 ==========")

    -- 步骤1：AirUI 进入休眠
    -- airui.sleep() 停止渲染更新，降低刷新频率
    -- 如果休眠类型是仅 AirUI 休眠（禁用触摸），则不关闭 LCD 电源
    if sleep_type == SLEEP_TYPE_AIRUI_ONLY then
        log.info("airui_sleep", "步骤1：AirUI 休眠（禁用触摸）")
        airui.sleep({power_down_lcd = false})
    elseif sleep_type == SLEEP_TYPE_AIRUI_TOUCH_WAKE then
        log.info("airui_sleep", "步骤1：AirUI 休眠（支持触摸唤醒）")
        airui.sleep({power_down_lcd = false})
    else
        -- 模组休眠或 TP 休眠场景，AirUI 也需要先休眠
        log.info("airui_sleep", "步骤1：AirUI 休眠")
        airui.sleep({power_down_lcd = false})
    end

    -- 步骤2：TP 触摸芯片休眠（仅首次，避免重复休眠导致 I2C 超时）
    -- GT911 休眠后若未被触摸唤醒（如定时器唤醒），芯片仍处于休眠态，再次发 0x05 会 I2C 超时
    if _G.tp_sleep_device and not tp_is_sleeping then
        log.info("airui_sleep", "步骤2：TP 触摸芯片休眠（GT911）")
        local tp_sleep_result = tp.sleep(_G.tp_sleep_device)
        if tp_sleep_result then
            tp_is_sleeping = true
            log.info("airui_sleep", "TP 休眠成功")
        else
            log.error("airui_sleep", "TP 休眠失败")
        end
    elseif tp_is_sleeping then
        log.info("airui_sleep", "步骤2：TP 已在休眠状态，跳过")
    else
        log.info("airui_sleep", "步骤2：无 TP 设备，跳过")
    end

    -- 步骤3：配置唤醒方式
    -- 软件层：取消 airui 触摸订阅
    airui_touch_disable()

    -- 硬件层：根据唤醒类型配置唤醒源
    -- 触摸唤醒：GPIO 中断配置 TP INT 引脚（下降沿触发 → 发布 AIRUI_SLEEP_WAKEUP）
    -- 定时唤醒：低功耗用 sys.timerStart，PSM+ 用 pm.dtimerStart
    if wake_type == WAKE_TYPE_TOUCH or wake_type == WAKE_TYPE_TOUCH_AND_TIMER then
        setup_touch_wakeup()
    end
    if wake_type == WAKE_TYPE_TIMER or wake_type == WAKE_TYPE_TOUCH_AND_TIMER then
        setup_timer_wakeup()
    else
        disable_timer_wakeup()
    end

    -- 步骤4：模组进入低功耗模式
    if sleep_type == SLEEP_TYPE_MODULE_LOWPOWER then
        -- 常规低功耗模式：代码仍可运行，响应中断和定时器
        -- 触摸 INT 中断、定时器到期都会唤醒模组并执行回调
        log.info("airui_sleep", "步骤3：模组进入常规低功耗模式（pm.WORK_MODE = 1）")
        pm.power(pm.WORK_MODE, 1)

    elseif sleep_type == SLEEP_TYPE_MODULE_PSM_PLUS then
        -- 超低功耗模式（PSM+）：代码停止运行，唤醒后设备会重启
        -- 使用 pm.dtimerStart 配置深度休眠定时器
        -- WAKEUP 引脚中断也可唤醒，但唤醒后设备重启
        log.info("airui_sleep", "步骤3：模组进入超低功耗模式（pm.WORK_MODE = 3）")

        -- 配置深度休眠定时器（仅 PSM+ 模式有效）
        if wake_type == WAKE_TYPE_TIMER or wake_type == WAKE_TYPE_TOUCH_AND_TIMER then
            pm.dtimerStart(0, timer_wake_sec * 1000)
            log.info("airui_sleep", "PSM+ 深度定时器已设置:", timer_wake_sec, "秒")
        end

        -- 进入 PSM+ 模式
        pm.power(pm.WORK_MODE, 3)

        -- 如果成功进入 PSM+，以下代码不会执行
        -- 如果未立即进入，等待80秒后强制重启
        sys.wait(80000)
        log.info("airui_sleep", "PSM+ 进入失败，执行重启")
        rtos.reboot()

    elseif sleep_type == SLEEP_TYPE_TP_ONLY then
        -- 仅 TP 休眠，模组不进入低功耗
        log.info("airui_sleep", "步骤3：仅 TP 休眠，模组保持常规模式")
        -- 不调用 pm.power，模组保持常规运行状态

    else
        -- AirUI 仅休眠类型，不操作模组功耗
        log.info("airui_sleep", "步骤3：仅 AirUI 休眠，模组保持常规模式")
    end

    log.info("airui_sleep", "========== 休眠流程完成 ==========")
end

-- 唤醒流程：先唤醒模组 → 再唤醒TP → 最后唤醒AirUI
-- 严格按照此顺序执行，确保各层级正确恢复
local function execute_wakeup_sequence(wake_source)
    if not is_sleeping then
        log.info("airui_sleep", "未在休眠状态，跳过唤醒")
        return
    end

    log.info("airui_sleep", "========== 开始唤醒流程，唤醒源:", wake_source, "==========")

    -- 步骤1：唤醒模组，切换到常规模式
    -- 对于低功耗模式（WORK_MODE 1），pm.power(WORK_MODE, 0) 立即切换
    -- 对于 PSM+ 模式（WORK_MODE 3），唤醒后设备已重启，不会执行到这里
    if sleep_type == SLEEP_TYPE_MODULE_LOWPOWER then
        log.info("airui_sleep", "步骤1：模组切换到常规模式（pm.WORK_MODE = 0）")
        pm.power(pm.WORK_MODE, 0)
    end

    -- 步骤2：释放触摸唤醒 GPIO，恢复 TP
    -- setup_touch_wakeup 用 gpio.setup 覆盖了 TP INT 引脚，唤醒后需释放并重新初始化 TP
    disable_touch_wakeup()
    if _G.tp_sleep_device then
        log.info("airui_sleep", "步骤2：重新初始化 TP，恢复 INT 引脚")
        tp_reinit()
    end

    -- 步骤3：唤醒 AirUI，恢复渲染
    log.info("airui_sleep", "步骤3：唤醒 AirUI")
    airui.wakeup({auto_refresh = true})

    -- 步骤4：重新启用 AirUI 触摸监控
    airui_touch_enable()

    -- 更新状态
    is_sleeping = false
    tp_is_sleeping = false
    idle_seconds = 0

    -- 重新启动空闲检测定时器
    update_idle_check_timer()

    log.info("airui_sleep", "========== 唤醒流程完成 ==========")
end

-- ==================== 外部接口 ====================

-- 休眠管理模块表
local airui_sleep = {}

-- 初始化休眠管理模块
-- 启动空闲检测，订阅休眠和唤醒消息
function airui_sleep.init()
    log.info("airui_sleep", "初始化休眠管理模块")
    log.info("airui_sleep", "休眠开关:", sleep_enable)
    log.info("airui_sleep", "空闲超时:", sleep_timeout_sec, "秒")
    log.info("airui_sleep", "休眠类型:", sleep_type)
    log.info("airui_sleep", "唤醒类型:", wake_type)
    if wake_type == WAKE_TYPE_TIMER or wake_type == WAKE_TYPE_TOUCH_AND_TIMER then
        log.info("airui_sleep", "定时唤醒间隔:", timer_wake_sec, "秒")
    end

    -- tp_sleep_device 在 tp_drv.lua 的 tp_drv_init() 中已设置到 _G.tp_sleep_device

    -- 初始化空闲计数
    idle_seconds = 0

    -- 启用 AirUI 触摸监控（用于空闲检测）
    airui_touch_enable()

    -- 启动空闲检测
    update_idle_check_timer()
end

-- 手动触发休眠
function airui_sleep.manual_sleep()
    if not sleep_enable then
        log.info("airui_sleep", "休眠开关已关闭，无法手动休眠")
        return
    end
    log.info("airui_sleep", "手动触发休眠")
    sys.publish("AIRUI_SLEEP_START")
end

-- 手动触发唤醒
function airui_sleep.manual_wakeup()
    log.info("airui_sleep", "手动触发唤醒")
    sys.publish("AIRUI_SLEEP_WAKEUP", "manual")
end

-- 更新休眠配置
-- @param config table 配置表，包含以下可选字段：
--   enable: boolean 休眠开关
--   timeout_sec: number 空闲超时秒数
--   sleep_type: number 休眠类型（1-5）
--   wake_type: number 唤醒类型（1-4）
--   timer_wake_sec: number 定时唤醒间隔秒数
function airui_sleep.update_config(config)
    if config.enable ~= nil then
        sleep_enable = config.enable
        log.info("airui_sleep", "休眠开关更新为:", sleep_enable)
    end
    if config.timeout_sec ~= nil then
        sleep_timeout_sec = config.timeout_sec
        log.info("airui_sleep", "空闲超时更新为:", sleep_timeout_sec, "秒")
    end
    if config.sleep_type ~= nil then
        sleep_type = config.sleep_type
        log.info("airui_sleep", "休眠类型更新为:", sleep_type)
    end
    if config.wake_type ~= nil then
        wake_type = config.wake_type
        log.info("airui_sleep", "唤醒类型更新为:", wake_type)
    end
    if config.timer_wake_sec ~= nil then
        timer_wake_sec = config.timer_wake_sec
        log.info("airui_sleep", "定时唤醒间隔更新为:", timer_wake_sec, "秒")
    end

    -- 如果休眠开关被关闭且当前正在休眠，执行唤醒
    if not sleep_enable and is_sleeping then
        airui_sleep.manual_wakeup()
    end

    -- 重置空闲计数
    idle_seconds = 0
    update_idle_check_timer()
end

-- 获取当前休眠状态
-- @return table 包含所有配置和状态信息
function airui_sleep.get_status()
    return {
        enable = sleep_enable,
        timeout_sec = sleep_timeout_sec,
        sleep_type = sleep_type,
        wake_type = wake_type,
        timer_wake_sec = timer_wake_sec,
        is_sleeping = is_sleeping,
        idle_sec = idle_seconds,
    }
end

-- 获取休眠类型名称（用于UI显示）
function airui_sleep.get_sleep_type_name(s_type)
    s_type = s_type or sleep_type
    local names = {
        [SLEEP_TYPE_AIRUI_ONLY] = "AirUI休眠（禁用触摸）",
        [SLEEP_TYPE_AIRUI_TOUCH_WAKE] = "AirUI休眠（触摸唤醒）",
        [SLEEP_TYPE_MODULE_LOWPOWER] = "模组常规低功耗",
        [SLEEP_TYPE_MODULE_PSM_PLUS] = "模组超低功耗（PSM+）",
        [SLEEP_TYPE_TP_ONLY] = "仅TP休眠",
    }
    return names[s_type] or "未知"
end

-- 获取唤醒类型名称（用于UI显示）
function airui_sleep.get_wake_type_name(w_type)
    w_type = w_type or wake_type
    local names = {
        [WAKE_TYPE_TOUCH] = "触摸唤醒",
        [WAKE_TYPE_TIMER] = "定时唤醒",
        [WAKE_TYPE_TOUCH_AND_TIMER] = "触摸+定时唤醒",
        [WAKE_TYPE_NONE] = "无外部唤醒",
    }
    return names[w_type] or "未知"
end


-- ==================== 事件订阅与任务 ====================

-- 休眠任务：收到休眠消息后执行休眠序列
local function sleep_task()
    while true do
        local result = sys.waitUntil("AIRUI_SLEEP_START")
        if result then
            -- 在协程中执行休眠序列，避免阻塞消息循环
            sys.taskInit(function()
                execute_sleep_sequence()
            end)
        end
    end
end

-- 唤醒任务：收到唤醒消息后执行唤醒序列
local function wakeup_task()
    while true do
        local result, wake_source = sys.waitUntil("AIRUI_SLEEP_WAKEUP")
        if result then
            sys.taskInit(function()
                execute_wakeup_sequence(wake_source or "unknown")
            end)
        end
    end
end

-- 注册休眠和唤醒消息订阅
sys.subscribe("AIRUI_SLEEP_START", function()
    -- 消息处理仅做转发，实际逻辑在 sleep_task 协程中执行
end)

sys.subscribe("AIRUI_SLEEP_WAKEUP", function()
    -- 消息处理仅做转发，实际逻辑在 wakeup_task 协程中执行
end)

-- 启动休眠管理任务
sys.taskInit(sleep_task)
sys.taskInit(wakeup_task)



-- ==================== 触摸回调与 UI ====================

-- 获取屏幕尺寸
local function get_screen_size()
    local s = airui.status()
    if s and s.w then return s.w, s.h end
    local w, h = lcd.getSize()
    return w or 320, h or 480
end

-- 创建配置与状态 UI
local function create_sleep_ui()
    local sw, sh = get_screen_size()
    log.info("airui_sleep", "分辨率:", sw, "x", sh)
    local pad, lh, dh, bh = 10, 24, 32, 38

    -- 快捷标签
    local function lb(ty, text) return airui.label({text=text, x=pad, y=ty, w=sw-pad*2, h=lh, font_size=14}) end

    -- 标题
    airui.label({text="AirUI 休眠演示", x=0, y=5, w=sw, h=28, align=airui.ALIGN_CENTER, font_size=18})

    -- 休眠开关
    local y = 36
    local sw_label = lb(y, "休眠开关: " .. (sleep_enable and "开" or "关"))
    airui.switch({x=sw-60, y=y-2, w=50, h=28, checked=true,
        on_change = function(self)
            local v = self:get_state()
            airui_sleep.update_config({enable=v})
            sw_label:set_text("休眠开关: " .. (v and "开" or "关"))
        end})

    -- 休眠超时
    y = y + lh + 6
    local to_label = lb(y, "休眠超时: " .. sleep_timeout_sec .. "秒")
    local to_opts = {15, 30, 60, 120, 300}
    local to_names = {"15秒","30秒","60秒","120秒","300秒"}
    y = y + lh
    local to_dd = airui.dropdown({x=pad, y=y, w=sw-pad*2, h=dh, options=to_names, default_index=1})

    -- 休眠类型
    y = y + dh + 8
    local st_label = lb(y, "休眠类型")
    local st_names = {"AirUI休眠(禁用触摸)","AirUI休眠(触摸唤醒)","模组常规低功耗","模组超低功耗(PSM+)","仅TP休眠"}
    y = y + lh
    local st_dd = airui.dropdown({x=pad, y=y, w=sw-pad*2, h=dh, options=st_names, default_index=sleep_type - 1})
    st_label:set_text("休眠类型: " .. airui_sleep.get_sleep_type_name())

    -- 唤醒类型
    y = y + dh + 8
    local wt_label = lb(y, "唤醒类型")
    local wt_names = {"触摸唤醒","定时唤醒","触摸+定时唤醒","无外部唤醒"}
    y = y + lh
    local wt_dd = airui.dropdown({x=pad, y=y, w=sw-pad*2, h=dh, options=wt_names, default_index=wake_type - 1})
    wt_label:set_text("唤醒类型: " .. airui_sleep.get_wake_type_name())

    -- 确定按钮
    y = y + dh + 10
    airui.button({x=pad, y=y, w=sw-pad*2, h=bh, text="确 定 应 用",
        on_click = function(self)
            local to_idx = to_dd:get_selected()
            local st_idx = st_dd:get_selected()
            local wt_idx = wt_dd:get_selected()
            airui_sleep.update_config({
                timeout_sec = to_opts[to_idx + 1],
                sleep_type = st_idx + 1,
                wake_type = wt_idx + 1,
            })
            to_label:set_text("休眠超时: " .. to_opts[to_idx + 1] .. "秒")
            st_label:set_text("休眠类型: " .. st_names[st_idx + 1])
            wt_label:set_text("唤醒类型: " .. wt_names[wt_idx + 1])
            log.info("airui_sleep", "配置已应用: 超时", to_opts[to_idx+1], "秒, 休眠类型", st_idx+1, ", 唤醒类型", wt_idx+1)
        end})

    -- 状态 + 空闲（存到模块级变量）
    y = y + bh + 12
    ui_status_label = lb(y, "状态: 运行中")
    y = y + lh
    ui_idle_label = lb(y, "空闲: 0/" .. sleep_timeout_sec .. "秒")

    -- 底部注意事项
    y = sh - 60
    airui.label({text="注意: 休眠保持VCC/RST高电平; PSM+下VDD-EXT勿用外设供电", x=pad, y=y, w=sw-pad*2, h=22, font_size=11})
    airui.label({text="      TP休眠仅支持GT911(tp.sleep发0x05),触摸唤醒", x=pad, y=y+22, w=sw-pad*2, h=22, font_size=11})

    -- 每秒刷新
    local function refresh_cb()
        if is_sleeping then ui_status_label:set_text("状态: 休眠中")
        else ui_status_label:set_text("状态: 运行中") end
        local s = airui_sleep.get_status()
        local r = math.max(0, sleep_timeout_sec - s.idle_sec)
        ui_idle_label:set_text("空闲: " .. s.idle_sec .. "/" .. sleep_timeout_sec .. "秒(剩" .. r .. "秒)")
    end
    sys.timerLoopStart(refresh_cb, 1000)
end

-- UI 初始化
local function ui_init_task_func()
    sys.wait(200)
    create_sleep_ui()
    airui_sleep.init()
end
sys.taskInit(ui_init_task_func)

-- 注意事项
-- 1、休眠模式下需保持屏幕 VCC 供电和 RST 引脚高电平
-- 2、PSM+ 模式下 VDD-EXT 间歇性掉电，外围设备不能使用 VDD-EXT 供电
-- 3、低功耗模式下普通 GPIO 掉电，AGPIO 可保持输出，WAKEUP 引脚可作唤醒源
-- 4、airui.touch_unsubscribe() 取消触摸订阅，airui.sleep() 停止渲染
-- 5、tp.sleep 仅支持 GT911（命令0x05），触摸时自动退出休眠
-- 6、tp.sleep 后若定时器唤醒（非触摸），GT911 仍在休眠，再发 0x05 会 I2C 超时
-- 7、PSM+ 唤醒后设备重启，pm.lastReson() 判断唤醒源
-- 8、功耗参考: 低功耗约40-70uA，PSM+约3-10uA

return airui_sleep
