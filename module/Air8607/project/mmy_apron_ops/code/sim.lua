--[[
@module  sim
@summary AeroDeck 数据与业务模型：航班保障流程、机位、跑道气象、资源与告警
@version 1.0
@date    2026.11.05
   说明：本项目无外接数据源，航班与气象由本地模型 + 时间推进生成，
        但各项之间存在真实因果：温度低 / 跑道结冰 → 除冰需求上升；
        能见度低 → 启动低能见运行（LVP）并压低放行率；
        保障节点推进 → 机位占用与准点率变化；资源不足 → 排队告警。
        接真实数据时，只需把 tick() 里的演化替换为解析报文后写值即可。
]]
local conf = require "conf"

local M = {}

local N = conf.sim.history or 48

local flights = {}
local alarms = {}
local fired = {}
local wx = {}
local hist = { vis = {}, wind = {}, temp = {} }
local resources = {}
local prev_lvp = false

M.paused = false
M.tick_count = 0
M.sim_min = conf.sim.start_min or 0

-- ===================== 工具 =====================
local function clamp(v, a, b)
    if v < a then return a elseif v > b then return b end
    return v
end

local function rnd(a)
    return (math.random() * 2 - 1) * a
end

local function pad2(n)
    return string.format("%02d", n)
end

local function hhmm(min)
    min = math.floor(min) % 1440
    return pad2(math.floor(min / 60)) .. ":" .. pad2(min % 60)
end

function M.clock()
    return hhmm(M.sim_min)
end

function M.date_text()
    local t = os.date("*t")
    local wd = { "日", "一", "二", "三", "四", "五", "六" }
    return string.format("%d月%d日 周%s", t.month, t.day, wd[t.wday])
end

-- "20:35" -> 分钟
local function parse_hm(s)
    local h, m = string.match(s or "", "(%d+):(%d+)")
    if not h then return 0 end
    return tonumber(h) * 60 + tonumber(m)
end

function M.minutes_of(hm) return parse_hm(hm) end

-- 航班计划时间与当前仿真时间的差值（分钟，正数=还没到点）
function M.until_std(f)
    return parse_hm(f.std) - M.sim_min
end

-- ===================== 初始化 =====================
function M.init()
    flights, alarms, fired, resources = {}, {}, {}, {}
    hist = { vis = {}, wind = {}, temp = {} }
    M.tick_count = 0
    M.sim_min = conf.sim.start_min or 0
    M.paused = false
    prev_lvp = false

    local stand_map = {}
    for _, s in ipairs(conf.stands) do stand_map[s.id] = s end

    for i, d in ipairs(conf.flights) do
        local st = stand_map[d.gate] or conf.stands[1]
        flights[i] = {
            idx = i,
            cs = d.cs, airline = d.airline, type = d.type, gate = d.gate,
            std = d.std, pax = d.pax, bags = d.bags,
            fuel = d.fuel, node = d.node, delay = d.delay, deice = d.deice,
            sang = st.ang, srad = st.rad, wide = st.wide,
            exit = 0, gone = false, wait = math.random(0, 3),
            auto = 3 + (i % 3),          -- 每推进一个保障节点需要的 tick 数
            fuel_loaded = 0,
        }
    end

    wx = {
        vis = 2600, rvr = 1250,
        wind_dir = 22, wind_spd = 6.4, gust = 8.2,
        temp = 3.6, dew = -1.2,
        state = "dry",
        qnh = 1018,
    }

    for _, r in ipairs(conf.resources) do
        resources[#resources + 1] = { key = r.key, name = r.name, icon = r.icon,
            total = r.total, used = r.used }
    end

    for i = 1, N do
        hist.vis[i] = wx.vis + rnd(120)
        hist.wind[i] = wx.wind_spd + rnd(0.6)
        hist.temp[i] = wx.temp + rnd(0.3)
    end

    M.log_event("机坪指挥系统启动，雷达链路正常", "ok")
    M.log_event(string.format("当前风向 %03d° / %.1f m/s，能见度 %d m",
        wx.wind_dir, wx.wind_spd, wx.vis), "ok")
