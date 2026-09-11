-- 原始 input 事件与 AirUI 同时消费。移动事件只做计数，避免串口刷屏。
local demo = {frames=0, events=0, key_frames=0, devices={}, held=nil}
assert(type(input.list) == "function", "input module missing")
log.info("input_demo", "LIST", json.encode(input.list()))

demo.subscription = assert(input.subscribe({queue_bytes=4096}, function(kind, id, data)
    if kind == "attach" then
        assert(data.id == id and data.state.id == id)
        demo.devices[id] = data.name
        log.info("input_demo", "ATTACH", id, data.name,
            string.format("%04x:%04x", data.vendor, data.product), data.resync or false)
        local info = input.info(id)
        if info and info.caps.mt_slots > 0 then demo.touch_id = id end
        if info then
            -- Axis codes are sparse numeric keys; encode them as JSON object keys.
            local caps = {}
            for name, value in pairs(info.caps) do
                if name == "abs" or name == "mt" then
                    local axes = {}
                    for code, axis in pairs(value) do axes[tostring(code)] = axis end
                    caps[name] = axes
                else
                    caps[name] = value
                end
            end
            log.info("input_demo", "CAPS", id, json.encode(caps))
        end
    elseif kind == "remove" then
        demo.devices[id] = nil
        if demo.touch_id == id then demo.touch_id = nil end
        local gone, why = input.info(id)
        assert(gone == nil and why == "not_found", "stale device id survived removal")
        log.info("input_demo", "REMOVE", id, "STALE_ID_OK")
    elseif kind == "reset" then
        log.info("input_demo", "RESET", id, data.state.sequence)
    elseif kind == "overflow" then
        demo.devices = {}
        log.warn("input_demo", "OVERFLOW", data.reason, data.required_bytes)
    elseif kind == "frame" then
        demo.frames = demo.frames + 1
        demo.events = demo.events + data.count
        assert(data.device_id == id and #data == data.count)
        if not demo.held and data.count > 0 then
            local t,c,v = data:get(1)
            demo.held = {frame=data, t=t, c=c, v=v}
            assert(not pcall(function() data.count=0 end), "frame must be read-only")
        end
        for i=1,data.count do
            local t,c,v = data:get(i)
            if t == input.EV_ABS and c == input.ABS_MT_TRACKING_ID then
                log.info("input_demo", "TP_TRACKING", id, data.sequence, v)
            end
            if t == input.EV_KEY or (t == input.EV_REL and c == input.REL_WHEEL) then
                log.info("input_demo", "EVENT", id, data.sequence, t, c, v)
            end
        end
    end
end))

demo.keys = assert(input.subscribe({types={input.EV_KEY},queue_bytes=2048}, function(kind,id,data)
    if kind ~= "frame" then return end
    for i=1,data.count do assert(data:get(i) == input.EV_KEY, "event filter failed") end
    demo.key_frames = demo.key_frames + 1
    if demo.key_frames == 1 then
        assert(input.state(id), "state query failed in callback")
        log.info("input_demo", "KEY_FILTER_AND_STATE_OK", id)
    end
end))

sys.timerLoopStart(function()
    if demo.held then
        local t,c,v = demo.held.frame:get(1)
        assert(t == demo.held.t and c == demo.held.c and v == demo.held.v, "retained frame changed")
    end
    local stat = demo.subscription:stats()
    log.info("input_demo", "INPUT_LUA_STABLE", demo.frames, demo.events, demo.key_frames,
        "queued", stat.queued_bytes, "overflow", stat.overflows, "closed", stat.closed)
end, 10000)

sys.timerLoopStart(function()
    if not demo.touch_id then return end
    local state = assert(input.state(demo.touch_id))
    local contacts = {}
    for slot, axes in pairs(state.slots) do
        local tracking = axes[input.ABS_MT_TRACKING_ID]
        if tracking and tracking >= 0 then
            contacts[#contacts+1] = string.format("%d:%d@%d,%d", slot, tracking,
                axes[input.ABS_MT_POSITION_X], axes[input.ABS_MT_POSITION_Y])
        end
    end
    log.info("input_demo", "TP_STATE", #contacts, table.concat(contacts, " "),
        "pressed", state.keys[input.BTN_TOUCH] or false)
end, 2000)

log.info("input_demo", "INPUT_LUA_API_READY")
return demo
