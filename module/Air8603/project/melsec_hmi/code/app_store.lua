--[[
@module  app_store
@summary 参数与报警记录持久化（fskv，掉电保存；fskv 不可用时自动降级为内存）
@version 1.0.0
@date    2026.11.09
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
@param v any 支持 fskv 的类型：number/string/boolean/table
@return boolean 是否写入成功
]]
function M.set(k, v)
    if not kv_ready() then
        return false
    end
    return pcall(fskv.set, key(k), v)
end

--[[
读取一个键值
@param k string 键名
@param default any 读取失败或不存在时的默认值
@return any
]]
function M.get(k, default)
    if not kv_ready() then
        return default
    end
    local ok, v = pcall(fskv.get, key(k))
    if ok and v ~= nil then
        return v
    end
    return default
end

--[[
保存所有通道的预警值/报警值
@param chs table conf.chs
@return nil
]]
function M.save_channels(chs)
    for i, ch in ipairs(chs) do
        M.set("ch" .. i .. "_warn", ch.warn)
        M.set("ch" .. i .. "_alarm", ch.alarm)
    end
    -- 记下当前量程：阈值是工程量数值，脱离量程没有意义
    M.set("scale_ver", conf.scale.val_max)
end

--[[
从 fskv 载入通道阈值，覆盖 conf.chs 中的默认值
@param chs table conf.chs
@return nil
]]
function M.load_channels(chs)
    -- 量程换过（例如 0~10V → 0~100℃）时，存储里是旧量程的阈值，
    -- 直接套用会让 7.0/9.0 变成 7℃/9℃，一上电就误报警，故整组丢弃用默认值
    local ver = tonumber(M.get("scale_ver", nil))
    if ver ~= conf.scale.val_max then
        if ver ~= nil then
            log.info("app_store", "量程已变更，丢弃旧阈值",
                "存储量程=" .. tostring(ver), "当前量程=" .. tostring(conf.scale.val_max))
        end
        return
    end
    for i, ch in ipairs(chs) do
        ch.warn = tonumber(M.get("ch" .. i .. "_warn", ch.warn)) or ch.warn
        ch.alarm = tonumber(M.get("ch" .. i .. "_alarm", ch.alarm)) or ch.alarm
    end
end

--[[
保存报警记录（json 字符串，最多 8 条，体积很小）
@param recs table 报警记录数组
@return nil
]]
function M.save_alarms(recs)
    if not json then
        return
    end
    local ok, s = pcall(json.encode, recs)
    if ok and s then
        M.set("alarms", s)
    end
end

--[[
载入报警记录
@return table 记录数组，失败返回空表
]]
function M.load_alarms()
    if not json then
        return {}
    end
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
