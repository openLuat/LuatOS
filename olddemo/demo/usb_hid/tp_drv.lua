-- AirCAMERA_1032: GT911, I2C1, INT51, RST2 (board reference wiring).
local M = {}
i2c.setup(1, i2c.SLOW)
gpio.setup(2, 0)
gpio.close(2)
M.device = tp.init("gt911", {
    port=1, pin_rst=2, pin_int=51, int_type=1,
    w=1024, h=600, tp_num=5, direction=0, swap_xy=0,
})
-- GPIO2 is also used by this demo's LCD backlight; restore it after TP reset.
gpio.setup(2, 1)
assert(M.device, "TP init failed")
assert(airui.device_bind_touch(M.device), "TP AirUI bind failed")
log.info("tp_demo", "TP_INPUT_READY", "gt911", 1024, 600)

return M
