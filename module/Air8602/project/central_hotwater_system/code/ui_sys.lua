--[[
@module  ui_sys
@summary 系统视图（设备信息 / 4G通信 / 存储SD / 串口485 / 采集通道 / 电源与输出）
@version 1.0.0
@date    2026.10.12
@usage
由 ui_shell 在切到「系统」时调用 create(parent,x,y,w,h,T)，
数据更新时调用 update(state)；纯展示，无交互。
]]

local W = require "ui_widgets"

local M = {}
local handles = nil

local function build_card(parent, x, y, w, h, info, T)
    local p = W.panel(parent, x, y, w, h, T)
    W.panel_title(p, 12, 14, w - 24, info.title, info.sub, T)
    if info.badge then
        W.badge(p, w - 12 - 62, 12, 62, 20, info.badge.text, info.badge.tone, T)
    end

    local ry0 = 46

    -- 信号强度
    if info.signal then
        local sg = info.signal
        local baseline = 46 + 34
        for i = 1, 4 do
            local bh = 9 + (i - 1) * 8
            local col = (i <= sg.level) and T.green or T.toggle_off
            airui.container({ parent = p, x = W.d(14 + (i - 1) * 12), y = W.d(baseline - bh),
                w = W.d(8), h = W.d(bh), radius = W.d(3), color = col })
        end
        W.label(p, 78, 40, 96, 32, sg.val, 24, T.text_bright)
        W.label(p, 168, 50, 60, 20, sg.unit, 10.5, T.text_dim)
        W.label(p, 78, 72, 160, 16, sg.note, 10, T.green)
        ry0 = 100
    end

    -- 存储 meters
    if info.meters then
        local my0 = 46
        for i, m in ipairs(info.meters) do
            local my = my0 + (i - 1) * 50
            W.kv(p, 14, my, w - 28, m[1], m[2], nil, T)
            W.bar(p, 14, my + 24, w - 30, 7, m[3], T.cyan, T.bar_bg)
        end
        ry0 = my0 + #info.meters * 50 + 4
    end

    -- 键值行
    local rows = info.rows or {}
    local n = #rows
    if n > 0 then
        local pitch = math.floor((h - ry0 - 6) / n)
        for i, r in ipairs(rows) do
            W.kv(p, 14, ry0 + (i - 1) * pitch, w - 28, r[1], r[2], r[3], T, info.val_w)
        end
    end
    return p
end

function M.create(parent, x, y, w, h, T)
    local root = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = T.bg, color_opacity = 0,
    })
    local CW, CH = w - 2, h - 2
    local gap = 12
    local cw = math.floor((CW - gap * 2) / 3)
    local ch = math.floor((CH - gap) / 2)

    handles = { root = root, T = T }

    local info = (require "mock_data").get().sysinfo
    for i = 1, 6 do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        build_card(root, col * (cw + gap), row * (ch + gap), cw, ch, info[i], T)
    end

    return root
end

function M.update(st)
    if not handles then return end
    -- 系统信息为静态展示，无动态字段
end

function M.destroy()
    if handles and handles.root then handles.root:destroy() end
    handles = nil
end

return M
