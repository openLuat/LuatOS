--[[
@module  page_func
@summary UAV GCS - 功能页（八个动作键 + 事件日志）
@version 1.0
@date    2026.11.02

左边 2x4 八个动作键，每个键 = 图标 + 标题 + 副标题 + 右侧状态字。
图标全部是图元画的（锁 / 上升箭头 / 同心圆 / 房子 / 下降箭头 / 循环箭头 / 告警三角 / 刷新），
没有任何图片资源 —— 这张图放大到 2 倍屏也不糊。

右边是事件日志：最新的在最上面，按级别染色（信息青 / 警告琥珀 / 错误红）。
日志和数据是同一份仿真状态产生的：点"一键起飞"，日志立刻多一行，
姿态页的高度同时开始爬 —— 这样点按钮才有"真的在飞"的感觉。
]]
local fx = require "fx"
local T = require "theme"
local parts = require "parts"
local sim = require "sim"

local C = T.c
local M = {}

local FB = T.func.btn
local LG = T.func.log
local TP_DOWN = T.TP_DOWN

local o = { root = nil }
local P = nil
local btn = {}
local logs = {}
local st = {}

local LOG_ROWS = 9
local LOG_H = 40

-- ==================== 图标 ====================
local function draw_icon(P0, kind, cx, cy, col)
    if kind == 1 then            -- 锁
        P0:frame(cx - 11, cy - 3, 23, 17, col, 2, 235, 4)
        P0:arc(cx, cy - 3, 9, 180, 360, col, 2, 235, false)
        P0:dot(cx, cy + 5, 2, col, 240)
    elseif kind == 2 then        -- 起飞
        P0:line(cx, cy + 13, cx, cy - 11, col, 3, 240, true)
        P0:line(cx, cy - 11, cx - 9, cy - 1, col, 3, 240, true)
        P0:line(cx, cy - 11, cx + 9, cy - 1, col, 3, 240, true)
        P0:line(cx - 16, cy + 17, cx + 16, cy + 17, col, 2, 190, true)
    elseif kind == 3 then        -- 悬停
        P0:ring(cx, cy, 15, col, 2, 230)
        P0:ring(cx, cy, 7, col, 2, 170)
        P0:dot(cx, cy, 3, col, 240)
    elseif kind == 4 then        -- 返航（房子）
        P0:line(cx - 15, cy + 2, cx, cy - 14, col, 2, 235, true)
        P0:line(cx, cy - 14, cx + 15, cy + 2, col, 2, 235, true)
        P0:line(cx - 10, cy + 2, cx - 10, cy + 15, col, 2, 235, true)
        P0:line(cx + 10, cy + 2, cx + 10, cy + 15, col, 2, 235, true)
        P0:line(cx - 10, cy + 15, cx + 10, cy + 15, col, 2, 235, true)
        P0:dot(cx, cy + 6, 3, col, 240)
    elseif kind == 5 then        -- 降落
        P0:line(cx, cy - 13, cx, cy + 11, col, 3, 240, true)
        P0:line(cx, cy + 11, cx - 9, cy + 1, col, 3, 240, true)
        P0:line(cx, cy + 11, cx + 9, cy + 1, col, 3, 240, true)
        P0:line(cx - 16, cy + 17, cx + 16, cy + 17, col, 2, 190, true)
    elseif kind == 6 then        -- 校准（循环箭头）
        P0:arc(cx, cy, 14, 40, 320, col, 2, 235, false)
        P0:line(cx + 10, cy - 10, cx + 17, cy - 3, col, 2, 235, true)
        P0:line(cx + 17, cy - 3, cx + 9, cy - 1, col, 2, 235, true)
    elseif kind == 7 then        -- 故障（告警三角）
        P0:line(cx, cy - 15, cx + 15, cy + 13, col, 2, 235, true)
        P0:line(cx, cy - 15, cx - 15, cy + 13, col, 2, 235, true)
        P0:line(cx - 15, cy + 13, cx + 15, cy + 13, col, 2, 235, true)
        P0:line(cx, cy - 6, cx, cy + 3, col, 2, 240, true)
        P0:dot(cx, cy + 8, 2, col, 240)
    else                         -- 清零（两条环）
        -- 起止角写成 300 -> 600 而不是 300 -> 240：后者是负跨度，
        -- 遇到没做取模的固件会画成一条线
        P0:arc(cx, cy, 13, 300, 600, col, 2, 235, false)
        P0:line(cx + 12, cy - 7, cx + 18, cy + 1, col, 2, 235, true)
        P0:line(cx - 18, cy + 1, cx - 12, cy - 7, col, 2, 235, true)
        P0:line(cx - 4, cy - 2, cx + 4, cy + 4, col, 2, 235, true)
    end
