--[[
@module  sim
@summary ROAST LAB 烘焙引擎（豆温/炉温/ROR/阶段/爆裂/冷却/评分/曲线档案）
@version 1.0
@date    2026.10.30

模型：炉温 ET 由火力/风门/转速决定目标值并一阶逼近；入豆瞬间炉温被冷豆拉低，
豆温先下探再回升形成回温点；BT 与 ET 温差驱动升温，ROR 随温差自然衰减；
豆温到一爆温度触发一爆，再 +crack_gap 触发二爆；出豆进入冷却。
演示加速：每次采样推进 dt_s 秒（12×），约 50~65 秒走完一炉 10~13 分钟。
]]
local conf = require("conf")

local M = {}
local C, DT, AMB, N = conf.sim, conf.sim.dt_s, conf.sim.ambient, conf.sim.history_n

local S = {
    mode = "idle", t = 0, cool_t = 0,
    bt = AMB, et = AMB, prev_bt = AMB, ror = 0,
    heat = conf.roast.heat_default,
    air = conf.roast.air_default,
    drum = conf.roast.drum_default,
    bean = 1,
    hist_bt = {}, hist_et = {}, hist_ror = {},
    events = {},
    first_crack = nil, second_crack = nil, turning = nil,
    drop_bt = nil, drop_t = nil, score = nil, dev_ratio = nil,
    batch = 18, archives = {}, compare = nil, paused = false, tick = 0,
}

for _, a in ipairs(conf.archives) do
    S.archives[#S.archives + 1] = {
        name = a.name, date = a.date, bean = a.bean,
        drop = a.drop, dur = a.dur, score = a.score, hist = nil,
    }
end

