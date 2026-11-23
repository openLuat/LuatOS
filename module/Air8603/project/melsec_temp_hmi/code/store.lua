--[[
@module  store
@summary 阈值与报警记录的掉电保持（fskv + json）
]]

local M = {}

local KEY_TH = "thr"
local KEY_AL = "alrm"

local ready = false

local function ensure()
    if ready then return true end
    if not fskv then return false end
    pcall(fskv.init)
    ready = true
    return true
end

-- thresholds: { {warn=,alarm=}, {warn=,alarm=} }
function M.save_thresholds(th)
    if not ensure() then return false end
    local ok, s = pcall(json.encode, th)
    if not ok then return false end
    return fskv.set(KEY_TH, s)
end

function M.load_thresholds()
    if not ensure() then return nil end
    local s = fskv.get(KEY_TH)
    if not s or s == "" then return nil end
    local ok, t = pcall(json.decode, s)
    if ok and type(t) == "table" and t[1] and t[2] then return t end
    return nil
end

function M.save_records(recs)
    if not ensure() then return false end
    local ok, s = pcall(json.encode, recs)
    if not ok then return false end
    return fskv.set(KEY_AL, s)
end

function M.load_records()
    if not ensure() then return nil end
    local s = fskv.get(KEY_AL)
    if not s or s == "" then return nil end
    local ok, t = pcall(json.decode, s)
    if ok and type(t) == "table" then return t end
    return nil
end

return M