end

-- ==================== 构建 ====================
-- 标题一律 4 个汉字：22 号字下正好 88px，键宽 312 里给标题留 112，右侧还剩 88 给状态字
local ACTS = {
    { icon = 1, title = "解锁上锁", sub = "ARM / DISARM", col = C.green },
    { icon = 2, title = "一键起飞", sub = "TAKEOFF 12m", col = C.cyan },
    { icon = 3, title = "定点悬停", sub = "POSITION HOLD", col = C.blue },
    { icon = 4, title = "自动返航", sub = "RETURN HOME", col = C.amber },
    { icon = 5, title = "立即降落", sub = "LAND NOW", col = C.green },
    { icon = 6, title = "校准罗盘", sub = "COMPASS CAL", col = C.violet },
    { icon = 7, title = "故障注入", sub = "FAULT INJECT", col = C.red },
    { icon = 8, title = "清零统计", sub = "RESET STATS", col = C.dim },
}
M.ACTS = ACTS

function M.build(parent)
    o.root = parent
    P = fx.pool()

    -- ---------- 八个动作键 ----------
    for i = 1, 8 do
        local col = (i - 1) % 2
        local row = (i - 1) // 2
        local x = FB.x + col * (FB.w + FB.gap_x)
        local y = FB.y + row * (FB.h + FB.gap_y)
        local a = ACTS[i]
        local sh = airui.shape({
            parent = parent, x = x, y = y, w = FB.w, h = FB.h, items = {},
        })
        btn[i] = {
            x = x, y = y, w = FB.w, h = FB.h, shape = sh,
            title = parts.lbl(parent, x + 96, y + 26, 112, 28, a.title,
                T.f.mid, C.txt, airui.TEXT_ALIGN_LEFT),
            sub = parts.lbl(parent, x + 96, y + 58, 150, 18, a.sub,
                T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT),
            state = parts.lbl(parent, x + FB.w - 104, y + 28, 88, 24, "",
                T.f.sub, C.dim, airui.TEXT_ALIGN_RIGHT),
        }
    end

    -- ---------- 日志卡 ----------
    parts.card(parent, LG, "事件日志 EVENT LOG", "LOG", C.cyan)
    local log_bg = airui.shape({
        parent = parent, x = LG.x, y = LG.y, w = LG.w, h = LG.h, items = {},
    })
    P:reset()
    P:line(14, 38, LG.w - 15, 38, C.line2, 1, 220, false)
    P:line(14, LG.h - 54, LG.w - 15, LG.h - 54, C.line2, 1, 200, false)
    for i = 1, LOG_ROWS - 1 do
        P:line(14, 38 + i * LOG_H, LG.w - 15, 38 + i * LOG_H, C.line, 1, 70, false)
    end
    P:box(14, LG.h - 48, 3, 40, C.cyan, 180, 2)
    P:finish()
    log_bg:set_items(P.items)

    for i = 1, LOG_ROWS do
        local y = LG.y + 40 + (i - 1) * LOG_H
        logs[i] = {
            t = parts.lbl(parent, LG.x + 16, y + 2, 52, 16, "", T.f.mini, C.dim2,
                airui.TEXT_ALIGN_LEFT),
            txt = parts.lbl(parent, LG.x + 16, y + 18, LG.w - 32, 20, "", T.f.sub,
                C.dim, airui.TEXT_ALIGN_LEFT),
        }
    end

    -- ---------- 状态脚注 ----------
    st.uptime = parts.lbl(parent, LG.x + 24, LG.y + LG.h - 46, 150, 18, "",
        T.f.sub, C.cyan, airui.TEXT_ALIGN_LEFT)
    st.mission = parts.lbl(parent, LG.x + 180, LG.y + LG.h - 46, 156, 18, "",
        T.f.mini, C.dim, airui.TEXT_ALIGN_RIGHT)
    st.ver = parts.lbl(parent, LG.x + 24, LG.y + LG.h - 26, 300, 18,
        "FC 4.5.1  /  GCS 1.0.0", T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT)
