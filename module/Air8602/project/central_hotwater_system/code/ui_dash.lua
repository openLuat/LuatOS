--[[
@module  ui_dash
@summary 监控视图（5 温度卡 / 水箱水位 / 系统压力 / 集热循环 / 6 路继电器）
@version 1.0.0
@date    2026.10.12
@usage
由 ui_shell 在切到「监控」时调用 create(parent,x,y,w,h,T)，
数据更新时调用 update(state)；切走时调用 destroy()。
本模块只负责渲染；交互（继电器切换）调用 mock_data 接口，数据由数据层统一广播。
]]

local W = require "ui_widgets"
local mock_data = require "mock_data"

local M = {}
local handles = nil

-- ============ 温度卡 ============
local function temp_card(parent, x, y, w, h, T)
    local card = W.panel(parent, x, y, w, h, T, nil, true)
    local tone_bar = airui.container({ parent = card, x = 1, y = 14, w = 3, h = h - 28, color = T.cyan })
    local tag_box = airui.container({ parent = card, x = 10, y = 10, w = 34, h = 18,
        radius = W.d(5), color = T.accent_soft })
    local tag = W.label(tag_box, 2, 1, 30, 16, "T1", 9, T.cyan, airui.TEXT_ALIGN_CENTER)
    local name = W.label(card, 50, 10, w - 58, 18, "", 11, T.text_soft)
    local val = W.label(card, 11, 32, w - 70, 44, "0.0", 30, T.text_bright)
    local unit = W.label(card, w - 56, 54, 44, 20, "℃", 11, T.cyan)
    local spark = W.spark(card, 12, 88, w - 24, 20, T.cyan)
    local foot_l = W.label(card, 11, 110, w - 88, 15, "", 9.5, T.text_dim)
    local foot_r = W.label(card, w - 76, 110, 64, 15, "", 9.5, T.text_dim, airui.TEXT_ALIGN_RIGHT)
    local bar = W.bar(card, 2, h - 8, w - 5, 4, 0, T.cyan, T.bar_bg)
    return { card = card, tag = tag, tag_box = tag_box, name = name, val = val, unit = unit,
        spark = spark, foot_l = foot_l, foot_r = foot_r, bar = bar, tone_bar = tone_bar }
end

-- ============ 水箱水位 ============
local function build_tank(parent, x, y, w, h, T)
    local p = W.panel(parent, x, y, w, h, T)
    W.panel_title(p, 12, 14, w - 100, "水箱水位", nil, T)
    -- 状态徽标（可动态改色）
    local badge_box = airui.container({ parent = p, x = w - 66, y = 12, w = 54, h = 20,
        radius = W.d(10), color = T.green })
    local badge_lbl = W.label(badge_box, 2, 1, 50, 18, "正常", 9.5, 0x0A2218, airui.TEXT_ALIGN_CENTER)

    -- 水箱（水体 + 刻度）
    local tank = W.tank(p, 12, 46, 84, 132, T, T.blue)
    W.label(p, 20, 52, 40, 14, "100%", 8.5, T.text_dim)
    W.label(p, 20, 106, 40, 14, "50%", 8.5, T.text_dim)
    W.label(p, 20, 162, 40, 14, "0%", 8.5, T.text_dim)

    -- 大数值 + 单位
    local val = W.label(p, 110, 56, 96, 46, "0", 38, T.text_bright)
    W.label(p, 200, 82, 34, 22, "%", 13, T.cyan)

    -- 迷你清单（3 行）
    local rows = {}
    local items = { { "水箱容积", "5.0 m3" }, { "当前水量", "-- m3" }, { "上水阀 KM2", "已关闭" } }
    for i = 1, 3 do
        local ry = 118 + (i - 1) * 26
        W.label(p, 112, ry, 90, 18, items[i][1], 10.5, T.text_dim)
        rows[i] = W.label(p, 150, ry, 104, 18, items[i][2], 10.5, T.text, airui.TEXT_ALIGN_RIGHT)
    end
    return { badge_box = badge_box, badge_lbl = badge_lbl, tank = tank, val = val, rows = rows }
end

-- ============ 系统压力 ============
local function build_press(parent, x, y, w, h, T)
    local p = W.panel(parent, x, y, w, h, T)
    W.panel_title(p, 12, 14, w - 24, "系统压力", nil, T)
    local ring = W.ring(p, 29, 34, 132, 9, 135, 270, T.bar_bg)
    local val = W.label(p, 30, 84, 130, 40, "0.00", 26, T.text_bright, airui.TEXT_ALIGN_CENTER)
    W.label(p, 30, 122, 130, 20, "MPa", 10.5, T.amber, airui.TEXT_ALIGN_CENTER)
    W.label(p, 12, h - 26, 120, 16, "量程 0-1.0 MPa", 10, T.text_dim)
    local tag = W.label(p, w - 90, h - 26, 78, 16, "压力正常", 10, T.green, airui.TEXT_ALIGN_RIGHT)
    return { ring = ring, val = val, tag = tag }
