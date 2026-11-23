--[[
@module  theme
@summary 设计令牌：配色 / 几何 / 字号 + 少量控件封装
@note
  === 视觉取向 ===
  深空蓝黑底（近纯黑，长时间盯屏不刺眼）+ 单一冷色强调 + 琥珀/玫红只留给告警。
  信息层次只靠"亮度分级"和"字号分级"，不用多重色相去抢注意力。
  所有卡片 = shape 底板（圆角填充 + 1px 描边 + 顶部高光 + 角落柔光），
  不用 container —— container 就是 lv_obj_create，默认带 SCROLLABLE 标志，
  子对象包围盒超出 1px 就会画出滚动条，真机上表现为"卡片里多一圈方角细框"。

  === 坐标体系（1024x600）===
  顶栏      y    0 .. 52
  内容区    y   62 .. 540
  底部导航  y  552 .. 592
  水平安全边距 16

  === 字体 ===
  内置 MiSans 字库有 7619 字，· ● ° ℃ → 都有（可以直接 grep cmap 验证）。
  分隔符统一用 | 只是为了视觉干净，不是字体限制；温度单位统一写 ℃。
  字号只用 10 11 12 13 15 17 20 24 30 36 44 这几档，
  hzfont 每种字号首次使用时要建实例，档位越少内存越省。
]]

local M = {}

M.W, M.H = 1024, 600

-- 关键横线
M.TOP_H  = 52
M.NAV_Y  = 552
M.NAV_H  = 40
M.PAD    = 16

M.C = {
    -- 底色（从近黑到略微提亮的四层）
    bg0 = 0x060A11,
    bg1 = 0x0A1119,
    bg2 = 0x0F1926,

    -- 卡片
    panel   = 0x121E2C,
    panel2  = 0x0B1420,
    panel3  = 0x192838,
    line    = 0x24374C,
    line2   = 0x35506B,

    -- 文字三级
    ink  = 0xE8F1FB,
    ink2 = 0x93A9C2,
    ink3 = 0x5C728B,

    -- 通道色（两路温度：天青 / 紫罗兰，都不与告警色冲突）
    ch1 = 0x38BDF8,
    ch2 = 0xA78BFA,

    -- 状态色
    ok     = 0x34D399,
    warn   = 0xF5A524,
    alarm  = 0xF43F5E,
    info   = 0x60A5FA,
    off    = 0x4A5C72,
    on_pri = 0x04121A,
}

local C = M.C
M.chColor = { C.ch1, C.ch2 }

-- 兼容旧命名
C.cyan, C.primary = C.ch1, C.ch1
C.red, C.alarm_c = C.alarm, C.alarm
C.green, C.amber, C.violet = C.ok, C.warn, C.ch2
C.dim, C.t2 = C.ink3, C.ink2

M.f = {
    micro = 10,
    mini  = 11,
    sub   = 12,
    body  = 13,
    label = 15,
    title = 17,
    head  = 20,
    num   = 24,
    big   = 30,
    hero  = 36,
    huge  = 44,
}

-- ==================== 控件封装 ====================
local AL = airui.TEXT_ALIGN_LEFT
local AC = airui.TEXT_ALIGN_CENTER
local AR = airui.TEXT_ALIGN_RIGHT
M.AL, M.AC, M.AR = AL, AC, AR

function M.label(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "",
        font_size = size or M.f.body,
        color = color or C.ink,
        align = align or AL,
    })
end

-- 纯形状画布（不带任何默认底色）
function M.shape(parent, x, y, w, h)
    return airui.shape({ parent = parent, x = x, y = y, w = w, h = h, items = {} })
end

-- 按钮：AirUI 的配色在 style 子表里，直接传 color 会被忽略
function M.btn(parent, x, y, w, h, text, size, bg, fg, on_click, radius)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or M.f.label,
        style = {
            bg_color = bg or C.panel3, bg_opa = 255,
            text_color = fg or C.ink,
            radius = radius or 9,
            border_width = 0, border_color = bg or C.panel3,
            pressed_bg_color = C.line2, pressed_bg_opa = 255,
            pressed_text_color = 0xFFFFFF,
        },
        on_click = on_click,
    })
end

-- 描边按钮（次要操作）
function M.ghost(parent, x, y, w, h, text, size, fg, on_click, border)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or M.f.body,
        style = {
            bg_color = C.panel2, bg_opa = 255,
            text_color = fg or C.ink2,
            radius = 9,
            border_width = 1, border_color = border or C.line2,
            pressed_bg_color = C.line2, pressed_bg_opa = 255,
            pressed_text_color = 0xFFFFFF,
        },
        on_click = on_click,
    })
end

function M.apply_style(btn, st)
    pcall(function() btn:set_style(st) end)
end

-- 安全的延时执行（点击回调里不要直接改控件树）
function M.defer(fn, ms)
    return sys.timerStart(function()
        local ok, err = pcall(fn)
        if not ok then log.error("ui", "defer", tostring(err)) end
    end, ms or 16)
end

return M