local function clamp(v, a, b) if v < a then return a end if v > b then return b end return v end
local function push(arr, v) arr[#arr + 1] = v if #arr > N then table.remove(arr, 1) end end

function M.fmt_time(sec)
    if not sec then return "--:--" end
    sec = math.floor(sec)
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

function M.level(v)
    for _, l in ipairs(conf.levels) do if v <= l.max then return l end end
    return conf.levels[#conf.levels]
end

-- 烘焙度在色阶里的位置 0..1
function M.level_pos(v)
    local list = conf.levels
    for i, l in ipairs(list) do
        if v <= l.max then
            local lo = (i == 1) and 180 or list[i - 1].max
            return clamp((i - 1 + (v - lo) / math.max(l.max - lo, 1)) / (#list - 1), 0, 1)
        end
    end
    return 1
end

function M.bean() return conf.beans[S.bean] end
function M.state() return S end
function M.mode() return S.mode end
function M.paused() return S.paused end
function M.beans_count() return #conf.beans end

function M.mode_text()
    if S.mode == "roast" then return "烘焙中" end
    if S.mode == "cooling" then return "冷却中" end
    if S.mode == "done" then return "已完成" end
    return "待机"
end

function M.mode_color()
    if S.mode == "roast" then return 0xC8763C end
    if S.mode == "cooling" then return 0x6FA8DC end
    if S.mode == "done" then return 0x7BC96F end
    return 0x806555
end

-- ===== 阶段 =====
function M.phases()
    local b = conf.beans[S.bean]
    return {
        { name = "脱水", from = 25, to = 150, color = 0x6FA8DC },
        { name = "梅纳", from = 150, to = b.crack, color = 0xD9A05B },
        { name = "发展", from = b.crack, to = 262, color = 0xFF8A4C },
    }
end

function M.phase()
    local ps = M.phases()
    for i = 1, #ps do
        if S.bt < ps[i].to or i == #ps then return i, ps[i] end
    end
    return 1, ps[1]
end

-- ===== 事件 =====
local function add_event(text, level)
    S.events[1] = { t = M.fmt_time(S.t), text = text, level = level or "info" }
    while #S.events > 6 do table.remove(S.events) end
end
function M.events() return S.events end
function M.clear_events() S.events = {} end

-- ===== 操作 =====
function M.set_bean(idx)
    if not conf.beans[idx] then return end
    S.bean = idx
    local b = conf.beans[idx]
    S.heat, S.air, S.drum = b.heat, b.air, b.drum
    M.reset()
end

function M.start()
    if S.mode == "roast" then return false end
    local b = conf.beans[S.bean]
    S.mode, S.t, S.cool_t = "roast", 0, 0
    S.bt, S.prev_bt, S.et, S.ror = AMB + 0.4, AMB + 0.4, 182, 0
    S.hist_bt, S.hist_et, S.hist_ror = {}, {}, {}
    S.events = {}
    S.first_crack, S.second_crack, S.turning = nil, nil, nil
    S.drop_bt, S.drop_t, S.score, S.dev_ratio = nil, nil, nil, nil
    S.compare, S.mena = nil, nil
    push(S.hist_bt, S.bt) push(S.hist_et, S.et) push(S.hist_ror, 0)
    add_event(string.format("入豆 · %s 生豆 %.1f°C", b.name, S.bt), "ok")
    return true
end

function M.drop()
    if S.mode ~= "roast" then return false end
    S.mode, S.cool_t = "cooling", 0
    S.drop_bt, S.drop_t = S.bt, S.t
    if S.first_crack then
        S.dev_ratio = clamp((S.t - S.first_crack) / math.max(S.t, 1), 0, 1)
    end
    S.score = M.score()
    add_event(string.format("出豆 %.1f°C · %s · %d 分", S.bt, M.level(S.bt).name, S.score), "ok")
    return true
end

function M.reset()
    S.mode, S.t, S.cool_t = "idle", 0, 0
    S.bt, S.prev_bt, S.et, S.ror = AMB, AMB, AMB, 0
    S.hist_bt, S.hist_et, S.hist_ror = {}, {}, {}
    S.events = {}
    S.first_crack, S.second_crack, S.turning = nil, nil, nil
    S.drop_bt, S.drop_t, S.score, S.dev_ratio, S.compare = nil, nil, nil, nil, nil
    S.mena = nil
    add_event("已复位 · 等待入豆", "info")
end

function M.set(k, v)
    if k == "heat" then S.heat = clamp(v, 0, 100)
    elseif k == "air" then S.air = clamp(v, 0, 100)
    elseif k == "drum" then S.drum = clamp(v, 20, 100) end
end

function M.get(k) return S[k] end

function M.toggle_pause()
    S.paused = not S.paused
    return S.paused
end

-- ===== 评分 =====
function M.score()
    local b = conf.beans[S.bean]
    local mid = (b.drop_min + b.drop_max) / 2
    local v = S.drop_bt or S.bt
    local s = 100 - math.abs(v - mid) * 2.6
    local dev = v - b.crack
    if dev < 6 then s = s - (6 - dev) * 5 end
    if dev > 32 then s = s - (dev - 32) * 2.2 end
    return math.floor(clamp(s, 40, 99))
end

-- ===== 提示 =====
function M.hint()
    local h, b = conf.roast.hint, conf.beans[S.bean]
    if S.mode == "idle" then
        return { text = "点按「入豆」开始 · 本豆推荐火力 " .. b.heat .. "% / 风门 " .. b.air .. "%", level = "info" }
    end
    if S.mode == "cooling" then
        return { text = "冷却盘运行中 · 豆温回落至 40°C 即可装袋", level = "info" }
    end
    if S.mode == "done" then
        return { text = string.format("本炉完成 · 评分 %d · 可保存曲线档案", S.score or 0), level = "ok" }
    end
    if S.et > h.et_high then return { text = "炉温偏高 · 开大风门或降低火力", level = "danger" } end
    if S.ror > h.ror_high and S.t > 120 then return { text = "升温过快 · 降低火力稳定发展", level = "warn" } end
    if S.air < h.air_low then return { text = "排风不足 · 易产生烟熏味", level = "warn" } end
    if S.heat < h.heat_low and S.t > 180 then return { text = "火力过低 · 曲线可能停滞", level = "warn" } end
    if S.bt > b.drop_max + 6 then return { text = "发展过深 · 建议立即出豆", level = "danger" } end
    if S.first_crack and not S.second_crack then
        return { text = "一爆中 · 建议发展 1'00''~1'40'' 后出豆", level = "warn" }
    end
    return { text = "曲线正常 · 保持当前火力与风门", level = "ok" }
end

-- ===== 档案 =====
function M.archives() return S.archives end
function M.compare() return S.compare end

function M.set_compare(i)
    if S.compare == i then S.compare = nil else S.compare = i end
    return S.compare
end

function M.archive_hist(i)
    local a = S.archives[i]
    if not a then return nil end
    if a.hist then return a.hist.bt end
    local n = math.max(2, math.floor(a.dur / DT))
    local arr, e = {}, math.exp(-3.1)
    for k = 0, n do
        local t = k / n
        arr[k + 1] = 26 + (a.drop - 26) * (1 - math.exp(-3.1 * t)) / (1 - e)
    end
    a.hist = { bt = arr }
    return arr
end

function M.save_curve()
    if not S.drop_bt then return nil end
    local a = {
        name = string.format("%s #A%d", conf.beans[S.bean].name, S.batch),
        date = os.date("%m-%d"), bean = S.bean,
        drop = S.drop_bt, dur = S.drop_t, score = S.score or M.score(),
        hist = { bt = S.hist_bt, et = S.hist_et },
    }
    S.batch = S.batch + 1
    table.insert(S.archives, 1, a)
    while #S.archives > 5 do table.remove(S.archives) end
    add_event("曲线已存档 · " .. a.name, "ok")
    return a
end

-- ===== 采样推演 =====
function M.tick()
    if S.paused then return false end
    S.tick = S.tick + 1
    local b = conf.beans[S.bean]

    if S.mode == "idle" then
        S.et = S.et + (AMB - S.et) * 0.05
        S.bt, S.ror = AMB, 0
        return false
    elseif S.mode == "done" then
        S.et = S.et + (AMB - S.et) * 0.06
        S.bt = S.bt + (AMB - S.bt) * 0.06
        S.ror = 0
        return false
    elseif S.mode == "cooling" then
        S.cool_t = S.cool_t + DT
        S.prev_bt = S.bt
        S.bt = S.bt + (C.cool_target - S.bt) * 0.058
        S.et = S.et + (AMB + 14 - S.et) * 0.085
        S.ror = (S.bt - S.prev_bt) / DT * 60
        push(S.hist_bt, S.bt) push(S.hist_et, S.et) push(S.hist_ror, S.ror)
        if S.bt <= C.cool_target + 3 then
            S.bt = C.cool_target
            S.mode = "done"
            add_event("冷却完成 · 可以装袋", "ok")
        end
        return true
    end

    -- 烘焙中：炉温
    S.t = S.t + DT
    local shock = 74 * math.exp(-S.t / 150)
    local et_target = clamp(38 + S.heat * 2.36 - S.air * 0.30 + S.drum * 0.03 - shock, 30, 272)
    S.et = S.et + (et_target - S.et) * 0.10

    -- 豆温：温差驱动升温 + 入豆吸热下探 + 低转速抖动
    local k = 0.030 * (0.80 + S.air / 180) * (0.66 + S.heat / 200) * (0.90 + S.drum / 420)
    local rise = (S.et - S.bt) * k
    if S.t <= 30 then rise = rise - 5.2 end
    if S.drum < 35 then rise = rise + (math.random() - 0.5) * 1.1 end
    S.prev_bt = S.bt
    S.bt = math.max(S.bt + rise, 18)
    S.ror = (S.bt - S.prev_bt) / DT * 60

    push(S.hist_bt, S.bt) push(S.hist_et, S.et) push(S.hist_ror, S.ror)

    if not S.turning and S.t > 30 and S.ror > 0.4 then
        S.turning = { t = S.t, bt = S.bt }
        add_event(string.format("回温点 %.1f°C", S.bt), "info")
    end
    if S.bt >= 150 and not S.mena then
        S.mena = true
        add_event("进入梅纳反应 · 注意甜感发展", "info")
    end
    if not S.first_crack and S.bt >= b.crack then
        S.first_crack = S.t
        add_event(string.format("一爆开始 · %.1f°C", S.bt), "warn")
    end
    if S.first_crack and not S.second_crack and S.bt >= b.crack + conf.roast.crack_gap then
        S.second_crack = S.t
        add_event("二爆 · 立即出豆或降火", "danger")
    end
    return true
end

return M
