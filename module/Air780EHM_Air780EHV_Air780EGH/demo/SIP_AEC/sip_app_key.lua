-- Air780EHV开发板：BOOT呼出/接听，POWERKEY挂断/拒接。
local cfg = require("config").keys
if not cfg.enabled then return end

local function on_boot_pressed()
    sys.publish("SIP_APP_MAIN_PRIMARY_REQ")
end

local function on_power_pressed()
    sys.publish("SIP_APP_MAIN_HANGUP_REQ", "POWERKEY")
end

gpio.setup(cfg.boot_gpio, on_boot_pressed, gpio.PULLDOWN, gpio.RISING)
gpio.debounce(cfg.boot_gpio, cfg.debounce_ms, 1)
gpio.setup(gpio.PWR_KEY, on_power_pressed, gpio.PULLUP, gpio.FALLING)
gpio.debounce(gpio.PWR_KEY, cfg.debounce_ms, 1)