end

-- ============ 集热循环 ============
local function build_cyc(parent, x, y, w, h, T)
    local p = W.panel(parent, x, y, w, h, T)
    W.panel_title(p, 12, 14, w - 140, "集热循环 / 温差控制", nil, T)
    local badge_box = airui.container({ parent = p, x = w - 76, y = 12, w = 64, h = 20,
        radius = W.d(10), color = T.cyan })
    local badge_lbl = W.label(badge_box, 2, 1, 60, 18, "运行中", 9.5, 0x04222B, airui.TEXT_ALIGN_CENTER)

    -- 温差块（左）
    W.label(p, 14, 44, 150, 18, "DT 温差 (T1 - T2)", 10.5, T.text_dim)
    local dt = W.label(p, 14, 62, 104, 46, "0.0", 34, T.text_bright)
    W.label(p, 108, 84, 34, 22, "℃", 12, T.amber)
    W.label(p, 14, 116, 150, 16, "启动阈值 >= 8.0℃", 10, T.text_dim)
    W.label(p, 14, 134, 150, 16, "停止阈值 <= 3.0℃", 10, T.text_dim)

    -- 管道 + 3 统计块（右）
    local rx = 168
    local rw = w - rx - 14
    W.pipe(p, rx, 46, rw, T.cyan, T.ring)
    local stats = {}
    local tw = math.floor((rw - 16) / 3)
    local names = { "循环泵", "今日循环", "累计运行" }
    for i = 1, 3 do
        local sx = rx + (i - 1) * (tw + 8)
        local box = airui.container({ parent = p, x = W.d(sx), y = W.d(92), w = W.d(tw), h = W.d(74),
            radius = W.d(9), color = T.chip_bg, border_color = T.ring, border_width = 1 })
        W.label(box, 6, 6, tw - 10, 16, names[i], 9, T.text_dim)
        stats[i] = W.label(box, 6, 34, tw - 10, 26, "--", 12.5, T.text_bright)
    end
    return { badge_box = badge_box, badge_lbl = badge_lbl, dt = dt, stats = stats }
end

-- ============ 继电器 ============
local RELAY_ICON = { "pump", "drop", "bolt", "pump", "back", "coil" }
local function build_relays(parent, x, y, w, h, T)
    local p = W.panel(parent, x, y, w, h, T)
    W.panel_title(p, 12, 14, w - 24, "继电器输出", "6 路干接点 / 点击可手动切换", T)
    local cg, pad = 10, 10
    local cw = math.floor((w - pad * 2 - cg * 5) / 6)
    local ch = h - 56            -- 单张继电器卡高度
    local cards = {}
    for i = 1, 6 do
        local cx = pad + (i - 1) * (cw + cg)
        local card = airui.container({ parent = p, x = W.d(cx), y = W.d(46), w = W.d(cw), h = W.d(ch),
            radius = W.d(11), color = T.chip_bg, border_color = T.ring, border_width = 1 })
        local ico = airui.container({ parent = card, x = 10, y = 10, w = 26, h = 26,
            radius = W.d(8), color = T.panel, border_color = T.ring, border_width = 1 })
        W.icon(ico, RELAY_ICON[i], 6, 6, 15, T.text_soft)
        local sw = W.toggle(card, cw - 52, 10, false,
            function() mock_data.toggle_relay(i) end, T)
        local name = W.label(card, 10, 42, cw - 20, 18, "", 11, T.text)
        local code = W.label(card, 10, ch - 22, cw - 48, 16, "", 9.5, T.text_dim)
        local state = W.label(card, cw - 44, ch - 22, 34, 16, "OFF", 9.5, T.text_dim, airui.TEXT_ALIGN_RIGHT)
        cards[i] = { card = card, sw = sw, name = name, code = code, state = state }
    end
    return cards
end

