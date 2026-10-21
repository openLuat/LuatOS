PROJECT = "FactoryTwin_Air8601"
VERSION = "001.000.000"

_G.sys = require("sys")
local config = require("config")
local board = require("board")
local Model = require("model")
local Reporter = require("reporter")
local UI = require("ui")
local Clock = require("clock_ms")

sys.taskInit(function()
    local ok, reason = board.init(config)
    if not ok then
        log.error(PROJECT, "Display/touch/font initialization failed", reason)
        return
    end
    local model = Model.new(config)
    local reporter = Reporter.new(config)
    local view = UI.new(model, reporter, config)
    reporter:start()
    -- Bring-up hook for a future real device adapter. The default project never
    -- drives industrial power outputs. Publish inputs only from trusted code.
    sys.subscribe("FACTORY_DEVICE_HEALTH", function(line,index,status)
        local accepted,why=model:set_health(line,index,status)
        if not accepted then log.warn("FACTORY_INPUT",why) end
    end)
    local last_tick = Clock.now()
    log.info("factory.clock", "provider", type(mcu), "start_ms", last_tick)
    while true do
        for _,event in ipairs(model:drain_events()) do
            view.history:consume(event)
            reporter:accept(event)
        end
        view:render(model:snapshot(true))
        sys.wait(config.tick_ms)
        local now = Clock.now()
        local dt = Clock.elapsed(now,last_tick)
        last_tick = now
        model:step(dt)
        view:step(dt)
    end
end)

-- LuatOS requires sys.run() as the last statement of the entry script.
sys.run()
