--[[
@module  airui_sleep
@summary AirUI 深度休眠管理演示
          GT911 深度休眠 + AirUI 自动休眠/唤醒管理 + 模组完整功耗切换
          触摸仅重置倒计时，不可从深度休眠中唤醒；休眠后仅按电源键唤醒
          集成 drv_lowpower/drv_normal 功耗模式切换 + 外设供电控制
@version 1.4
@date    2026.06.16
@author  江访
@usage
依赖模块（由 main.lua 先后加载）：
  lcd_inner_drv  → lcd.init + airui.init + 字体加载
  tp_drv         → tp.init + airui.device_bind_touch + 设置 _G.tp_sleep_device
  airui_sleep    → 本文件（内部 require drv_lowpower + drv_normal）

整体流程：
  运行态 → 空闲30秒 → airui.sleep() → TP deinit → LCD sleep
         → 拉低 INT >50ms (GT911 深度休眠) → drv_lowpower 进入低功耗模式1
  休眠态 → 按下 PWR_KEY → drv_normal 退出低功耗 → 恢复 GPIO147/164 供电
         → pm.WORK_MODE 0 → 拉高 INT 5ms 唤醒 GT911 → airui.wakeup() → 恢复显示

关键设计说明：
  1. 外设供电控制：GPIO147（摄像头）、GPIO164（音频解码 ES8311）与触摸共用 I2C，
     休眠时拉低可切断供电降低漏电，唤醒后恢复以确保 I2C 通信正常。
  2. GT911 深度休眠：deinit 释放 INT 脚后，重新将 INT(GPIO2) 拉低 >50ms，
     GT911 自动进入深度休眠（停止扫描，功耗 <30μA）。
  3. 功耗模式切换：通过 DRV_SET_LOWPOWER / DRV_SET_NORMAL 消息，
     触发 drv_lowpower.lua / drv_normal.lua 配置完整的模组电源状态。
  4. 触摸仅重置空闲倒计时，不会从深度休眠中唤醒设备。
]]

require("drv_lowpower")  -- 加载Air8000 进入低功耗模块
require("drv_normal")  -- 加载Air8000 退出低功耗模块

local IDLE_TIMEOUT = 30
local KEY_PWR = gpio.PWR_KEY

local is_sleeping = false
local idle_sec = 0

-- ==================== 按键初始化 ====================

local function key_down(name)
    sys.publish("KEY_EVENT", name .. "_down")
end
local function key_up(name)
    sys.publish("KEY_EVENT", name .. "_up")
end

local function pwr_key_cb(v)
    if v == 1 then key_up("pwr") else key_down("pwr") end
end

if KEY_PWR then
    gpio.setup(KEY_PWR, pwr_key_cb, gpio.PULLUP, gpio.BOTH)
    gpio.debounce(KEY_PWR, 50, 0)
end

-- ==================== 触摸重置空闲计时 ====================

local function touch_state_cb(state)
    if not is_sleeping and (state == 1 or state == 4) then
        idle_sec = 0
    end
end

airui.touch_subscribe(touch_state_cb)

-- ==================== AirUI 显示 ====================

airui.label({ text = "休眠演示", x = 10, y = 10, w = 300, h = 28, font_size = 20, color = 0x000000 })
local st_label = airui.label({ text = "运行中", x = 10, y = 55, w = 300, h = 24, font_size = 16, color = 0x000000 })
local ct_label = airui.label({ text = "", x = 10, y = 85, w = 300, h = 24, font_size = 16, color = 0x000000 })
local wk_label = airui.label({ text = "触摸可重置倒计时", x = 10, y = 120, w = 300, h = 20, font_size = 14, color = 0x808080 })
local pw_label = airui.label({ text = "休眠后按电源键唤醒", x = 10, y = 440, w = 300, h = 20, font_size = 14, color = 0x808080 })

local function display()
    local r = math.max(0, IDLE_TIMEOUT - idle_sec)
    if is_sleeping then
        st_label:set_text("深度休眠中")
        ct_label:set_text("")
        wk_label:set_text("")
        pw_label:set_text("休眠后按电源键唤醒")
    else
        st_label:set_text("运行中")
        ct_label:set_text(r .. " 秒后进入深度休眠")
        wk_label:set_text("触摸可重置倒计时")
        pw_label:set_text("休眠后按电源键唤醒")
    end
end
display()

-- ==================== 空闲定时器 ====================

local function idle_timer()
    idle_sec = idle_sec + 1
    if not is_sleeping then
        if idle_sec >= IDLE_TIMEOUT then
            log.info("main", "Idle timeout, sleep")
            sys.publish("SLEEP_START")
        end
        display()
    end
end
sys.timerLoopStart(idle_timer, 1000)

-- ==================== 进入深度休眠 ====================

