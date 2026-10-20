-- 板载 SOS：呼出/接听；UP：挂断/拒接。PWRKEY 已由R9常下拉，不作按键。
local cfg = require("config").keys
if not cfg.enabled then return end
gpio.setup(cfg.vref_gpio, 1)
local function on_sos_pressed()
    sys.publish("SIP_APP_MAIN_PRIMARY_REQ")
end
gpio.setup(cfg.sos_gpio, on_sos_pressed, gpio.PULLUP, gpio.FALLING)
local function on_up_pressed()
    sys.publish("SIP_APP_MAIN_HANGUP_REQ", "UP")
end
gpio.setup(cfg.up_gpio, on_up_pressed, gpio.PULLUP, gpio.FALLING)
gpio.debounce(cfg.sos_gpio, cfg.debounce_ms, 1)
gpio.debounce(cfg.up_gpio, cfg.debounce_ms, 1)
