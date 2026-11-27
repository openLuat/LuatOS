local cfg = require "air8801_config"
local M = {}

function M.set_backlight(duty)
    if rtos.bsp() == "PC" then return true end
    local bl = cfg.hw.lcd.backlight
    return pwm.setup(bl.pwm_ch, bl.pwm_freq, duty) and pwm.start(bl.pwm_ch)
end

function M.init_outputs()
    if rtos.bsp() == "PC" then return true end
    assert(gpio.setup(cfg.serial.power, 0), "RS232_EN")
    assert(gpio.setup(cfg.sd.power, 0), "SD_EN")
    assert(gpio.setup(cfg.buzzer.pin, 0), "BUZZER")
    return M.set_backlight(0)
end

--[[播放提示音。ms 缺省 30（页面切换用短促一声），hz 缺省走配置的 2700Hz。
用定时器关断而不是 sys.wait，因为左栏点击回调跑在 UI 线程，阻塞 30ms 会卡一帧。
连续触发时先停掉上一个定时器并重开通道，避免前一声的关断动作把后一声掐掉。]]
local beep_timer
function M.beep(ms, hz)
    if rtos.bsp() == "PC" then return true end
    local b = cfg.buzzer
    if beep_timer then
        sys.timerStop(beep_timer)
        beep_timer = nil
    end
    pcall(pwm.close, b.channel)
    if not pwm.open(b.channel, hz or b.hz, 50) then return false end
    beep_timer = sys.timerStart(function()
        beep_timer = nil
        pwm.close(b.channel)
        gpio.setup(b.pin, 0)
    end, ms or 30)
    return true
end

return M