end

-- ===================== 航班 =====================
function M.flights() return flights end
function M.count() return #flights end

function M.flight(idx)
    return flights[idx]
end

function M.find(cs)
    for i, f in ipairs(flights) do
        if f.cs == cs then return i end
    end
    return nil
end

function M.nodes() return conf.nodes end
function M.node_count() return #conf.nodes end

-- 下一步动作名
function M.step_name(f)
    local n = conf.nodes[(f.node or 0) + 1]
    return n and n.name or "已推出"
end

function M.status_text(f)
    if f.gone then return "已起飞" end
    if (f.node or 0) >= #conf.nodes then return "已推出" end
    return M.step_name(f) .. "中"
end

-- 航班风险等级：延误 > 15 或 缺除冰 → danger / 延误 > 5 → warn
function M.level(f)
    if f.deice and f.node >= 4 then return "danger" end
    if f.delay > 15 then return "danger" end
    if f.delay > 5 or M.until_std(f) < 0 then return "warn" end
    return "ok"
end

function M.level_text(f)
    local lv = M.level(f)
    if lv == "danger" then return f.deice and "待除冰" or "延误" end
    if lv == "warn" then return "关注" end
    return "正常"
end

function M.progress(f)
    return clamp((f.node or 0) / #conf.nodes, 0, 1)
end

-- 推进一个保障节点，返回 (新节点, 事件文本)
function M.advance(idx)
    local f = flights[idx]
    if not f or f.node >= #conf.nodes then return f and f.node end
    f.node = f.node + 1
    f.wait = 0
    local n = conf.nodes[f.node]
    local txt = f.cs .. " " .. n.name .. "完成"
    -- 加油节点把油量补满，装行李节点把行李配平
    if n.key == "fuel" then
        f.fuel_loaded = 1
        f.fuel = math.min(100, f.fuel + 18)
    elseif n.key == "bag" then
        f.bags = f.bags + math.random(0, 6)
    elseif n.key == "push" then
        f.delay = math.max(0, f.delay - 4)
    end
    M.log_event(txt, "ok")
    return f.node, txt
end

function M.deice_on(idx)
    local f = flights[idx]
    if not f then return false, "航班不存在" end
    if not f.deice then return false, f.cs .. " 当前无需除冰" end
    local car = M.res("deice")
    if car.used >= car.total then
        M.log_event("除冰车已满负荷，A08 继续排队", "warn")
        return false, "除冰车不足，请先在设置页增加车辆"
    end
    f.deice = false
    car.used = math.min(car.total, car.used + 1)
    M.log_event(f.cs .. " 除冰完成，等待放行", "ok")
    return true, f.cs .. " 除冰完成（用时 8 分钟）"
end

function M.set_gate(idx, gate)
    local f = flights[idx]
    if not f then return false, "航班不存在" end
    for _, o in ipairs(flights) do
        if o.idx ~= idx and o.gate == gate and not o.gone then
            return false, gate .. " 已被 " .. o.cs .. " 占用"
        end
    end
    for _, s in ipairs(conf.stands) do
        if s.id == gate then
            if f.wide and not s.wide then
                return false, gate .. " 为窄体机位，无法停靠宽体机"
            end
            f.gate, f.sang, f.srad = gate, s.ang, s.rad
            M.log_event(f.cs .. " 调整至机位 " .. gate, "ok")
            return true, f.cs .. " 已调整至 " .. gate
        end
    end
    return false, "机位不存在"
end

-- 雷达坐标：已推出的航班沿滑行道向外移动
function M.pos(f)
    local e = f.exit or 0
    local ang = f.sang + (18 - f.sang) * e
    local rr = f.srad + (1.04 - f.srad) * e
    return ang % 360, rr
end

-- ===================== 机位 =====================
function M.stands() return conf.stands end

function M.stand_flight(gate)
    for _, f in ipairs(flights) do
        if f.gate == gate and not f.gone then return f end
    end
    return nil
end

function M.occupied()
    local n = 0
    for _, s in ipairs(conf.stands) do
        if M.stand_flight(s.id) then n = n + 1 end
    end
    return n
end

function M.stand_total() return #conf.stands end

-- ===================== 气象 =====================
function M.wx() return wx end

function M.runway_state()
    for _, s in ipairs(conf.wx.states) do
        if s.key == wx.state then return s end
    end
    return conf.wx.states[1]
end

function M.state_name()
    return M.runway_state().name
end

function M.mu()
    return M.runway_state().mu
end

-- 侧风分量：跑道 18（磁向 180），风来向与跑道夹角
function M.crosswind()
    local a = math.rad(wx.wind_dir - 180)
    return math.abs(math.sin(a)) * wx.wind_spd
end

function M.headwind()
    local a = math.rad(wx.wind_dir - 180)
    return math.cos(a) * wx.wind_spd
end

function M.wind_sector()
    local d = wx.wind_dir % 360
    for _, s in ipairs(conf.wx.sectors) do
        if s.from < s.to then
            if d >= s.from and d < s.to then return s.name end
        else
            if d >= s.from or d < s.to then return s.name end
        end
    end
    return "北风"
end

function M.lvp()
    return wx.vis < conf.wx.vis.lo or wx.rvr < conf.wx.rvr.lo
end

function M.lvp_text()
    return M.lvp() and "低能见运行 LVP" or "常规运行"
end

-- 气象综合等级
function M.wx_level()
    local lv = "ok"
    if wx.vis < conf.wx.vis.lo then return "danger" end
    if wx.vis < conf.wx.vis.hi then lv = "warn" end
    if wx.wind_spd > conf.wx.wind.lo then return "danger" end
    if wx.wind_spd > conf.wx.wind.hi then lv = "warn" end
    if wx.temp < conf.wx.temp.lo then return "warn" end
    if wx.rvr < conf.wx.rvr.lo then return "danger" end
    if wx.rvr < conf.wx.rvr.hi and lv == "ok" then lv = "warn" end
    return lv
end

function M.set_wind(v)
    wx.wind_spd = clamp(v, conf.wx.wind.min, conf.wx.wind.max)
    wx.gust = wx.wind_spd * 1.28
end

function M.set_wind_dir(d)
    wx.wind_dir = math.floor(clamp(d, 0, 359))
end

function M.set_vis(v)
    wx.vis = math.floor(clamp(v, conf.wx.vis.min, conf.wx.vis.max))
    wx.rvr = math.floor(wx.vis * 0.62)
end

function M.set_temp(v)
    wx.temp = clamp(v, conf.wx.temp.min, conf.wx.temp.max)
    wx.dew = wx.temp - 4.8
end

function M.set_state(key)
    for _, s in ipairs(conf.wx.states) do
        if s.key == key then
            wx.state = key
            M.log_event("跑道状态切换为「" .. s.name .. "」，摩擦系数 " ..
                string.format("%.2f", s.mu), key == "dry" and "ok" or "warn")
            -- 结冰 / 雪浆会把在场所需除冰的航班标出来
            local need = s.deice
            for _, f in ipairs(flights) do
                if not f.gone then
                    if need > 0 and wx.temp < conf.wx.temp.hi then
                        if not f.deice and math.random() < need * 0.16 then f.deice = true end
                    end
                end
            end
            return true, s.name
        end
    end
    return false, "未知跑道状态"
end

function M.hist(key)
    return hist[key] or {}
end

-- ===================== 资源 =====================
function M.resources() return resources end

function M.res(key)
    for _, r in ipairs(resources) do
        if r.key == key then return r end
    end
end

function M.res_add(key, d)
    local r = M.res(key)
    if not r then return end
    r.total = clamp(r.total + d, 1, 12)
    if r.used > r.total then r.used = r.total end
    M.log_event(r.name .. " 调整至 " .. r.total .. " 台", "ok")
end

function M.res_sum()
    local total, used = 0, 0
    for _, r in ipairs(resources) do
        total = total + r.total
        used = used + r.used
    end
    return used, total
end

-- ===================== KPI =====================
function M.on_stand()
    local n = 0
    for _, f in ipairs(flights) do
        if not f.gone then n = n + 1 end
    end
    return n
end

function M.on_time_rate()
    local ok, total = 0, 0
    for _, f in ipairs(flights) do
        if not f.gone then
            total = total + 1
            if f.delay <= 5 then ok = ok + 1 end
        end
    end
    if total == 0 then return 100 end
    return math.floor(ok * 100 / total + 0.5)
end

function M.avg_delay()
    local sum, n = 0, 0
    for _, f in ipairs(flights) do
        if not f.gone then
            sum = sum + f.delay
            n = n + 1
        end
    end
    if n == 0 then return 0 end
    return sum / n
end

function M.deice_count()
    local n = 0
    for _, f in ipairs(flights) do
        if f.deice and not f.gone then n = n + 1 end
    end
    return n
end

function M.pax_total()
    local n = 0
    for _, f in ipairs(flights) do
        if not f.gone then n = n + f.pax end
    end
    return n
end

-- 已完成的保障节点总数 / 应完成总数（机坪进度）
function M.node_ratio()
    local done, all = 0, 0
    for _, f in ipairs(flights) do
        if not f.gone then
            done = done + f.node
            all = all + #conf.nodes
        end
    end
    if all == 0 then return 0 end
    return done / all
end

-- ===================== 事件 =====================
function M.log_event(text, level)
    alarms[#alarms + 1] = {
        text = text,
        level = level or "ok",
        time = hhmm(M.sim_min),
    }
    while #alarms > 40 do table.remove(alarms, 1) end
end

-- 最新在前
function M.alarms(n)
    local list = {}
    local total = #alarms
    local cnt = n or total
    for i = 0, cnt - 1 do
        local idx = total - i
        if idx >= 1 then list[#list + 1] = alarms[idx] end
    end
    return list
end

function M.alarm_count() return #alarms end

function M.worst_level()
    local worst = "ok"
    for _, f in ipairs(flights) do
        if not f.gone then
            local lv = M.level(f)
            if lv == "danger" then return "danger" end
            if lv == "warn" then worst = "warn" end
        end
    end
    local wl = M.wx_level()
    if wl == "danger" then return "danger" end
    if wl == "warn" and worst == "ok" then worst = "warn" end
    return worst
end

function M.abnormal_count()
    local n = 0
    for _, f in ipairs(flights) do
        if not f.gone and M.level(f) ~= "ok" then n = n + 1 end
    end
    if M.wx_level() ~= "ok" then n = n + 1 end
    return n
end

function M.uptime_text()
    local min = M.tick_count * (conf.sim.min_per_tick or 2)
    if min < 60 then return min .. " 分钟" end
    return string.format("%.1f 小时", min / 60)
end

-- ===================== 演化 =====================
function M.tick()
    if M.paused then return end
    M.tick_count = M.tick_count + 1
    M.sim_min = M.sim_min + (conf.sim.min_per_tick or 2)

    -- 航班保障推进：wait 到 auto 就前进一步，推出后沿滑行道离场
    for _, f in ipairs(flights) do
        if not f.gone then
            if f.node < #conf.nodes then
                f.wait = f.wait + 1
                if f.wait >= f.auto then
                    f.wait = 0
                    f.node = f.node + 1
                    local n = conf.nodes[f.node]
                    if n.key == "fuel" then
                        f.fuel = math.min(100, f.fuel + 18)
                    elseif n.key == "bag" then
                        f.bags = f.bags + math.random(0, 5)
                    elseif n.key == "push" then
                        f.delay = math.max(0, f.delay - 3)
                        M.log_event(f.cs .. " 关舱推出，移交放行", "ok")
                    end
                end
            else
                f.exit = math.min(1.1, (f.exit or 0) + 0.055)
                if f.exit >= 1.1 and not f.gone then
                    f.gone = true
                    f.respawn = 0
                    M.log_event(f.cs .. " 已起飞离场", "ok")
                end
            end

            -- 时间压力：过了计划时间仍未推出就累计延误
            if not f.gone and f.node < #conf.nodes then
                if M.sim_min > parse_hm(f.std) then
                    f.delay = f.delay + 1
                    if f.delay == 6 or f.delay == 16 then
                        M.log_event(f.cs .. " 保障滞后，延误 " .. f.delay .. " 分钟",
                            f.delay > 15 and "danger" or "warn")
                    end
                end
            end

            -- 低温 + 结冰跑道会自动把航班标成待除冰
            if not f.deice and wx.temp < conf.wx.temp.lo and f.node >= 2 then
                if math.random() < 0.06 then
                    f.deice = true
                    M.log_event(f.cs .. " 机翼结霜，需除冰后方可放行", "warn")
                end
            end
        end
    end

    -- 离场航班返场执飞下一段：保证长时间演示时雷达与列表不会跑空
    for _, f in ipairs(flights) do
        if f.gone then
            f.respawn = (f.respawn or 0) + 1
            if f.respawn >= 12 then
                f.gone = false
                f.exit = 0
                f.node = 0
                f.delay = 0
                f.deice = false
                f.wait = 0
                f.respawn = 0
                f.std = hhmm(parse_hm(f.std) + 95)
                M.log_event(f.cs .. " 返场靠桥，开始下一段保障", "ok")
            end
        end
    end

    -- 气象演化：能见度与风做有界随机游走
    -- 注意：vis / rvr / wind_dir 必须落成整数。rnd() 是浮点，若直接写回模型，
    -- 界面上的 string.format("%d m", w.vis) 会抛 "number has no integer representation"
    -- （Lua 5.3 里 %d 不接受非整值浮点），一抛整条 refresh 就断在那一刻，后面全部不刷新。
    wx.vis = math.floor(clamp(wx.vis + rnd(90) + (wx.vis < 1600 and 55 or -25),
        conf.wx.vis.min, conf.wx.vis.max))
    wx.rvr = math.floor(clamp(wx.vis * 0.62 + rnd(60), conf.wx.rvr.min, conf.wx.rvr.max))
    wx.wind_spd = clamp(wx.wind_spd + rnd(0.55), conf.wx.wind.min, conf.wx.wind.max)
    wx.gust = wx.wind_spd * 1.28 + math.abs(rnd(0.4))
    wx.wind_dir = math.floor((wx.wind_dir + rnd(3) + 360) % 360)
    wx.temp = clamp(wx.temp - 0.035 + rnd(0.06), conf.wx.temp.min, conf.wx.temp.max)
    wx.dew = wx.temp - 4.8 + rnd(0.3)

    -- LVP 切换只在越界瞬间记一条，避免刷屏
    local lvp = M.lvp()
    if lvp ~= prev_lvp then
        prev_lvp = lvp
        M.log_event(lvp and "能见度低于标准，启动低能见运行" or "能见度恢复，解除低能见运行",
            lvp and "danger" or "ok")
    end

    -- 演示事件
    for i, e in ipairs(conf.events) do
        if not fired[i] and M.tick_count >= e.after then
            fired[i] = true
            if e.text then
                if string.find(e.text, "能见度跌破") then M.set_vis(620) end
                if string.find(e.text, "能见度回升") then M.set_vis(2800) end
                if string.find(e.text, "北风加大") then
                    M.set_wind(13.5)
                    M.set_wind_dir(18)
                end
                M.log_event(e.text, e.level)
            end
        end
    end

    -- 历史
    local function push(k, v)
        local h = hist[k]
        h[#h + 1] = v
        if #h > N then table.remove(h, 1) end
    end
    push("vis", wx.vis)
    push("wind", wx.wind_spd)
    push("temp", wx.temp)
end

return M
