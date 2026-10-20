--[[
@module  ui_ctrl
@summary 控制视图（3 个控制模式 / 循环泵运行状态 / 运行模式与保护）
@version 1.0.0
@date    2026.10.12
@usage
由 ui_shell 在切到「控制」时调用 create(parent,x,y,w,h,T)，
数据更新时调用 update(state)；切走时调用 destroy()。
交互（模式启停 / 保护开关 / 自动手动）调用 mock_data 接口，界面不自行保存状态。
]]

local W = require "ui_widgets"
local mock_data = require "mock_data"

local M = {}
local handles = nil

local MODE_ICON = { dt_loop = "loop", water_fill = "drop", elec_heat = "bolt" }

-- ============ 模式卡 ============
local function build_mode(parent, x, y, w, h, mode, index, T)
    local card = airui.container({
        parent = parent, x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(h),
        radius = W.d(12), color = T.panel, border_color = T.ring, border_width = 1,
        on_click = function() mock_data.toggle_mode(index) end,
    })
    local c = W.tone(T, mode.tone)
    local ico = airui.container({ parent = card, x = 12, y = 12, w = 30, h = 30,
        radius = W.d(10), color = T.accent_soft, border_color = c, border_width = 1 })
    W.icon(ico, MODE_ICON[mode.key] or "loop", 7, 7, 16, c)
    local badge_box = airui.container({ parent = card, x = W.d(w - 66), y = 14, w = 54, h = 20,
        radius = W.d(10), color = T.cyan })
    local badge_lbl = W.label(badge_box, 2, 1, 50, 18, "已启用", 9.5, 0x04222B, airui.TEXT_ALIGN_CENTER)
    W.label(card, 12, 48, w - 24, 22, mode.title, 12.5, T.text)
    W.label(card, 12, 70, w - 28, 36, mode.desc, 9.5, T.text_dim)

    local vals = {}
    for i = 1, #mode.rows do
        local ry = 110 + (i - 1) * 18
        W.label(card, 12, ry, 200, 16, mode.rows[i][1], 10, T.text_soft)
        local v = mode.rows[i][2] .. mode.rows[i][3]
        vals[i] = W.label(card, 12, ry, w - 24, 16, v, 10.5, T.text_bright, airui.TEXT_ALIGN_RIGHT)
    end
    return { card = card, ico = ico, badge_box = badge_box, badge_lbl = badge_lbl, vals = vals }
end

-- ============ 循环泵运行状态 ============
local function build_pump(parent, x, y, w, h, T)
    local p = W.panel(parent, x, y, w, h, T)
    W.panel_title(p, 12, 14, w - 160, "循环泵运行状态", nil, T)
    local badge_box = airui.container({ parent = p, x = W.d(w - 106), y = 12, w = 94, h = 20,
        radius = W.d(10), color = T.cyan })
    local badge_lbl = W.label(badge_box, 2, 1, 90, 18, "KM1 运行中", 9.5, 0x04222B, airui.TEXT_ALIGN_CENTER)

    local ring = W.ring(p, 20, 52, 126, 8, -90, 360, T.bar_bg)
    local state = W.label(p, 20, 104, 126, 22, "RUNNING", 11, T.green, airui.TEXT_ALIGN_CENTER)

    local kvs = {}
    local names = { "实时功率", "运行时长", "今日启动", "累计流量" }
    for i = 1, 4 do
        local ry = 62 + (i - 1) * 34
        W.label(p, 170, ry, 110, 18, names[i], 10.5, T.text_dim)
        kvs[i] = W.label(p, 220, ry, w - 236, 18, "--", 12, T.text_bright, airui.TEXT_ALIGN_RIGHT)
    end

    -- 近 12 小时运行占比（分段条）
    local track = airui.container({ parent = p, x = 20, y = W.d(h - 26), w = W.d(w - 40), h = W.d(6),
        radius = W.d(3), color = T.bar_bg })
    local segs = {}
    local tw = math.floor(w - 40)
    local cx = 0
    for i = 1, 7 do
        local v = 0
        local bw = math.max(0, math.floor(tw / 7) - 2)
        local box = airui.container({ parent = track, x = W.d(cx), y = 0, w = W.d(bw), h = W.d(6),
            radius = W.d(3), color = T.bar_bg })
        segs[i] = { box = box, on = false }
        cx = cx + math.floor(tw / 7)
    end
    return { ring = ring, state = state, badge_box = badge_box, badge_lbl = badge_lbl, kvs = kvs, segs = segs }
end

