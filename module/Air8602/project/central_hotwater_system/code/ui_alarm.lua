--[[
@module  ui_alarm
@summary 记录视图（报警统计 / 设备健康度 / 事件与报警记录）
@version 1.0.0
@date    2026.10.12
@usage
由 ui_shell 在切到「记录」时调用 create(parent,x,y,w,h,T)，
数据更新时调用 update(state)；切走时调用 destroy()。
点击事件项调用 mock_data.ack_alarm 标记已处理。
报警列表固定 6 条、不滚动（技能强制无滚动条）。
]]

local W = require "ui_widgets"
local mock_data = require "mock_data"

local M = {}
local handles = nil

local SEV = {
    crit = { tone = "red",   icon = "alarm" },
    warn = { tone = "amber", icon = "alarm" },
    info = { tone = "cyan",  icon = "loop" },
    ok   = { tone = "green", icon = "pump" },
}

local function build_stats(parent, x, y, w, h, T)
    local p = W.panel(parent, x, y, w, h, T)
    W.panel_title(p, 12, 14, w - 24, "报警统计", "近 7 天", T)
    local tiles = {
        { "今日报警", "amber" }, { "未处理", "red" },
        { "历史累计", "cyan" }, { "已恢复", "green" },
    }
    local g, tw, th = 10, math.floor((w - 24 - 10) / 2), 88
    local vals = {}
    for i = 1, 4 do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local bx = 12 + col * (tw + g)
        local by = 48 + row * (th + 8)
        local box = airui.container({ parent = p, x = W.d(bx), y = W.d(by), w = W.d(tw), h = W.d(th),
            radius = W.d(11), color = T.chip_bg, border_color = T.ring, border_width = 1 })
        W.label(box, 10, 12, tw - 20, 16, tiles[i][1], 10, T.text_dim)
        vals[i] = W.label(box, 10, 34, tw - 20, 32, "0", 24, W.tone(T, tiles[i][2]))
    end
    return vals
end

local function build_health(parent, x, y, w, h, T)
    local p = W.panel(parent, x, y, w, h, T)
    W.panel_title(p, 12, 14, w - 24, "设备健康度", nil, T)
    local val = W.label(p, 14, 52, 78, 42, "0", 30, T.green)
    W.label(p, 96, 70, 80, 20, "/100 分", 11, T.text_dim)
    local bar = W.bar(p, 14, 106, w - 30, 7, 0, T.green, T.bar_bg)
    W.label(p, 14, 126, w - 28, 18, "传感器在线 7/7 / 通信正常", 10, T.text_dim)
    W.label(p, 14, 146, w - 28, 18, "继电器动作正常 / 无硬件故障", 10, T.text_dim)
    return { val = val, bar = bar }
end

local function build_list(parent, x, y, w, h, T)
    local p = W.panel(parent, x, y, w, h, T)
    W.panel_title(p, 14, 14, w - 28, "事件与报警记录", "点击可标记处理", T)
    local items = {}
    local ih, ig = 70, 7
    for i = 1, 6 do
        local iy = 46 + (i - 1) * (ih + ig)
        local item = airui.container({
            parent = p, x = 14, y = W.d(iy), w = W.d(w - 28), h = W.d(ih),
            radius = W.d(11), color = T.chip_bg, border_color = T.ring, border_width = 1,
            on_click = function() mock_data.ack_alarm(i) end,
        })
        -- 左侧色条上下各留 2px，避免超出 item 内容区触发滚动条
        airui.container({ parent = item, x = 0, y = 2, w = 3, h = ih - 6, color = T.red })
        local ico = airui.container({ parent = item, x = 14, y = 20, w = 30, h = 30,
            radius = W.d(9), color = T.panel, border_color = T.ring, border_width = 1 })
        local ico_shape = W.icon(ico, "alarm", 7, 7, 16, T.red)
        -- 文本区宽度按 item 宽度（w-28）而非卡片宽度计算，避免与右侧标记重叠/越界
        local txt = W.label(item, 56, 12, w - 190, 22, "", 11.5, T.text)
        local meta = W.label(item, 56, 38, w - 190, 18, "", 9.5, T.text_dim)
        local tag_box = airui.container({ parent = item, x = W.d(w - 124), y = 14, w = 76, h = 22,
            radius = W.d(8), color = T.chip_bg })
        local tag = W.label(tag_box, 3, 1, 70, 20, "已处理", 9.5, T.text_dim, airui.TEXT_ALIGN_CENTER)
        items[i] = { box = item, ico = ico, shape = ico_shape, txt = txt, meta = meta,
                     tag_box = tag_box, tag = tag }
    end
    return items
end

function M.create(parent, x, y, w, h, T)
    local root = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = T.bg, color_opacity = 0,
    })
    local CW, CH = w - 2, h - 2
    local gap = 12
    local left_w = 266
    local right_w = CW - left_w - gap

    handles = { root = root, T = T }

    local stat_h = 252
    local health_h = CH - stat_h - gap
    handles.stat = build_stats(root, 0, 0, left_w, stat_h, T)
    handles.health = build_health(root, 0, stat_h + gap, left_w, health_h, T)
    handles.items = build_list(root, left_w + gap, 0, right_w, CH, T)

    return root
end

function M.update(st)
    if not handles then return end
    local T = handles.T

    local s = st.stats
    handles.stat[1]:set_text(tostring(s.today))
    handles.stat[2]:set_text(tostring(s.pending))
    handles.stat[3]:set_text(tostring(s.total))
    handles.stat[4]:set_text(tostring(s.recovered))

    handles.health.val:set_text(tostring(st.health))
    handles.health.bar:set_value(st.health)

    for i = 1, 6 do
        local a = st.alarms[i]
        local hd = handles.items[i]
        if a and hd then
            local tone = SEV[a.sev] or SEV.info
            local col = W.tone(T, tone.tone)
            hd.txt:set_text(a.txt)
            hd.meta:set_text(a.t .. "   " .. a.src)
            W.icon_set_color(hd.shape, tone.icon, 16, col)
            hd.ico:set_border_color(col, 1)
            if a.done then
                hd.tag_box:set_color(T.chip_bg, 255)
                hd.tag:set_text("已处理")
                hd.tag:set_color(T.text_dim)
            else
                hd.tag_box:set_color(T.amber, 255)
                hd.tag:set_text("待处理")
                hd.tag:set_color(0x2A1602)
            end
        end
    end
end

function M.destroy()
    if handles and handles.root then handles.root:destroy() end
    handles = nil
end

return M
