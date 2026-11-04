--[[
@module  theme
@summary 任务指挥控制台配色 + 基础控件封装（深空钢蓝 + 火箭琥珀 + 遥测青）
@version 1.0
@date    2026.11.04
]]
local M = {}

M.C = {
    -- 背景（控制室暗场，越往下越深）
    bg1      = 0x04070E,
    bg2      = 0x0A1220,
    bg3      = 0x070C16,

    -- 面板
    panel    = 0x0B1424,
    panel2   = 0x081020,
    panel3   = 0x122036,
    line     = 0x1A2A44,
    line2    = 0x2B4368,

    -- 文字
    ink      = 0xE8F1FF,
    ink2     = 0x9DB0CA,
    ink3     = 0x5A6F8C,

    -- 数据色
    amber    = 0xFFB02E,   -- 火箭 / 主强调
    amber2   = 0xFFD37A,
    cyan     = 0x3FD8F2,   -- 遥测
    blue     = 0x4C86FF,   -- 二级 / 轨道
    green    = 0x3FE08F,   -- 正常 / 通过
    red      = 0xFF4D5E,   -- 中止 / 告警
    violet   = 0x9E7BFF,
    white    = 0xFFFFFF,

    ok       = 0x3FE08F,
    warn     = 0xFFB02E,
    danger   = 0xFF4D5E,

    -- 发射台场景专用
    sky1     = 0x0B1B33,
    sky2     = 0x050A14,
    ground   = 0x0C1522,
    tower    = 0x22334C,
}

local C = M.C

-- ==================== 颜色工具 ====================
local function chan(c, shift)
    return math.floor(c / shift) % 256
end

function M.lerp_color(c1, c2, t)
    if t <= 0 then return c1 elseif t >= 1 then return c2 end
    local r1, g1, b1 = chan(c1, 65536), chan(c1, 256), chan(c1, 1)
    local r2, g2, b2 = chan(c2, 65536), chan(c2, 256), chan(c2, 1)
    local r = math.floor(r1 + (r2 - r1) * t + 0.5)
    local g = math.floor(g1 + (g2 - g1) * t + 0.5)
    local b = math.floor(b1 + (b2 - b1) * t + 0.5)
    return r * 65536 + g * 256 + b
end

-- 亮度缩放（做"暗一档"的次级文字/网格线）
function M.shade(color, k)
    local r = chan(color, 65536) * k
    local g = chan(color, 256) * k
    local b = chan(color, 1) * k
    if r > 255 then r = 255 end
    if g > 255 then g = 255 end
    if b > 255 then b = 255 end
    return math.floor(r) * 65536 + math.floor(g) * 256 + math.floor(b)
end

-- ==================== 基础控件 ====================
function M.label(parent, x, y, w, h, text, size, color, align)
    local lb = airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "",
        font = "hzfont",
        font_size = size or 16,
        color = color or C.ink,
    })
    if align and align ~= airui.TEXT_ALIGN_LEFT and lb.set_align then
        pcall(lb.set_align, lb, align)
    end
    return lb
end

function M.box(parent, x, y, w, h, color, radius, opacity)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.panel,
        color_opacity = opacity or 255,
        radius = radius or 0, border_width = 0,
    })
end

function M.frame(parent, x, y, w, h, color, radius, border, bw, opacity)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.panel, color_opacity = opacity or 255,
        radius = radius or 12,
        border_color = border or C.line, border_width = bw or 1,
    })
end

function M.card(parent, x, y, w, h, color, radius, line_color, line_width)
    return M.frame(parent, x, y, w, h, color or C.panel, radius or 12,
        line_color or C.line, line_width or 1)
end

-- 卡片左上角的 3px 强调条
function M.accent(parent, x, y, w, color)
    return M.box(parent, x, y, w, 3, color or C.amber, 2)
end

function M.hline(parent, x, y, w, color, opacity)
    return M.box(parent, x, y, w, 1, color or C.line, 0, opacity or 255)
