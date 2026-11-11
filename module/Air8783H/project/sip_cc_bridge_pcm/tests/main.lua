PROJECT = "SIP_CC_NOTICE_TEST"
VERSION = "1.0.0"

-- Run with --dep_strip=0, passing tests/ and sip_cc/ as the two script directories.
-- All modem, SIP and playback boundaries are mocked; the real bridge.lua is loaded.
local real_sys = require "sys"
local real_log = log
local bridge_source = assert(io.readFile("/luadb/bridge.lua"))

local function fixture(codec)
    local f = {now = 0, timers = {}, next_timer = 0, events = {}, handlers = {},
        state = "cc_idle", generation = 1, owner = nil, plays = {}, muted = false,
        stats = {selected = true, session = 101, active = 0, media_ready = 0,
            dl_queued = 0, ul_queued = 0, sdk_active = 0, sdk_pending = 0, sdk_stop_waiting = 0},
        status = {id = 0, state = "idle"}}
    function f.emit(name, ...)
        if f.handlers[name] then f.handlers[name](...) end
    end
    function f.count(name)
        local n = 0
        for _, event in ipairs(f.events) do if event[1] == name then n = n + 1 end end
        return n
    end
    function f.advance(ms)
        local deadline = f.now + ms
        for _ = 1, 1000 do
            local next_id, due
            for id, timer in pairs(f.timers) do
                if timer.at <= deadline and (not due or timer.at < due) then next_id, due = id, timer.at end
            end
            if not next_id then f.now = deadline; return end
            f.now = due
            local timer = f.timers[next_id]
            f.timers[next_id] = nil
            timer.fn(table.unpack(timer.args))
        end
        error("timer loop did not settle")
    end
    sys = {
        subscribe = function(name, fn) f.handlers[name] = fn end,
        publish = function(name, ...)
            table.insert(f.events, {name, ...})
            f.emit(name, ...)
        end,
        timerStart = function(fn, ms, ...)
            if f.fail_timer and ms == 500 then return nil end
            f.next_timer = f.next_timer + 1
            f.timers[f.next_timer] = {fn = fn, at = f.now + ms, args = {...}}
            return f.next_timer
        end,
        timerStop = function(id)
            if type(id) == "function" then
                for key, timer in pairs(f.timers) do if timer.fn == id then f.timers[key] = nil end end
            else f.timers[id] = nil end
        end,
    }
    mcu = {ticks2 = function() return 0, f.now end}
    log = {info = function() end, warn = function() end, error = function() end}
    local function play(source, options)
        if f.fail_play then return nil, "file_error" end
        table.insert(f.plays, {source = source, target = options.target, mode = options.mode})
        f.status = {id = #f.plays, state = "playing"}
        return f.status.id
    end
    voip = {
        on = function(name, fn) assert(name == "play"); f.play_event = fn end,
        playFile = play, playTTS = play,
        playStop = function(id) f.stopped = id; return true end,
        playStatus = function() return f.status end,
        bridgeMute = function(mute) f.muted = mute; return true end,
    }
    local modules = {}
    modules.config = {codec = codec or "PCMA", auto_answer_sip = true,
        auto_handle_mobile_incoming = true, remote_sip_uri = "sip:callee@example.invalid",
        target_phone_number = "test-number", cc_media_reboot_on_error = false}
    modules.exsipproto = {normalize_codec_name = function(name) return name end}
    modules.cc_main = {
        get_stats = function() return f.stats end,
        get_state = function() return f.state end,
        get_generation = function() return f.generation end,
        claim_owner = function(generation, owner) f.owner = owner; return generation == f.generation end,
        is_media_idle = function() return f.stats.active == 0 end,
    }
    modules.pcm_sip = {is_media_idle = function() return true end}
    require = function(name) return assert(modules[name], "unexpected dependency: " .. name) end
    f.bridge = assert(load(bridge_source, "bridge.lua"))()
    function f.incoming()
        local accepts, dials = f.count("CC_ACCEPT_REQ"), f.count("SIP_DIAL_REQ")
        f.state, f.stats.active = "cc_ringing", 1
        f.emit("CC_INCOMING", "test-caller", f.generation, f.stats.session)
        assert(f.count("CC_ACCEPT_REQ") == accepts + 1, "CC must be answered before SIP dialing")
        assert(f.count("SIP_DIAL_REQ") == dials, "SIP must wait for notice completion")
    end
    function f.connected()
        f.state, f.stats.media_ready = "cc_connected", 1
        f.emit("CC_CONNECTED", f.generation, f.owner, f.stats.session)
    end
    function f.ready()
        f.incoming()
        f.connected()
        f.advance(500)
    end
    function f.ended()
        f.state, f.stats.active, f.stats.media_ready = "cc_idle", 0, 0
        f.emit("CC_DISCONNECTED", "remote_hangup", f.generation, f.owner, f.stats.session)
    end
    function f.finish(event, id)
        f.play_event(event, {id = id or f.status.id, state = "idle", reason = event})
    end
    return f
end

local tests = {}
function tests.test_cc_notice_then_sip_once()
    local f = fixture()
    f.ready()
    assert(#f.plays == 1 and f.plays[1].target == "cc" and f.plays[1].mode == "replace")
    assert(not f.muted and f.count("SIP_DIAL_REQ") == 0)
    f.connected()
    f.finish("done", 99)
    assert(f.count("SIP_DIAL_REQ") == 0, "stale playback must not dial")
    f.finish("done")
    f.finish("done")
    assert(f.count("SIP_DIAL_REQ") == 1)
    f.emit("SIP_CONNECTED", "sip-call", 7, f.owner)
    f.advance(1000)
    assert(#f.plays == 1, "SIP connection must not replay the notice")
end
function tests.test_notice_is_independent_of_sip_codec()
    for _, codec in ipairs({"G729", "G722"}) do
        local f = fixture(codec)
        f.ready()
        assert(#f.plays == 1 and f.plays[1].target == "cc")
        f.finish("done")
        assert(f.count("SIP_DIAL_REQ") == 1)
    end
end
function tests.test_playback_error_or_cancel_does_not_dial()
    for _, event in ipairs({"error", "stopped"}) do
        local f = fixture()
        f.ready()
        f.finish(event)
        assert(f.count("CC_HANGUP_REQ") == 1 and f.count("SIP_DIAL_REQ") == 0)
        f.finish("done")
        assert(f.count("SIP_DIAL_REQ") == 0)
    end
end
function tests.test_submission_failure_or_timer_failure_hangs_up()
    for _, failure in ipairs({"fail_play", "fail_timer"}) do
        local f = fixture()
        f[failure] = true
        f.ready()
        assert(f.count("CC_HANGUP_REQ") == 1 and f.count("SIP_DIAL_REQ") == 0)
    end
end
function tests.test_hangup_before_or_during_playback()
    local f = fixture()
    f.incoming()
    f.connected()
    f.ended()
    f.advance(1000)
    assert(#f.plays == 0 and f.count("SIP_DIAL_REQ") == 0)
    f = fixture()
    f.ready()
    f.ended()
    assert(f.stopped == 1)
    f.finish("done")
    assert(f.count("SIP_DIAL_REQ") == 0)
end
function tests.test_native_media_loss_before_done()
    local f = fixture()
    f.ready()
    f.stats.media_ready = 0
    f.finish("done")
    assert(f.count("CC_HANGUP_REQ") == 1 and f.count("SIP_DIAL_REQ") == 0)
end
function tests.test_old_playback_callback_does_not_dial_new_call()
    local f = fixture()
    f.ready()
    f.ended()
    f.advance(500)
    f.generation, f.stats.session = 2, 102
    f.ready()
    assert(#f.plays == 2)
    f.finish("done", 1)
    assert(f.count("SIP_DIAL_REQ") == 0)
    f.finish("done", 2)
    assert(f.count("SIP_DIAL_REQ") == 1)
end
function tests.test_idle_status_fallback_checks_reason()
    for _, reason in ipairs({"done", "stopped", "decode_error"}) do
        local f = fixture()
        f.ready()
        f.status = {id = 1, state = "idle", reason = reason}
        f.advance(100)
        assert(f.count("SIP_DIAL_REQ") == (reason == "done" and 1 or 0))
        assert(f.count("CC_HANGUP_REQ") == (reason == "done" and 0 or 1))
        f.finish("done")
        assert(f.count("SIP_DIAL_REQ") == (reason == "done" and 1 or 0))
    end
end
function tests.test_sip_incoming_keeps_both_notice()
    local f = fixture()
    f.emit("SIP_INCOMING", "caller", "sip:callee@example.invalid", "callee", "inbound", 8)
    assert(f.count("SIP_PROGRESS_REQ") == 1)
    f.emit("SIP_PROGRESSING", "inbound", 8)
    assert(f.count("CC_DIAL_REQ") == 1)
    f.owner = f.events[#f.events][3]
    f.stats.active = 1
    f.connected()
    assert(f.count("SIP_ACCEPT_REQ") == 1 and #f.plays == 0)
    f.emit("SIP_CONNECTED", "inbound", 8)
    f.advance(500)
    assert(#f.plays == 1 and f.plays[1].target == "both" and f.muted)
    f.finish("done")
    assert(not f.muted and f.count("SIP_DIAL_REQ") == 0)
end

real_sys.taskInit(function()
    local count = 0
    for name, test in pairs(tests) do
        local ok, err = pcall(test)
        if not ok then real_log.error("notice_test", name, err); os.exit(1) end
        real_log.info("notice_test", "PASS", name)
        count = count + 1
    end
    real_log.info("notice_test", "OVERALL_PASS", count)
    os.exit(0)
end)
real_sys.run()
