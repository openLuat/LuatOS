local air_touch = {}

log.info("tp", "tp init")
local function tp_callBack(tp_device, tp_data)
    log.info("TP", tp_data[1].x, tp_data[1].y, tp_data[1].event)
    sys.publish("TP", tp_device, tp_data)
end

function air_touch.init()
    log.info("tp", "tp init function start")
    local i2c_id = 1
    i2c.setup(i2c_id)

    tp_device = tp.init("gt911", {
        port = i2c_id,
        pin_int = gpio.WAKEUP0
    }, tp_callBack)

log.info("tp", "tp init function end")
end

return air_touch
