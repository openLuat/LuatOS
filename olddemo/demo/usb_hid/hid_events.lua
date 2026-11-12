-- USB HID events are separate from the AirUI pointer and touch handlers.
local frames, events = 0, 0
local sub = assert(usb.hid_subscribe({}, function(kind, id, data)
    if kind == "frame" then
        frames = frames + 1
        events = events + data.count
    elseif kind == "attach" then
        log.info("usb_hid", "ATTACH", id, data.name, data.vendor, data.product, data.resync)
    elseif kind == "overflow" then
        log.warn("usb_hid", "OVERFLOW", data.reason, data.required_bytes)
    else
        log.info("usb_hid", kind, id)
    end
end))

-- This closure keeps the subscription alive while the demo is running.
sys.timerLoopStart(function()
    local stat = sub:stats()
    log.info("usb_hid", "HID_LUA_STABLE", frames, events,
        "queued", stat.queued_bytes, "overflow", stat.overflows, "closed", stat.closed)
end, 10000)

log.info("usb_hid", "HID_LUA_API_READY")
