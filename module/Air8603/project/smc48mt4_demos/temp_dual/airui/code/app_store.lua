--[[
@module  app_store
@summary 掉电保存（阈值、偏移），基于 fskv
@version 1.0.0
@date    2026.11.16

fskv 未初始化时所有读写静默失败，只走内存，界面上照常可用但重启会丢。
]]
local M = {}

local conf = require "conf"

local function key(k)
    return conf.store_ns .. "_" .. k
end

function M.available()
    return fskv ~= nil and type(fskv.get) == "function" and type(fskv.set) == "function"
end

function M.set(k, v)
    if not M.available() then return false end
    return pcall(fskv.set, key(k), v)
end

function M.get(k, def)
    if not M.available() then return def end
    local ok, v = pcall(fskv.get, key(k))
    if ok and v ~= nil then return v end
    return def
end

--[[
把存下来的阈值套回 conf.chs
]]
function M.load_channels()
    for i = 1, #conf.chs do
        local c = conf.chs[i]
        c.warn  = tonumber(M.get("warn" .. i, c.warn)) or c.warn
        c.alarm = tonumber(M.get("alarm" .. i, c.alarm)) or c.alarm
        c.offset = tonumber(M.get("ofs" .. i, c.offset or 0)) or (c.offset or 0)
    end
end

function M.save_channels()
    for i = 1, #conf.chs do
        local c = conf.chs[i]
        M.set("warn" .. i, c.warn)
        M.set("alarm" .. i, c.alarm)
        M.set("ofs" .. i, c.offset or 0)
    end
end

return M
