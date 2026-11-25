local cfg = require "air8607c1_config"
local M = {}
local KEY = "air8607c1_baseboard_model"
local active

local function find(name)
    for _, model in ipairs(cfg.expansion_models) do
        if model.name == name then return model end
    end
end

function M.current()
    if not active then
        local ok, saved = pcall(function()
            if fskv and fskv.init() then return fskv.get(KEY) end
        end)
        active = (ok and find(saved)) or assert(find(cfg.default_expansion_model))
        log.info("factory", "BASEBOARD", active.name)
    end
    return active
end

function M.supports(id)
    local model = M.current()
    if id == "wifi" or id == "wifi_dl" then return model.wifi end
    if id == "ttl" or id == "rs232" then return model.uart2 == id end
    if id == "buzzer" then return model.audio == id end
    -- DAC 喇叭：audio 为 dac 的底板自带；其余底板用 dac = true 声明 J102 喇叭通路
    if id == "dac" then return model.dac == true or model.audio == "dac" end
    return true
end

function M.save(name)
    if not find(name) then return false, "底板型号无效" end
    local ok, saved = pcall(function()
        return fskv and fskv.init() and fskv.set(KEY, name)
    end)
    if not ok or not saved then return false, "保存底板型号失败，请重试" end
    log.info("factory", "BASEBOARD_SAVED", name)
    return true
end

return M
