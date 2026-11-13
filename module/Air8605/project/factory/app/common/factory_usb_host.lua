-- Only called on final camera-page exit, after excamera.close; never during face capture.
local M = {}
function M.shutdown()
    assert(usb and usb.on and pm and pm.power and pm.USB, "USB Host stop API unavailable")
    assert(camera and camera.on and camera.USB, "camera USB callback API unavailable")
    assert(camera.on(camera.USB, "usb_raw", nil) ~= false, "USB raw callback removal failed")
    assert(camera.on(camera.USB, "scanned", nil) ~= false, "USB scan callback removal failed")
    local result = usb.on(0, nil)
    assert(result ~= false, "USB callback removal failed")
    result = pm.power(pm.USB, false)
    assert(result ~= false, "USB Host power off failed")
    -- Allow pending native events to unwind before destroying the display widget.
    sys.wait(100)
    log.info("factory_handoff", "USB_HOST_OFF")
    return true
end
return M
