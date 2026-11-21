-- drv_power.lua  屏幕供电 / 背光 PWM
-- 先 0 占空比（黑屏）把界面搭完，再点亮背光：避免开机看到搭界面的过程。

local cfg = require "app_config"
local S = cfg.HW.screen
local M = {}

function M.power_on()
  pwm.setup(S.pwm_ch, S.pwm_freq, 0)   -- 背光先关死，界面搭完再点亮
  pwm.start(S.pwm_ch)
  -- 供电使能只在真的独立接了引脚时才动；和 pin_rst 撞车会打乱复位时序
  if type(S.pin_pwr) == "number" and S.pin_pwr >= 0 and S.pin_pwr ~= S.pin_rst then
    gpio.setup(S.pin_pwr, 0)
  end
  -- 复位脉冲：低 → 高（10ms 足够 RGB 屏的复位窗口）
  gpio.setup(S.pin_rst, 0)
  sys.wait(10)
  gpio.setup(S.pin_rst, 1)
  sys.wait(100)
end

-- duty 0~100（pwm.setup 无返回值，不能拿它当成败判据）
function M.backlight_on(duty)
  duty = duty or 100
  pwm.setup(S.pwm_ch, S.pwm_freq, duty)
  pwm.start(S.pwm_ch)
  log.info("drv_power", "背光已点亮", duty .. "%")
  return true
end

return M
