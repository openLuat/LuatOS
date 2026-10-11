--[[
@module  ui_settings
@summary 设置视图（色谱方法参数 + 系统配置）
@version 1.0.0
@date    2026.10.10
@usage
设置项的修改统一调用 mock_data / theme 的对外接口，
再由数据层广播 VOCS_DATA，本视图在 update 中回填显示值，
保证「数据是唯一事实来源」，界面不自行保存业务状态。
]]

local W = require "ui_widgets"
local config = require "config"
local mock_data = require "mock_data"
local theme = require "theme"

local M = {}
local handles = nil

function M.create(parent, x, y, w, h, T)
    local root = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = T.bg, color_opacity = 0,
    })

    -- 面板整体比视图容器内缩 2px，避免贴住内容区边界触发滚动条
    local vw, vh = w - 2, h - 2
    local gap = 12
    local pw = (vw - gap) / 2
    handles = { root = root, T = T, steppers = {}, toggles = {}, segs = {} }

    -- ============ 面板 A：色谱方法参数 ============
    local pa = W.panel(root, 0, 0, pw, vh, T)
    W.panel_title(pa, 12, 14, pw - 12, "色谱方法参数", "VOC-58", T)

    -- 行标题 + 小字说明 + 行分隔线（对应设计稿 .set-row 的下边框）
    local function title(panel, py, name, sub)
        W.label(panel, 15, py, 220, 18, name, 12.5, T.text_soft)
        -- 主标题与说明文字之间留 8px 左右，避免两行贴在一起
        if sub then W.label(panel, 15, py + 22, 240, 14, sub, 10, T.text_dim) end
        W.divider(panel, 15, py + 48, pw - 30, T.ring)
    end

    local A_ROWS = {
        { key = "column_temp", name = "柱温起始",   sub = "Column initial temp." },
        { key = "heat_rate",   name = "升温速率",   sub = "Heating rate" },
        { key = "inlet_temp",  name = "进样口温度", sub = "Inlet temperature" },
        { key = "split_ratio", name = "分流比",     sub = "Split ratio" },
        { key = "scan_range",  name = "扫描范围",   sub = "Scan range" },
    }
    for i, r in ipairs(A_ROWS) do
        local ry = 40 + (i - 1) * 71
        title(pa, ry, r.name, r.sub)
        local spec = config.param_spec[r.key]
        handles.steppers[r.key] = W.stepper(pa, pw - 161, ry + 8, spec, spec.min,
            function(dir) mock_data.step_param(r.key, dir) end, T)
    end
    do
        local ry = 40 + 5 * 71
        title(pa, ry, "载气类型", "Carrier gas")
        handles.segs.carrier = W.seg(pa, pw - 171, ry + 7, 156, 34,
            { "氦气 He", "氮气 N2" }, 1,
            function(_, opt) mock_data.set_carrier(opt) end, T)
    end

    -- ============ 面板 B：系统配置 ============
    local pb = W.panel(root, pw + gap, 0, pw, vh, T)
    W.panel_title(pb, 12, 14, pw - 12, "系统配置", "SYSTEM", T)

    local rows = {
        { name = "界面主题",     sub = "Theme style",              kind = "theme_seg" },
        { name = "自动校准",     sub = "每 4 小时执行一次",        kind = "switch", key = "auto_calib" },
        { name = "数据云端上传", sub = "实时同步监测数据",          kind = "switch", key = "cloud_upload" },
        { name = "超标声光报警", sub = "阈值 10 μg/m3",            kind = "switch", key = "alarm" },
        { name = "谱图实时平滑", sub = "Savitzky-Golay 滤波",      kind = "switch", key = "smooth" },
        { name = "通信协议",     sub = "Modbus TCP / RS-485",      kind = "proto_seg" },
        { name = "屏幕亮度",     sub = "Display brightness",        kind = "brightness" },
    }
    for i, r in ipairs(rows) do
        local ry = 40 + (i - 1) * 62
        title(pb, ry, r.name, r.sub)
        if r.kind == "switch" then
            handles.toggles[r.key] = W.toggle(pb, pw - 57, ry + 11, false,
                function(on) mock_data.set_switch(r.key, on) end, T)
        elseif r.kind == "theme_seg" then
            handles.segs.theme = W.seg(pb, pw - 171, ry + 7, 156, 34,
                { "深色", "浅色" }, (theme.name == "light") and 2 or 1,
                function(_, opt)
                    theme.set(opt == "深色" and "dark" or "light")
                    sys.publish("VOCS_THEME_CHANGED")
                end, T)
        elseif r.kind == "proto_seg" then
            handles.segs.protocol = W.seg(pb, pw - 171, ry + 7, 156, 34,
                { "Modbus", "RS-485" }, 1,
                function(_, opt) mock_data.set_protocol(opt) end, T)
        elseif r.kind == "brightness" then
            local spec = config.param_spec.brightness
            handles.steppers.brightness = W.stepper(pb, pw - 161, ry + 11, spec, spec.min,
                function(dir) mock_data.step_param("brightness", dir) end, T)
        end
    end

    return root
end

function M.update(st)
    if not handles then return end

    -- 色谱方法参数：回填步进器数值
    for key, hd in pairs(handles.steppers) do
        local v = (key == "brightness") and st.params.brightness or st.params[key]
        if v then hd.set(v) end
    end
    handles.segs.carrier.set(st.carrier == "氮气 N2" and 2 or 1)

    -- 系统配置：回填开关 / 分段
    for key, hd in pairs(handles.toggles) do
        hd.set(st.switches[key])
    end
    handles.segs.theme.set(theme.name == "light" and 2 or 1)
    handles.segs.protocol.set(st.protocol == "RS-485" and 2 or 1)
end

function M.destroy()
    if handles and handles.root then handles.root:destroy() end
    handles = nil
end

return M
