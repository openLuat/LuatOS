-- @module  alarm_app
-- @summary 电表数据越限报警（阈值可在 Web 端远程配置，掉电保存）
-- @version 001.000.000
-- @date    2026.10.27
-- @author  OpenLuat
-- @BSD License
--[[
纯软件报警：不依赖电表的 DO/AO（说明书地址表没有相关寄存器），
由网关侧订阅 METER_DATA，自行判断越限，再随 TLV 上报云端。

报警项（位图，tag1313）：
  bit0 (1)  电压越限：任一相 > hi_u 或 < lo_u
  bit1 (2)  电流越限：任一相 > hi_i
  bit2 (4)  功率越限：|P| > hi_p
  bit3 (8)  频率越限：f > hi_f 或 < lo_f

阈值里填 0 表示不判该项；hys 为回差，触发后需回到 门限∓hys 才解除，
避免数值在门限附近抖动导致报警反复翻转。

下行命令（tag19，JSON）：
  {"type":"alarm","enable":1,"hi_u":250,"lo_u":180,"hi_i":10,"hi_p":50,"hi_f":50.5,"lo_f":49.5,"hys":2}
      —— 只更新传入的字段，其余保持不变
  {"type":"alarm_get"}   —— 查询当前配置与状态
文本命令：alarm:on / alarm:off

上报（tag）：1313 报警位图 INTEGER，1314 报警描述 ASCII（如 "OV,OC"）
事件：sys.publish("ALARM_STATE", {bitmap=, text=})
]]

local M = {}

local DEFAULTS = {
    enable = 0,   -- 1=启用
    hi_u   = 0,   -- 电压上限 V（0=不判）
    lo_u   = 0,   -- 电压下限 V
    hi_i   = 0,   -- 电流上限 A
    hi_p   = 0,   -- 功率上限 kW
    hi_f   = 0,   -- 频率上限 Hz
    lo_f   = 0,   -- 频率下限 Hz
    hys    = 2,   -- 回差
}

local cfg = {}
local state = { bitmap = 0, text = "", ts = 0 }
local active = { u = false, i = false, p = false, f = false }

-- ==================== 持久化 ====================
local FSKV_KEY = "alarm_cfg"

local function save_cfg()
    if fskv and fskv.set then pcall(fskv.set, FSKV_KEY, json.encode(cfg)) end
end

local function load_cfg()
    if fskv and fskv.init then pcall(fskv.init) end
    for k, v in pairs(DEFAULTS) do cfg[k] = v end
    if fskv and fskv.get then
        local ok, s = pcall(fskv.get, FSKV_KEY)
        if ok and type(s) == "string" and s ~= "" then
            local ok2, t = pcall(json.decode, s)
            if ok2 and type(t) == "table" then
                for k, v in pairs(t) do
                    if DEFAULTS[k] ~= nil and type(v) == "number" then cfg[k] = v end
                end
            end
        end
    end
end

-- ==================== 判定 ====================
local function num(v) return tonumber(v) or 0 end

