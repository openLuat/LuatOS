--[[
@module  store
@summary 工业 HMI 数据持久化：工艺参数 / 报警阈值 / 模具模次 / 报警记录 / 班次产量
@version 1.0
@date    2026.11.10

落盘策略：内存即时生效，dirty 后由 flush() 统一写 fskv，
避免 1Hz 刷新时高频擦写 KV 分区。
]]
local conf = require("conf")

local M = {}

local P = conf.kv .. "_"
local ok_kv = false
local mem = {}
local cache = {}

local function kv_get(key)
    if ok_kv then
        local ok, v = pcall(fskv.get, P .. key)
        if ok and v ~= nil then return v end
    end
    return mem[key]
end

local function kv_set(key, v)
    mem[key] = v
    if ok_kv then pcall(fskv.set, P .. key, v) end
end

function M.kv_ok() return ok_kv end

function M.init()
    local ok = pcall(fskv.init)
    if ok then
        ok_kv = true
    else
        log.warn("store", "fskv 不可用，数据仅保存在内存")
    end
    return ok_kv
end

local function deep_copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = deep_copy(v) end
    return o
end

-- ==================== 报警阈值 / 运行设置 ====================
local DEFAULT_SET = {
    mold_hi = 95, oil_hi = 58, cyc_dev = 15, lowp_time = 1.8,
    shift = 1, rotate = 1, backlight = 85, buzzer = 1,
}

function M.settings()
    if cache.set then return cache.set end
    local s = kv_get("set")
    local t = deep_copy(DEFAULT_SET)
    if type(s) == "table" then
        for k, v in pairs(s) do
            if t[k] ~= nil then t[k] = v end
        end
    end
    cache.set = t
    return t
end

function M.set_setting(key, v)
    local s = M.settings()
    s[key] = v
end

function M.save_settings()
    kv_set("set", deep_copy(M.settings()))
end

-- ==================== 工艺参数 ====================
local function default_params()
    local t = {}
    for _, p in ipairs(conf.params) do t[p.key] = p.def end
    return t
end

function M.params()
    if cache.prm then return cache.prm end
    local s = kv_get("prm")
    local t = default_params()
    if type(s) == "table" then
        for k, v in pairs(s) do
            if t[k] ~= nil and type(v) == "number" then t[k] = v end
        end
    end
    cache.prm = t
    return t
end

function M.set_param(key, v)
    M.params()[key] = v
end

function M.save_params()
    kv_set("prm", deep_copy(M.params()))
end

-- ==================== 模具已用模次（万模次）====================
function M.mold_used(id)
    local t = kv_get("mold")
    if type(t) == "table" and type(t[id]) == "number" then return t[id] end
    for _, m in ipairs(conf.molds) do
        if m.id == id then return m.used end
    end
    return 0
end

function M.add_mold_cycles(id, wan)
    local t = kv_get("mold")
    if type(t) ~= "table" then t = {} end
    t[id] = (t[id] or M.mold_used(id)) + wan
    kv_set("mold", t)
end

-- ==================== 报警记录 ====================
local ALARM_MAX = 40

function M.alarms()
    if cache.alm then return cache.alm end
    local t = kv_get("alm")
    if type(t) ~= "table" then t = {} end
    cache.alm = t
    return t
end

function M.add_alarm(rec)
    local t = M.alarms()
    table.insert(t, 1, rec)
    while #t > ALARM_MAX do table.remove(t) end
    kv_set("alm", t)
end

function M.ack_alarm(index)
    local t = M.alarms()
    if t[index] then
        t[index].ack = true
        kv_set("alm", t)
    end
end

function M.ack_all()
    for _, r in ipairs(M.alarms()) do r.ack = true end
    kv_set("alm", M.alarms())
end

function M.unacked_count()
    local n = 0
    for _, r in ipairs(M.alarms()) do
        if not r.ack then n = n + 1 end
    end
    return n
end

function M.clear_alarms()
    cache.alm = {}
    kv_set("alm", {})
end

-- ==================== 今日产量（模数）====================
local function today_key() return os.date("%Y%m%d") end

-- 今日产量只在内存累加，flush() 时落盘（1Hz 调用不能直接写 flash）
function M.today()
    local t = mem.day
    if type(t) ~= "table" or t.date ~= today_key() then
        local s = kv_get("day")
        if type(s) == "table" and s.date == today_key() then
            t = s
        else
            t = { date = today_key(), ok = 0, ng = 0 }
        end
        mem.day = t
    end
    return t
end

function M.add_output(ok_n, ng_n)
    local t = M.today()
    t.ok = t.ok + (ok_n or 0)
    t.ng = t.ng + (ng_n or 0)
end

-- 由主循环每 60s 调一次，统一落盘
function M.flush()
    if not ok_kv then return end
    local t = mem.day
    if type(t) == "table" then kv_set("day", deep_copy(t)) end
end

return M
