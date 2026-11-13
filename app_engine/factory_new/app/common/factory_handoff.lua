-- All page transitions and peripheral commands run on one FIFO worker.
local M = {}
local queue, running = {}, false
local mode
local hooks = {}
local navigation_guards = {}
function M.set_navigation_guard(fn, name) navigation_guards[name or "camera"] = fn end
function M.defer_navigation(fn)
    for _, guard in pairs(navigation_guards) do
        if guard(fn) then return true end
    end
    return false
end
local sip, audio
-- LuatOS does not expose the standard Lua package.loaded cache.
-- The SIP page supplies its existing modules after lazy loading them.
function M.bind_sip(sip_app, audio_app)
    assert(type(sip_app) == "table" and type(sip_app.logout) == "function"
        and type(sip_app.wait_stopped) == "function")
    assert(type(audio_app) == "table" and type(audio_app.shutdown) == "function")
    sip, audio = sip_app, audio_app
end
function M.register(name, fn) hooks[name] = fn end
function M.mode() return mode end
function M.enqueue(fn)
    queue[#queue+1] = fn
    if running then return end
    running = true
    sys.taskInit(function()
        while #queue > 0 do
            local job = table.remove(queue, 1)
            local ok, err = pcall(job)
            if not ok then
                log.error("factory_handoff", tostring(err))
                sys.publish("FACTORY_HANDOFF_ERROR", tostring(err))
            end
        end
        running = false
    end)
end
function M.prepare(target)
    log.info("factory_handoff", "STOP_BEGIN", mode or "none", "->", target)
    for _, fn in pairs(hooks) do assert(fn() ~= false, "page cleanup failed") end
    if type(sip) == "table" then
        local ok, err = sip.logout(true); assert(ok ~= false, err)
        ok, err = sip.wait_stopped(15000); assert(ok, err)
    end
    if type(audio) == "table" then assert(audio.shutdown()) end
    local periph = require "other_func_app"
    local ok, err = periph.stop_all(); assert(ok, err)
    local hw = require "audio_hw"
    assert(hw.shutdown())
    mode = target
    log.info("factory_handoff", "STOP_DONE", target)
    return true
end
function M.leave(expected)
    if mode == expected then M.prepare("idle") end
end
return M