end

-- ==================== 键位重绘 ====================
local function paint_button(i)
    local b = btn[i]
    local a = ACTS[i]
    local s = sim.s
    local on = false
    if i == 1 then
        on = s.armed
    elseif i == 7 then
        on = (s.fault ~= nil)
    elseif i == 3 then
        on = (s.mode == 3)
    end

    P:reset()
    if on then
        P:box(0, 0, b.w - 1, b.h - 1, a.col, 26, 12)
        P:frame(0, 0, b.w - 1, b.h - 1, a.col, 2, 220, 12)
    else
        P:box(0, 0, b.w - 1, b.h - 1, C.panel, 250, 12)
        P:frame(0, 0, b.w - 1, b.h - 1, C.line, 1, 235, 12)
    end
    -- 左侧图标区
    P:box(12, 12, 72, b.h - 24, 0x0A1220, 220, 8)
    P:line(84, 20, 84, b.h - 20, C.line, 1, 120, false)
    draw_icon(P, a.icon, 48, b.h / 2, on and a.col or fx.shade(a.col, -0.15))

    -- 右侧装饰：一条随状态亮起的细线
    P:line(b.w - 20, b.h / 2, b.w - 12, b.h / 2, on and a.col or C.line2, 2, on and 240 or 120, true)
    P:finish()
    b.shape:set_items(P.items)
end

-- ==================== 每帧（10Hz） ====================
function M.draw(dt, t)
    local s = sim.s
    for i = 1, 8 do
        paint_button(i)
    end

    parts.text(btn[1].state, s.armed and "已解锁" or "上锁")
    parts.text(btn[2].state, string.format("%.0f m", s.cmd.alt))
    parts.text(btn[3].state, sim.MODES[s.mode])
    parts.text(btn[4].state, string.format("%.0f m", s.dist))
    parts.text(btn[5].state, string.format("%.1f m", s.alt))
    parts.text(btn[6].state, (s.cal.dur > 0) and "校准中" or "")
    parts.text(btn[7].state, s.fault == "gps" and "GPS 失锁"
        or (s.fault == "link" and "链路丢包" or "正常"))
    parts.text(btn[8].state, string.format("%d%%", math.floor(s.batt + 0.5)))

    -- 日志（颜色也缓存，set_color 同样会触发重绘）
    for i = 1, LOG_ROWS do
        local it = s.logs[i]
        local row = logs[i]
        if it then
            parts.text(row.t, sim.fmt_time(it.t))
            parts.text(row.txt, parts.cut(it.txt, 17))
            local col = (it.lv == "err") and C.red
                or ((it.lv == "warn") and C.amber or C.dim)
            if row.col ~= col then
                row.col = col
                row.txt:set_color(col)
            end
        else
            parts.text(row.t, "")
            parts.text(row.txt, "")
        end
    end

    parts.text(st.uptime, "运行 " .. sim.fmt_time(s.t))
    parts.text(st.mission, "任务 " .. s.mission)
end

-- ==================== 触摸 ====================
function M.on_touch(state, x, y)
    if state ~= TP_DOWN then return end
    local s = sim.s
    for i = 1, 8 do
        local b = btn[i]
        if parts.hit(x, y, b.x, b.y, b.w, b.h) then
            if i == 1 then
                sim.arm(not s.armed)
            elseif i == 2 then
                sim.takeoff(12)
            elseif i == 3 then
                sim.hover()
            elseif i == 4 then
                sim.rtl()
            elseif i == 5 then
                sim.land()
            elseif i == 6 then
                sim.calibrate("compass")
            elseif i == 7 then
                -- 在 无 / GPS / 链路 之间轮换，方便演示告警态
                if s.fault == nil then
                    sim.inject_fault("gps")
                elseif s.fault == "gps" then
                    sim.inject_fault("link")
                else
                    sim.inject_fault(nil)
                end
            else
                sim.reset_stats()
            end
            return
        end
    end
end

function M.leave() end

return M
