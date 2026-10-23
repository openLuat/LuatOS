PROJECT = "TrainControl_Air8601"
VERSION = "001.000.000"

_G.sys = require("sys")
local config = require("config")
local board = require("board")
local Clock = require("clock_ms")
local data = require("train_data")
local Model = require("train_model")
local UI = require("ui")

log.info(PROJECT, "scripts", VERSION, "stations", #data.stations, "edges", #data.edges)

sys.taskInit(function()
    local ok, reason = board.init(config)
    if not ok then
        log.error(PROJECT, reason)
        return
    end

    local model = Model.new(data, config)
    local view = UI.new(model, data, config)
    local previous = Clock.now()

    local function frame()
        local now = Clock.now()
        local dt = Clock.elapsed(now, previous) / 1000
        previous = now
        if dt < 0 then dt = 0 elseif dt > 0.5 then dt = 0.5 end
        model:step(dt)
        view:render(model:snapshot())
    end

    view:render(model:snapshot())
    log.info(PROJECT, "ready", "trains", #data.routes)

    if not sys.timerLoopStart(frame, config.frame_ms) then
        while true do
            sys.wait(config.frame_ms)
            frame()
        end
    end
end)

sys.run()
