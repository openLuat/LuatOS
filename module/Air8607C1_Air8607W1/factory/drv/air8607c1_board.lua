local config = require "air8607c1_config"
local baseboard = require "air8607c1_baseboard"
local M = {}

function M.is_target()
    return rtos.bsp() == "PC" or (hmeta and hmeta.chip and hmeta.chip() == "CCM4211")
end

function M.set_backlight(duty)
    if rtos.bsp() == "PC" then return true end
    local bl = config.hw.lcd.backlight
    return pwm.setup(bl.pwm_ch, bl.pwm_freq, duty) and pwm.start(bl.pwm_ch)
end

-- W1 的 USB VBUS 取自 PWM1/GPIO65。始终用 PWM 控制，避免切成 GPIO 后无法恢复 PWM 复用。
function M.set_pwm1(duty)
    if rtos.bsp() == "PC" then return true end
    local p = config.pwm_test
    return pwm.setup(p.channel, p.hz, duty) and pwm.start(p.channel)
end

function M.init_outputs()
    if rtos.bsp() == "PC" then return true end
    local ok, output = pcall(gpio.setup, config.buzzer.pin, 0)
    if not ok or not output then log.warn("factory", "BUZ1 GPIO73 初始化失败", output) end

    -- W 系列上电即开 Air6205 电源，下载口和 SPI Wi-Fi 测试都不再依赖测试页临时上电。
    if baseboard.current().wifi then
        local wifi = config.w1.wifi
        local wifi_ok, wifi_output = pcall(gpio.setup, wifi.power, 1)
        if not wifi_ok or not wifi_output then
            log.warn("factory", "WiFi GPIO72 上电拉高失败", wifi_output)
        end
    end
    return M.set_backlight(0)
end

return M