function M.create(parent, x, y, w, h, T)
    local root = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = T.bg, color_opacity = 0,
    })
    -- 内容区比视图容器内缩 2px，避免子控件贴住内容区边界触发滚动条
    local CW, CH = w - 2, h - 2
    local gap = 12
    local row1, row3 = 140, 154
    local row2 = CH - row1 - row3 - gap * 2
    local y2 = row1 + gap
    local y3 = y2 + row2 + gap

    handles = { root = root, T = T, temp = {} }

    -- 行1：5 张温度卡
    local cg = 10
    local cw = math.floor((CW - 4 * cg) / 5)
    for i = 1, 5 do
        handles.temp[i] = temp_card(root, (i - 1) * (cw + cg), 0, cw, row1, T)
    end

    -- 行2：水位 + 压力 + 集热循环
    local tank_w, press_w = 268, 190
    local cyc_w = CW - tank_w - press_w - gap * 2
    handles.tank = build_tank(root, 0, y2, tank_w, row2, T)
    handles.press = build_press(root, tank_w + gap, y2, press_w, row2, T)
    handles.cyc = build_cyc(root, tank_w + press_w + gap * 2, y2, cyc_w, row2, T)

    -- 行3：6 路继电器
    handles.relay = build_relays(root, 0, y3, CW, row3, T)

    return root
end

function M.update(st)
    if not handles then return end
    local T = handles.T

    -- 温度卡
    for i = 1, 5 do
        local t = st.temps[i]
        local hd = handles.temp[i]
        if t and hd then
            local c = W.tone(T, t.tone)
            hd.tag:set_text(t.tag)
            hd.tag:set_color(c)
            hd.tag_box:set_color(T.accent_soft, 255)
            hd.name:set_text(t.name)
            hd.val:set_text(string.format("%.1f", t.v))
            hd.unit:set_color(c)
            hd.tone_bar:set_color(c, 255)
            hd.spark.update(t.hist, c)
            local pct = (t.v - t.min) / (t.max - t.min) * 100
            hd.bar:set_indicator_color(c)
            hd.bar:set_value(math.floor(pct + 0.5))
            hd.foot_r:set_text(string.format("%d-%d℃", t.min, t.max))
            local txt, col = "采样正常", T.green
            if t.v > t.hi then txt, col = "高温", T.red
            elseif t.v < t.lo then txt, col = "偏低", T.amber end
            hd.foot_l:set_text(txt)
            hd.foot_l:set_color(col)
        end
    end

    -- 水箱
    local tk = handles.tank
    local lvl = st.level
    tk.val:set_text(tostring(math.floor(lvl + 0.5)))
    tk.tank.set(lvl / 100, T.blue)
    tk.rows[2]:set_text(string.format("%.2f m3", st.volume))
    tk.rows[3]:set_text(st.valve)
    tk.rows[3]:set_color((st.valve == "上水中") and T.green or T.text)
    local bt, bc = "正常", T.green
    if lvl >= 95 then bt, bc = "已满", T.cyan
    elseif lvl <= 20 then bt, bc = "低水位", T.red
    elseif lvl <= 30 then bt, bc = "偏低", T.amber end
    tk.badge_lbl:set_text(bt)
    tk.badge_box:set_color(bc, 255)
    tk.badge_lbl:set_color(0x04222B)

    -- 压力
    local pr = handles.press
    pr.val:set_text(string.format("%.2f", st.press))
    local pct = st.press / 1.0
    local pcol = (st.press > 0.75) and T.red or ((st.press < 0.12) and T.amber or T.green)
    pr.ring.set(pct, pcol)
    local pt, pc = "压力正常", T.green
    if st.press > 0.75 then pt, pc = "压力偏高", T.red
    elseif st.press < 0.12 then pt, pc = "压力偏低", T.amber end
    pr.tag:set_text(pt)
    pr.tag:set_color(pc)

    -- 集热循环
    local cy = handles.cyc
    cy.dt:set_text(string.format("%.1f", st.dt))
    if st.cyc_on then
        cy.badge_lbl:set_text("运行中")
        cy.badge_box:set_color(T.cyan, 255)
        cy.badge_lbl:set_color(0x04222B)
    else
        cy.badge_lbl:set_text("待机")
        cy.badge_box:set_color(T.chip_bg, 255)
        cy.badge_lbl:set_color(T.text_dim)
    end
    cy.stats[1]:set_text(st.cyc_on and "运行" or "停止")
    cy.stats[2]:set_text(tostring(st.pump.today) .. " 次")
    cy.stats[3]:set_text(st.pump.runtime)

    -- 继电器
    for i = 1, 6 do
        local r = st.relays[i]
        local hd = handles.relay[i]
        if r and hd then
            hd.sw.set(r.on)
            hd.name:set_text(r.name)
            hd.code:set_text(r.code .. " " .. r.note)
            hd.state:set_text(r.on and "ON" or "OFF")
            hd.state:set_color(r.on and T.green or T.text_dim)
        end
    end
end

function M.destroy()
    if handles and handles.root then handles.root:destroy() end
    handles = nil
end

return M
