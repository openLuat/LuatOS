-- drv_tp.lua  GT911 电容触摸初始化 + 绑定到 airui

local cfg = require "app_config"
local T = cfg.HW.tp
local M = {}

local INT_TYPE = { falling = tp.FALLING, rising = tp.RISING }
local dev = nil

function M.init()
  if rtos.bsp() == "PC" then
    log.info("drv_tp", "PC 模拟器，跳过触摸初始化")
    return true
  end
  gpio.setup(T.pin_rst, 0)
  gpio.close(T.pin_rst)
  i2c.setup(T.i2c_id)

  dev = tp.init(T.ic, {
    port = T.i2c_id,
    pin_rst = T.pin_rst,
    pin_int = T.pin_int,
    int_type = INT_TYPE[T.int_type] or tp.FALLING,
    w = cfg.HW.screen.w,
    h = cfg.HW.screen.h,
  })
  if not dev then
    log.error("drv_tp", "触摸初始化失败", T.ic)
    return false
  end
  airui.device_bind_touch(dev)
  log.info("drv_tp", "触摸已绑定", T.ic, T.i2c_id, T.pin_rst, T.pin_int)
  return true
end

return M
