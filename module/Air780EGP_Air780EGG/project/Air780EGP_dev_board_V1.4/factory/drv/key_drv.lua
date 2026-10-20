--[[
@module  key_drv
@summary 按键驱动（BOOT 键 + PWR 键）
@version 1.0
@date    2026.10.16
@usage
初始化 BOOT 键(GPIO0) 和 PWR 键(gpio.PWR_KEY) 的 GPIO 中断，50ms 防抖，
对外发布按键消息 "KEY_EVENT"。

按键事件：
  boot_down / boot_up
  pwr_down / pwr_up
]]

local key_drv = {}

local key_boot = 0           -- GPIO0 按键（BOOT 键）
local key_pwr = gpio.PWR_KEY -- 电源按键

local function handle_boot_key(val)
    if val == 1 then
        sys.publish("KEY_EVENT", "boot_down")
    else
        sys.publish("KEY_EVENT", "boot_up")
    end
end

local function handle_pwr_key(val)
    if val == 1 then
        sys.publish("KEY_EVENT", "pwr_up")
    else
        sys.publish("KEY_EVENT", "pwr_down")
    end
end

function key_drv.init()
    gpio.setup(key_boot, handle_boot_key, gpio.PULLDOWN, gpio.BOTH)
    gpio.debounce(key_boot, 50, 0)     -- 50ms 防抖

    gpio.setup(key_pwr, handle_pwr_key, gpio.PULLUP, gpio.BOTH)
    gpio.debounce(key_pwr, 50, 0)

    log.info("key_drv", "按键初始化完成")
    return true
end

key_drv.init()
return key_drv
