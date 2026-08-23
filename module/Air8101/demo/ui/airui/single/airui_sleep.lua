--[[
@module  airui_sleep
@summary AirUI 休眠演示
          GT911 深度休眠（INT 拉低 >50ms）+ AirUI 自动休眠/唤醒管理
          触摸可重置倒计时，休眠后仅按 GPIO2（65号引脚）唤醒
@version 1.3
@date    2026.06.12
@author  江访
@usage
依赖模块（由 main.lua 先后加载）：
  lcd_drv         → lcd.init + airui.init + 字体加载
  tp_drv         → tp.init + airui.device_bind_touch + 设置 _G.tp_sleep_device
  airui_sleep    → 本文件

注意：
  Air8101 无 PWR_KEY，使用 GPIO2（65号引脚）作为唤醒按键。
  airui.sleep({power_down_lcd=true}) 内部自动休眠 TP 和 LCD，
  退出后需重新拉低 INT >50ms 让 GT911 进入深度休眠。
  airui.wakeup() 内部自动重新初始化 TP。
]]

PROJECT = "Sleep_Demo"
VERSION = "001.999.001"
log.info("main", PROJECT, VERSION)

local IDLE_TIMEOUT = 30
local KEY_WAKE = 65                -- GPIO2（Air8101 无 PWR_KEY，用 65 号引脚替代）

local is_sleeping = false
local idle_sec = 0

-- ==================== 按键初始化 ====================

local function key_down(name)
    sys.publish("KEY_EVENT", name .. "_down")
end
local function key_up(name)
    sys.publish("KEY_EVENT", name .. "_up")
end

gpio.setup(KEY_WAKE, function(v)
    if v == 1 then key_up("wake") else key_down("wake") end
end, gpio.PULLUP, gpio.BOTH)
gpio.debounce(KEY_WAKE, 50, 0)

-- ==================== 触摸重置空闲计时 ====================

airui.touch_subscribe(function(state)
    if not is_sleeping and (state == 1 or state == 4) then
        idle_sec = 0
    end
end)

-- ==================== AirUI 显示 ====================

local sw, sh = 800, 480

airui.label({text = "休眠演示", x = 20, y = 20, w = 760, h = 30, font_size = 22, color = 0x000000})
local st_label = airui.label({text = "运行中", x = 20, y = 70, w = 760, h = 26, font_size = 18, color = 0x000000})
local ct_label = airui.label({text = "", x = 20, y = 110, w = 760, h = 26, font_size = 18, color = 0x000000})
local wk_label = airui.label({text = "触摸可重置倒计时", x = 20, y = 150, w = 760, h = 22, font_size = 16, color = 0x808080})
local pw_label = airui.label({text = "休眠后按 GPIO2 唤醒", x = 20, y = sh - 40, w = 760, h = 22, font_size = 16, color = 0x808080})

local function display()
    local r = math.max(0, IDLE_TIMEOUT - idle_sec)
    if is_sleeping then
        st_label:set_text("深度休眠中")
        ct_label:set_text("")
        wk_label:set_text("")
        pw_label:set_text("休眠后按 GPIO2 唤醒")
    else
        st_label:set_text("运行中")
        ct_label:set_text(r .. " 秒后进入深度休眠")
        wk_label:set_text("触摸可重置倒计时")
        pw_label:set_text("休眠后按 GPIO2 唤醒")
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

-- ==================== 休眠 ====================

local function do_sleep()
    if is_sleeping then return end
    is_sleeping = true
    log.info("main", "=== Sleep ===")

    -- airui.sleep() 内部按顺序：关中断 → tp.sleep(写 0x05) → deinit(释放 INT 脚) → LCD sleep
    airui.sleep({ power_down_lcd = true, mode = airui.SLEEP_MODE_DEEP })
    sys.timerStop(idle_timer)

    -- GT911 深度休眠：deinit 释放 INT 后，重新拉低 INT 并维持 >50ms
    -- Air8101 tp_drv 中 pin_int = 7
    if _G.tp_sleep_device then
        gpio.setup(7, 0, gpio.PULLDOWN)
        sys.wait(100)
    end

    display()
    pm.power(pm.WORK_MODE, 1)
    log.info("main", "=== Sleep done ===")
end

-- ==================== 唤醒 ====================

local function do_wake()
    if not is_sleeping then return end
    log.info("main", "=== Wakeup ===")

    pm.power(pm.WORK_MODE, 0)
    sys.wait(20)

    -- GT911 深度休眠唤醒：拉高 INT 2-5ms 唤醒 GT911
    if _G.tp_sleep_device then
        gpio.setup(7, 1)
        sys.wait(5)
        gpio.close(7)
        sys.wait(10)
    end

    -- AirUI 唤醒（C 层自动重新初始化 TP + 恢复显示）
    airui.wakeup()
    airui.full_refresh()

    sys.timerLoopStart(idle_timer, 1000)
    is_sleeping = false; idle_sec = 0
    display()
    log.info("main", "=== Wakeup done ===")
end

-- ==================== 任务 ====================

sys.taskInit(function()
    while true do
        sys.waitUntil("SLEEP_START")
        do_sleep()
        local _, src = sys.waitUntil("SLEEP_WAKEUP")
        do_wake()
    end
end)

sys.taskInit(function()
    while true do
        local _, name = sys.waitUntil("KEY_EVENT")
        if name then
            idle_sec = 0
            if is_sleeping and name == "wake_down" then
                sys.publish("SLEEP_WAKEUP", name)
            end
        end
    end
end)

log.info("main", "Started, auto sleep in", IDLE_TIMEOUT, "s, GPIO2 key to wake")