local function do_sleep()

    -- 切断与触摸共用 I2C 的外设供电，防止漏电影响 I2C 通信
    -- GPIO147：摄像头电源；GPIO164：ES8311 音频 LDO 使能
    -- 这两个外设的 I2C 引脚与触摸 I2C 共用，若不切断供电，
    -- 休眠后 I2C 总线存在漏电路径，影响触摸唤醒后的 I2C 恢复
    gpio.set(147, 0)
    gpio.set(164, 0)

    if is_sleeping then return end
    is_sleeping = true
    log.info("main", "=== Sleep ===")

    -- AirUI 层休眠：关闭 LCD 显示，释放触摸 INT 引脚
    -- airui.sleep() 内部按顺序：
    --   1) 关触摸中断 → 2) tp.sleep(写 0x05 使 GT911 浅睡眠)
    --   3) tp.deinit(释放 INT 脚) → 4) LCD sleep 关闭显示

    -- 进入关闭lcd显示并进入浅休眠，整体功耗2ma
    -- airui.sleep({ power_down_lcd = true, mode = airui.SLEEP_MODE_LIGHT })
    
    -- 进入关闭lcd显示并进入深度休眠，整体功耗500微安
    airui.sleep({ power_down_lcd = true, mode = airui.SLEEP_MODE_DEEP })
    sys.timerStop(idle_timer)

    -- GT911 深度休眠（相位一）：deinit 释放 INT 后，重新拉低 INT >50ms
    -- GT911 检测到 INT 持续低电平 >50ms 后自动进入深度休眠
    -- 深度休眠下 GT911 停止扫描触摸，功耗从 ~3mA 降低到 <30μA
    -- 此时无法通过触摸唤醒设备，仅支持 PWR_KEY 唤醒
    if _G.tp_sleep_device then
        gpio.setup(2, 0, gpio.PULLDOWN)
        sys.wait(100)
    end

    display()
    gpio.setup(2, 0, gpio.PULLUP)

    -- 发布消息，触发 drv_lowpower 配置完整的模组低功耗模式
    -- drv_lowpower.lua 会：配置中断唤醒源、关闭非必要外设、
    -- 最后调用 pm.power(pm.WORK_MODE, 1) 让系统进入低功耗模式1
    sys.publish("DRV_SET_LOWPOWER")
    log.info("main", "=== Sleep done ===")
end

-- ==================== 从深度休眠唤醒 ====================

local function do_wake()
    -- 第一步：先切换功耗模式到常规模式
    -- drv_normal.lua 会：恢复必要外设供电（如 GPIO24 GNSS/GSensor）、
    -- 调用 pm.power(pm.WORK_MODE, 0) 退出低功耗模式
    sys.publish("DRV_SET_NORMAL")

    -- 恢复与触摸共用 I2C 的外设供电
    -- 必须先于 airui.wakeup()，确保触摸 I2C 总线通信正常
    gpio.set(147, 1)
    gpio.set(164, 1)

    if not is_sleeping then return end
    log.info("main", "=== Wakeup ===")
    -- 切换到常规工作模式（pm.WORK_MODE 0 是常规模式、非最低功耗模式）
    pm.power(pm.WORK_MODE, 0)
    -- 拉高 GPIO20(WAKEUP3) 作为 PWR_KEY 松手后的保持信号
    -- 某些版本核心板上 WAKEUP3 接 LED4，拉高并等待 20ms 确保稳定
    gpio.setup(20, 1, gpio.PULLUP); sys.wait(20)

    -- GT911 深度休眠唤醒（相位二）：拉高 INT 2-5ms
    -- GT911 检测到 INT 上升沿后从深度休眠中唤醒
    -- 之后 airui.wakeup() 内部的 C 层会自动调用 luat_tp_init 重新初始化 TP
    if _G.tp_sleep_device then
        gpio.setup(2, 1)
        sys.wait(5)
        gpio.close(2)
        sys.wait(10)
    end

    -- AirUI 唤醒：内部重新初始化 TP（luat_tp_init） + 恢复 LCD 显示
    airui.wakeup()
    airui.full_refresh()

    sys.timerLoopStart(idle_timer, 1000)
    is_sleeping = false; idle_sec = 0
    display()
    log.info("main", "=== Wakeup done ===")
end

-- ==================== 任务定义 ====================

-- 任务1：休眠/唤醒主循环
-- 等待 SLEEP_START → 执行深度休眠 (do_sleep)
-- 等待 SLEEP_WAKEUP → 执行唤醒 (do_wake)
local function sleep_task_func()
    while true do
        sys.waitUntil("SLEEP_START")
        do_sleep()
        local _, src = sys.waitUntil("SLEEP_WAKEUP")
        do_wake()
    end
end
sys.taskInit(sleep_task_func)

-- 任务2：按键事件处理
-- 监听所有 KEY_EVENT，收到 PWR_KEY 按下事件时触发送 SLEEP_WAKEUP
-- 在运行态收到按键事件也会重置空闲倒计时
local function key_task_func()
    while true do
        local _, name = sys.waitUntil("KEY_EVENT")
        if name then
            idle_sec = 0
            if is_sleeping and name == "pwr_down" then
                sys.publish("SLEEP_WAKEUP", name)
            end
        end
    end
end
sys.taskInit(key_task_func)

log.info("main", "Started, auto sleep in", IDLE_TIMEOUT, "s, POWER key to wake")
sys.run()