-- ============ 运行模式与保护 ============
local PROTS = {
    { key = "auto_run",   label = "自动运行模式" },
    { key = "antifreeze", label = "防冻保护" },
    { key = "overtemp",   label = "高温保护 85℃" },
    { key = "dry_burn",   label = "防干烧保护" },
}
local function build_proto(parent, x, y, w, h, T)
    local p = W.panel(parent, x, y, w, h, T)
    W.panel_title(p, 12, 14, w - 120, "运行模式与保护", nil, T)
    local badge_box = airui.container({ parent = p, x = W.d(w - 76), y = 12, w = 64, h = 20,
        radius = W.d(10), color = T.cyan,
        on_click = function()
            local m = mock_data.get()
            mock_data.set_mode((m.mode == "自动") and "手动" or "自动")
        end })
    local badge_lbl = W.label(badge_box, 2, 1, 60, 18, "自动", 9.5, 0x04222B, airui.TEXT_ALIGN_CENTER)

    local pad, gap = 12, 8
    local iw = math.floor((w - pad * 2 - gap) / 2)
    local ih = 52
    local sws = {}
    for i, pr in ipairs(PROTS) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local ix = pad + col * (iw + gap)
        local iy = 42 + row * (ih + gap)
        local item = airui.container({
            parent = p, x = W.d(ix), y = W.d(iy), w = W.d(iw), h = W.d(ih),
            radius = W.d(10), color = T.chip_bg, border_color = T.ring, border_width = 1,
            on_click = function() mock_data.toggle_prot(pr.key) end,
        })
        W.label(item, 10, 16, iw - 64, 20, pr.label, 11, T.text_soft)
        sws[pr.key] = W.toggle(item, iw - 52, 15, false, nil, T)
    end
    return { badge_box = badge_box, badge_lbl = badge_lbl, sws = sws }
end

function M.create(parent, x, y, w, h, T)
    local root = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = T.bg, color_opacity = 0,
    })
    local CW, CH = w - 2, h - 2
    local gap = 12
    local right_w = 404
    local left_w = CW - right_w - gap

    handles = { root = root, T = T, mode = {} }

    -- 左列：3 张模式卡
    local mgap = 8
    local mh = math.floor((CH - mgap * 2) / 3)
    for i = 1, 3 do
        handles.mode[i] = build_mode(root, 0, (i - 1) * (mh + mgap), left_w, mh,
            mock_data.get().modes[i], i, T)
    end

    -- 右列：泵状态 + 保护
    local rx = left_w + gap
    local proto_h = 172
    local pump_h = CH - proto_h - gap
    handles.pump = build_pump(root, rx, 0, right_w, pump_h, T)
    handles.proto = build_proto(root, rx, pump_h + gap, right_w, proto_h, T)

    return root
end

function M.update(st)
    if not handles then return end
    local T = handles.T

    -- 模式卡状态
    for i = 1, 3 do
        local m = st.modes[i]
        local hd = handles.mode[i]
        if m and hd then
            if m.on then
                hd.badge_lbl:set_text("已启用")
                hd.badge_box:set_color(T.cyan, 255)
                hd.badge_lbl:set_color(0x04222B)
            else
                hd.badge_lbl:set_text("待机")
                hd.badge_box:set_color(T.chip_bg, 255)
                hd.badge_lbl:set_color(T.text_dim)
            end
            for k = 1, #m.rows do
                hd.vals[k]:set_text(m.rows[k][2] .. m.rows[k][3])
            end
        end
    end

    -- 泵状态
    local pm = handles.pump
    local on = st.cyc_on
    pm.state:set_text(on and "RUNNING" or "STANDBY")
    pm.state:set_color(on and T.green or T.text_dim)
    pm.ring.set(on and math.min(1, st.pump.power / 1.6) or 0.02, T.cyan)
    pm.badge_lbl:set_text(on and "KM1 运行中" or "KM1 已停止")
    pm.badge_box:set_color(on and T.cyan or T.chip_bg, 255)
    pm.badge_lbl:set_color(on and 0x04222B or T.text_dim)
    pm.kvs[1]:set_text(string.format("%.2f kW", st.pump.power))
    pm.kvs[2]:set_text(st.pump.runtime)
    pm.kvs[3]:set_text(st.pump.today .. " 次")
    pm.kvs[4]:set_text(string.format("%.1f m3", st.pump.flow))
    for i = 1, #pm.segs do
        local onseg = (st.pump.timeline[i] or 0) > 0
        pm.segs[i].box:set_color(onseg and T.cyan or T.bar_bg, 255)
    end

    -- 保护开关
    local pr = handles.proto
    for key, sw in pairs(pr.sws) do sw.set(st.prot[key]) end
    local auto = (st.mode == "自动")
    pr.badge_lbl:set_text(st.mode)
    pr.badge_box:set_color(auto and T.cyan or T.amber, 255)
    pr.badge_lbl:set_color(auto and 0x04222B or 0x2A1602)
end

function M.destroy()
    if handles and handles.root then handles.root:destroy() end
    handles = nil
end

return M
