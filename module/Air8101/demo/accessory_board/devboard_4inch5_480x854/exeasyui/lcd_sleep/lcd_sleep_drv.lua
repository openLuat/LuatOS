--[[
@module  lcd_sleep_drv
@summary LCD休眠管理驱动模块
@version 1.0.0
@date    2026.01.16
@author  江访
@usage
本文件为LCD休眠管理驱动模块，核心业务逻辑为：
1、监听LCD休眠相关消息，执行对应操作；
2、管理自动休眠定时器，根据触摸事件或按键事件重置；
3、支持立即休眠操作和可覆盖触摸唤醒设置。

本文件无对外接口，require加载后自动执行初始化；
]]

-- 变量定义
local auto_sleep_switch = true -- 自动休眠开关
local auto_sleep_time = 10000  -- 自动休眠时间(毫秒)
local tp_wakeup_switch = true  -- 触摸唤醒开关
local sleeping_status = false  -- 休眠状态

--[[
@function msg_handle
@summary 消息处理函数
@param msg 消息类型
@param auto_sleep 自动休眠开关（SET_AUTO_SLEEP消息）
@param tp_wakeup 触摸唤醒开关（SET_AUTO_SLEEP消息）
@param sleep_time 休眠时间（SET_AUTO_SLEEP消息）
@return nil
]]
local function msg_handle(msg, auto_sleep, tp_wakeup, sleep_time)
    if msg == "TOUCH_DOWN" or msg == 1 then
        msg = "BASE_TOUCH_EVENT"
    end
    -- 处理SET_AUTO_SLEEP消息（所有状态都处理）
    if msg == "SET_AUTO_SLEEP" then
        -- 更新配置
        if auto_sleep ~= nil then auto_sleep_switch = auto_sleep end
        if tp_wakeup ~= nil then tp_wakeup_switch = tp_wakeup end
        if sleep_time ~= nil then auto_sleep_time = sleep_time end

        if auto_sleep_switch and not sleeping_status then
            sys.timerStart(msg_handle, auto_sleep_time, "AUTO_SLEEP")
        elseif not auto_sleep_switch then
            sys.timerStop(msg_handle, "AUTO_SLEEP")
        end

        log.info("lcd_sleep_drv", "更新配置:",
            "自动休眠:", auto_sleep_switch,
            "触摸唤醒:", tp_wakeup_switch,
            "休眠时间:", auto_sleep_time, "ms")
        return
    end

    -- 1. 唤醒状态(自动休眠开启)
    if not sleeping_status and auto_sleep_switch then
        if msg == "BASE_TOUCH_EVENT" or msg == "KEY_WAKEUP" then
            -- 重置定时器
            sys.timerStart(msg_handle, auto_sleep_time, "AUTO_SLEEP")
            log.info("lcd_sleep_drv", "唤醒状态(自动休眠): 重置定时器")
        elseif msg == "AUTO_SLEEP" or msg == "FORCE_SLEEP" then
            -- 进入休眠，关闭定时器
            log.info("lcd_sleep_drv", "唤醒状态(自动休眠): 进入休眠")
            if tp_wakeup_switch then
                ui.sleep(true)
                log.info("lcd_sleep_drv", "进入休眠(启用触摸)")
            else
                ui.sleep(false)
                log.info("lcd_sleep_drv", "进入休眠(禁用触摸)")
            end
            sys.timerStop(msg_handle, "AUTO_SLEEP")
            sleeping_status = true
        end
        -- 2. 唤醒状态(不自动休眠)
    elseif not sleeping_status and not auto_sleep_switch then
        if msg == "BASE_TOUCH_EVENT" or msg == "KEY_WAKEUP" or msg == "AUTO_SLEEP" then
            sys.timerStop(msg_handle, "AUTO_SLEEP")
            -- 关闭定时器，过滤消息
            log.info("lcd_sleep_drv", "唤醒状态(不自动休眠): 关闭定时器")
        elseif msg == "FORCE_SLEEP" then
            -- 立即休眠，等待触摸和按键消息，停止定时器
            sleeping_status = true
            sys.timerStop(msg_handle, "AUTO_SLEEP")
            log.info("lcd_sleep_drv", "唤醒状态(不自动休眠): 立即休眠")

            if tp_wakeup_switch then
                ui.sleep(true)
                log.info("lcd_sleep_drv", "强制进入休眠(启用触摸)")
            else
                ui.sleep(false)
                log.info("lcd_sleep_drv", "强制进入休眠(禁用触摸)")
            end
        end
        -- 3. 休眠状态（启用触摸）
    elseif sleeping_status and tp_wakeup_switch then
        if msg == "BASE_TOUCH_EVENT" or msg == "KEY_WAKEUP" then
            -- 重新启动定时器，刷新、唤醒
            log.info("lcd_sleep_drv", "休眠状态(启用触摸): 触摸唤醒")
            ui.wakeup()
            ui.refresh()
            sleeping_status = false
            sys.timerStart(msg_handle, auto_sleep_time, "AUTO_SLEEP")
        elseif msg == "AUTO_SLEEP" or msg == "FORCE_SLEEP" then
            -- 过滤
            log.info("lcd_sleep_drv", "休眠状态(启用触摸): 过滤定时休眠消息")
        end
        -- 4. 休眠状态（禁用触摸）
    elseif sleeping_status and not tp_wakeup_switch then
        if msg == "BASE_TOUCH_EVENT" or msg == "AUTO_SLEEP" or msg == "FORCE_SLEEP" then
            -- 过滤
            log.info("lcd_sleep_drv", "休眠状态(禁用触摸): 过滤触摸消息")
        elseif msg == "KEY_WAKEUP" then
            -- 重新启动定时器，刷新、唤醒
            log.info("lcd_sleep_drv", "休眠状态(禁用触摸): 按键唤醒")
            ui.wakeup()
            ui.refresh()
            sleeping_status = false
            sys.timerStart(msg_handle, auto_sleep_time, "AUTO_SLEEP")
        end
    end
end

--[[
@function init_driver
@summary 初始化驱动函数
@description 启动所有消息处理任务
@return nil
]]
local function init_driver()
    -- 订阅所有消息
    sys.subscribe("BASE_TOUCH_EVENT", msg_handle)

    sys.subscribe("KEY_WAKEUP", msg_handle)

    sys.subscribe("FORCE_SLEEP", msg_handle)

    sys.subscribe("SET_AUTO_SLEEP", msg_handle)

    if auto_sleep_time then
        sys.timerStart(msg_handle, auto_sleep_time, "AUTO_SLEEP")
    end

    log.info("lcd_sleep_drv", "LCD休眠管理驱动初始化完成")
    log.info("lcd_sleep_drv", "当前配置:",
        "自动休眠:", auto_sleep_switch and "开启" or "关闭",
        "触摸唤醒:", tp_wakeup_switch and "开启" or "关闭",
        "休眠时间:", auto_sleep_time, "ms")
end

-- 初始化驱动
init_driver()