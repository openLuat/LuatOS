PROJECT = "BusFare_Air8601"
VERSION = "001.000.000"

_G.sys = require("sys")
local config = require("config")
local board = require("board")
local Store = require("settings_store")
local Model = require("settings_model")
local UI = require("ui")

log.info(PROJECT, "scripts", VERSION)

sys.taskInit(function()
    local ok, reason = board.init(config)
    if not ok then
        log.error(PROJECT, reason)
        return
    end

    local model = Model.new(config, Store)
    local view = UI.new(model, config)
    view:render(model:snapshot())

    log.info(PROJECT, "ready",
        "vehicle", model.values.vehicle,
        "fare", model.values.fare,
        "warning", model.values.warning)
end)

sys.run()
