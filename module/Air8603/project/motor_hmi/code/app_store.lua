--[[
@module  app_store
@summary 参数与报警记录持久化（fskv，掉电保存；fskv 不可用时降级为内存）
@version 1.0.0
@date    2026.11.12
]]
local M = {}

local conf = require "conf"

local function key(k)
    return conf.store_ns .. "_" .. k
end

local function kv_ready()
    return fskv ~= nil and type(fskv.get) == "function" and type(fskv.set) == "function"
end

--[[
写入一个键值
@param k string 键名（不含命名空间前缀）
@param v any number/string/boolean/table
@return boolean 是否成功
]]
function M.set(k, v)
    if not kv_ready() then return false end
    return pcall(fskv.set, key(k), v)
end

--[[
读取一个键值
@param k string 键名
@param default any 默认值
@return any
]]
function M.get(k, default)
    if not kv_ready() then return default end
    local ok, v = pcall(fskv.get, key(k))
    if ok and v ~= nil then
        return v
    end
    return default
end

--[[
保存顺序启动间隔
@param gap number 秒
@return nil
]]
function M.save_gap(gap)
    M.set("seq_gap", tonumber(gap) or conf.seq.gap_s)
end

--[[
载入顺序启动间隔，覆盖 conf.seq.gap_s
@return number 实际生效的间隔
]]
function M.load_gap()
    local v = tonumber(M.get("seq_gap", nil))
    if v and v >= conf.seq.gap_min and v <= conf.seq.gap_max then
        conf.seq.gap_s = v
    end
    return conf.seq.gap_s
end

--[[
保存报警记录
@param recs table
@return nil
]]
function M.save_alarms(recs)
    if not json then return end
    local ok, s = pcall(json.encode, recs)
    if ok and s then
        M.set("alarms", s)
    end
end

--[[
载入报警记录
@return table
]]
function M.load_alarms()
    if not json then return {} end
    local s = M.get("alarms", nil)
    if type(s) == "string" and #s > 2 then
        local ok, t = pcall(json.decode, s)
        if ok and type(t) == "table" then
            return t
        end
    end
    return {}
end

return M