end

--[[实心按钮
]]
function M.button(parent, x, y, w, h, text, size, bg, fg, on_click, radius)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font = "hzfont", font_size = size or 20,
        style = {
            bg_color = bg or C.amber, bg_opa = 255,
            text_color = fg or 0x0A0F18,
            radius = radius or 12,
            border_width = 0,
            border_color = bg or C.amber,
            pressed_bg_color = C.amber2,
            pressed_text_color = 0x0A0F18,
        },
        on_click = on_click,
    })
end

--[[描边按钮（次级操作）
]]
function M.ghost(parent, x, y, w, h, text, size, fg, on_click, border)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font = "hzfont", font_size = size or 16,
        style = {
            bg_color = C.panel3, bg_opa = 255,
            text_color = fg or C.ink2,
            radius = 12,
            border_width = 1,
            border_color = border or C.line2,
            pressed_bg_color = C.line2,
            pressed_text_color = C.white,
        },
        on_click = on_click,
    })
end

--[[胶囊：返回 box 与内部 label
]]
function M.pill(parent, x, y, w, h, text, color, size)
    local col = color or C.cyan
    local box = M.box(parent, x, y, w, h, col, h / 2, 40)
    local lb = M.label(box, 0, math.floor((h - (size or 13)) / 2) - 1, w, (size or 13) + 6,
        text or "", size or 13, col, airui.TEXT_ALIGN_CENTER)
    return box, lb
end

-- shape 图元的坐标最终由 C 层 airui_marshal_integer -> lua_tointeger 取出。
-- lua_tointeger 只能转换"整数值的浮点"：42.0 得到 42，42.7 直接得到 0。
-- 一旦传入未取整的坐标（曲线插值、相机滚动都会产生小数），整条线段会塌到
-- shape 左上角 (0,0)，表现为"曲线贴着卡片顶部"或"末尾一条竖线"。
-- 所以所有进图元表的数值字段必须在这里统一 floor，不要指望调用方每次都记得。
local INT_FIELD = {
    x = true, y = true, w = true, h = true, radius = true,
    x1 = true, y1 = true, x2 = true, y2 = true,
    cx = true, cy = true, r = true, rx = true, ry = true,
    width = true, dash_width = true, dash_gap = true,
    opacity = true, fill_opacity = true,
    segments = true, start_angle = true, end_angle = true,
}

--- 就地修正图元表：补齐填充色 + 数值字段取整
function M.fix_items(items)
    for i = 1, #items do
        local it = items[i]
        if it.fill then
            if it.color == nil then it.color = it.fill_color or 0xFFFFFF end
            if it.opacity == nil then it.opacity = it.fill_opacity or 255 end
        end
        for k, v in pairs(it) do
            if INT_FIELD[k] and type(v) == "number" then
                it[k] = math.floor(v)
            end
        end
    end
    return items
end

--- 统一的 set_items：先取整再交给 airui
function M.set_items(obj, items)
    obj:set_items(M.fix_items(items))
end

function M.shape(config)
    if config and config.items then M.fix_items(config.items) end
    return airui.shape(config)
end

function M.defer(fn, ms)
    return sys.timerStart(function()
        local ok, err = pcall(fn)
        if not ok then log.error("ui", "defer error", tostring(err)) end
    end, ms or 20)
end

-- ==================== 语音参数 ====================
-- 固件本地 TTS（exaudio.play_start type=1），DAC + HT6873 功放。
-- 指挥中心是看大屏的场合，语音只念"任务节点"，音量 18 够穿透展厅噪声。
M.audio = {
    model       = "dac",
    vol         = 18,
    priority    = 200,
    pa_ctrl     = 73,
    pa_on_level = 1,
    dac_delay   = 6,

    boot        = true,
    boot_text   = "任务指挥中心已启动，等待发射指令",
    auto_gap    = 3,
}

return M