local function eval(d)
    local hys = cfg.hys or 0

    -- 电压：取三相最大值/最小值
    local umax = math.max(num(d.ua), num(d.ub), num(d.uc))
    local umin = math.min(num(d.ua), num(d.ub), num(d.uc))
    local u_hit  = (cfg.hi_u > 0 and umax > cfg.hi_u) or (cfg.lo_u > 0 and umin < cfg.lo_u)
    local u_miss = (cfg.hi_u <= 0 or umax <= cfg.hi_u - hys) and (cfg.lo_u <= 0 or umin >= cfg.lo_u + hys)

    -- 电流
    local imax = math.max(num(d.ia), num(d.ib), num(d.ic))
    local i_hit  = (cfg.hi_i > 0 and imax > cfg.hi_i)
    local i_miss = (cfg.hi_i <= 0 or imax <= cfg.hi_i - hys)

    -- 功率（有功取绝对值）
    local pabs = math.abs(num(d.p))
    local p_hit  = (cfg.hi_p > 0 and pabs > cfg.hi_p)
    local p_miss = (cfg.hi_p <= 0 or pabs <= cfg.hi_p - hys)

    -- 频率
    local f = num(d.f)
    local f_hit  = (cfg.hi_f > 0 and f > cfg.hi_f) or (cfg.lo_f > 0 and f < cfg.lo_f)
    local f_miss = (cfg.hi_f <= 0 or f <= cfg.hi_f - hys) and (cfg.lo_f <= 0 or f >= cfg.lo_f + hys)

    local items = { { "u", u_hit, u_miss, "OV" }, { "i", i_hit, i_miss, "OC" },
                    { "p", p_hit, p_miss, "OP" }, { "f", f_hit, f_miss, "OF" } }
    local bitmap, texts = 0, {}
    for idx, it in ipairs(items) do
        local name, hit, miss, tag = it[1], it[2], it[3], it[4]
        if active[name] then
            if miss then active[name] = false end
        elseif hit then
            active[name] = true
        end
        if active[name] then
            bitmap = bitmap + 2 ^ (idx - 1)
            texts[#texts + 1] = tag
        end
    end
    return bitmap, table.concat(texts, ",")
end

local function refresh(d)
    if not d then return end
    local bitmap, text
    if cfg.enable == 1 and d.online then
        bitmap, text = eval(d)
    else
        for k in pairs(active) do active[k] = false end
        bitmap, text = 0, ""
    end
    local changed = (bitmap ~= state.bitmap)
    state.bitmap, state.text, state.ts = bitmap, text, os.time()
    if changed then
        log.info("alarm", "报警状态", bitmap, text)
        sys.publish("ALARM_STATE", { bitmap = bitmap, text = text })
    end
end

-- ==================== 对外接口 ====================
function M.get()
    return { bitmap = state.bitmap, text = state.text, ts = state.ts, cfg = cfg }
end

function M.get_cfg() return cfg end

-- 增量更新配置，返回 JSON 应答字符串
-- 数值转 JSON 文本：本固件 sprintf 的 %g 对 0 会输出 0.000000e-308，统一改定点格式
local function jnum(v)
    v = tonumber(v) or 0
    if v % 1 == 0 then return string.format("%.0f", v) end
    return (string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", ""))
end

function M.set(t)
    if type(t) ~= "table" then return '{"code":1,"type":"alarm","value":"bad param"}' end
    local updated = {}
    for k in pairs(DEFAULTS) do
        if type(t[k]) == "number" then
            cfg[k] = t[k]
            updated[#updated + 1] = k
        end
    end
    if #updated == 0 then return '{"code":1,"type":"alarm","value":"no valid field"}' end
    cfg.enable = (cfg.enable == 1) and 1 or 0
    if cfg.hys < 0 then cfg.hys = 0 end
    save_cfg()
    log.info("alarm", "报警配置更新", json.encode(cfg))
    -- 配置变化后强制重新评估，避免沿用旧的回差状态
    for k in pairs(active) do active[k] = false end
    state.bitmap, state.text = 0, ""
    return string.format('{"code":0,"type":"alarm","enable":%d,"hi_u":%s,"lo_u":%s,"hi_i":%s,'
        .. '"hi_p":%s,"hi_f":%s,"lo_f":%s,"hys":%s,"state":%d}',
        cfg.enable, jnum(cfg.hi_u), jnum(cfg.lo_u), jnum(cfg.hi_i),
        jnum(cfg.hi_p), jnum(cfg.hi_f), jnum(cfg.lo_f), jnum(cfg.hys), state.bitmap)
end

function M.get_json()
    return string.format('{"code":0,"type":"alarm_get","enable":%d,"hi_u":%s,"lo_u":%s,"hi_i":%s,'
        .. '"hi_p":%s,"hi_f":%s,"lo_f":%s,"hys":%s,"state":%d,"text":"%s"}',
        cfg.enable, jnum(cfg.hi_u), jnum(cfg.lo_u), jnum(cfg.hi_i),
        jnum(cfg.hi_p), jnum(cfg.hi_f), jnum(cfg.lo_f), jnum(cfg.hys),
        state.bitmap, state.text or "")
end

function M.enable(on)
    cfg.enable = on and 1 or 0
    save_cfg()
    return string.format('{"code":0,"type":"alarm","enable":%d}', cfg.enable)
end

-- ==================== 启动 ====================
load_cfg()

sys.subscribe("METER_DATA", function(d) refresh(d) end)

log.info("alarm", "越限报警就绪", "启用", cfg.enable, "回差", cfg.hys)

return M
