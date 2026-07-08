PROJECT = "camera_pc_basic"
VERSION = "1.0.0"
sys = require("sys")

sys.taskInit(function()
    local cap_path = "/pc_capture.jpg"

    camera.on(0, "scanned", function(id, evt)
        if evt == true then
            log.info("camera", "capture done")
        elseif evt == false then
            log.error("camera", "capture failed")
        elseif type(evt) == "number" then
            log.info("camera", "raw frame size", evt)
        end
    end)

    local cam_id = camera.init({
        id = 0,
        sensor_width = 640,
        sensor_height = 480,
        color_bit = 16,
    })
    log.info("camera", "init", cam_id)
    if not cam_id or cam_id ~= 0 then
        log.error("camera", "init failed")
        os.exit(1)
    end

    camera.start(0)
    camera.capture(0, cap_path, 80)
    sys.waitUntil("capture_done", 10000)
    camera.stop(0)
    camera.close(0)

    local fd = io.open(cap_path, "rb")
    if fd then
        local sz = fd:seek("end")
        fd:close()
        log.info("camera", "jpg size", sz)
        if sz and sz > 1000 then
            log.info("camera", "TEST PASS")
        else
            log.error("camera", "TEST FAIL: file too small")
        end
    else
        log.error("camera", "TEST FAIL: no output file")
    end
    os.exit(0)
end)

sys.run()
