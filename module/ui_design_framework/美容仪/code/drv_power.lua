-- drv_power.lua  屏幕供电 / 背光 PWM

local cfg = require "app_config"
local S = cfg.HW.screen
local M = {}

-- 上电与背光：PWM 先 0 占空比（黑屏），UI 搭好后再调 backlight_on
function M.power_on()
  pwm.setup(S.pwm_ch, S.pwm_freq, 0)
  pwm.start(S.pwm_ch)
  gpio.setup(S.pin_pwr, 0)      -- LCD 供电使能（低有效，按原理图调整）
  gpio.setup(S.pin_rst, 1)      -- LCD 复位/显示使能
  sys.wait(100)
end

-- 点亮背光：duty 0~100，默认 100
function M.backlight_on(duty)
  duty = duty or 100
  if pwm.setup(S.pwm_ch, S.pwm_freq, duty) then
    pwm.start(S.pwm_ch)
    log.info("drv_power", "背光已点亮", duty .. "%")
    return true
  end
  log.error("drv_power", "背光初始化失败，请检查 PWM 通道")
  return false
end

return M
