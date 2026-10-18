--[[
@module  ui_param
@summary 设置视图（温度参数 / 水位参数 / 时间与通讯 + 恢复出厂 / 保存下发）
@version 1.0.0
@date    2026.10.12
@usage
由 ui_shell 在切到「设置」时调用 create(parent,x,y,w,h,T)，
数据更新时调用 update(state)；切走时调用 destroy()。
步进修改调用 mock_data.step_param，保存/恢复调用 mock_data.save_params / reset_params。
]]

local W = require "ui_widgets"
local config = require "config"
local mock_data = require "mock_data"

local M = {}
local handles = nil

local function fmt(key, v)
    local spec = config.param_spec[key]
    local txt
    if spec and spec.step < 1 then txt = string.format("%.1f", v) else txt = tostring(math.floor(v + 0.5)) end
    return txt .. (spec and spec.unit or "")
end

local function build_group(parent, x, y, w, h, title, hint, icon, T)
    local p = W.panel(parent, x, y, w, h, T)
    local ib = airui.container({ parent = p, x = 12, y = 12, w = 26, h = 26,
        radius = W.d(8), color = T.accent_soft, border_color = T.ring, border_width = 1 })
    W.icon(ib, icon, 6, 6, 14, T.cyan)
    W.label(p, 46, 14, w - 120, 22, title, 12.5, T.text)
    W.label(p, w - 96, 16, 82, 18, hint, 9.5, T.text_dim, airui.TEXT_ALIGN_RIGHT)
    return p
end

-- 文本 pill
local function pill(parent, x, y, w, text, T)
    local box = airui.container({ parent = parent, x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(26),
        radius = W.d(8), color = T.chip_bg, border_color = T.ring, border_width = 1 })
    return W.label(box, 2, 3, w - 4, 20, text, 11, T.text_bright, airui.TEXT_ALIGN_CENTER)
end

-- 主题色取用（toast 颜色）：0=amber, 1=green
local function theme_color(k)
    local T = handles and handles.T
    if not T then return 0x22D3EE end
    return (k == 0) and T.amber or T.green
end

function M.create(parent, x, y, w, h, T)
    local root = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = T.bg, color_opacity = 0,
    })
    local CW, CH = w - 2, h - 2
    local gap = 10
    local btn_h = 44
    local card_h = CH - btn_h - gap
    local gw = math.floor((CW - gap * 2) / 3)

    local st = mock_data.get()
    handles = { root = root, T = T, step = {}, text = {} }

    local groups = {
        { title = "温度参数", hint = "℃", icon = "thermo", rows = st.set_temp, kind = "step" },
        { title = "水位参数", hint = "%", icon = "drop", rows = st.set_level, kind = "step" },
        { title = "时间与通讯", hint = "485 / 4G", icon = "param", rows = st.set_comm, kind = "comm" },
    }

    for gi, g in ipairs(groups) do
        local gx = (gi - 1) * (gw + gap)
        local p = build_group(root, gx, 0, gw, card_h, g.title, g.hint, g.icon, T)
        local n = #g.rows
        local y0 = 50
        local pitch = math.floor((card_h - y0 - 10) / n)
        for i, r in ipairs(g.rows) do
            local ry = y0 + (i - 1) * pitch
            W.label(p, 14, ry + 4, gw - 172, 20, r.label, 11, T.text_soft)
            local is_text = (g.kind == "comm") and (r.type == "text")
            if is_text then
                handles.text[r.key] = pill(p, gw - 14 - 110, ry, 110, r.val, T)
            else
                handles.step[r.key] = W.stepper(p, gw - 14 - 150, ry, 150,
                    fmt(r.key, st.params[r.key]), function(dir) mock_data.step_param(r.key, dir) end, T)
            end
        end
    end

    -- 底部按钮
    local by = card_h + gap
    local reset_w = math.floor((CW - gap) / 3)
    local reset = airui.container({
        parent = root, x = 0, y = W.d(by), w = W.d(reset_w), h = W.d(btn_h),
        radius = W.d(11), color = T.panel, border_color = T.ring, border_width = 1,
        on_click = function()
            mock_data.reset_params()
            sys.publish("SOLAR_TOAST", { color = theme_color(0), title = "已恢复出厂参数", sub = "请点击保存以写入主控" })
        end,
    })
    W.label(reset, 2, 11, reset_w - 4, 22, "恢复出厂参数", 12.5, T.text_soft, airui.TEXT_ALIGN_CENTER)
    handles.save = W.btn(root, reset_w + gap, by, CW - reset_w - gap, btn_h, "保存并下发到主控",
        function()
            mock_data.save_params()
            sys.publish("SOLAR_TOAST", { color = theme_color(1), title = "参数已保存并下发", sub = "主控已确认，参数生效" })
        end, T)

    return root
end

function M.update(st)
    if not handles then return end
    for key, hd in pairs(handles.step) do
        local v = st.params[key]
        if v then hd.set(fmt(key, v)) end
    end
end

function M.destroy()
    if handles and handles.root then handles.root:destroy() end
    handles = nil
end

return M
