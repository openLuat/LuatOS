--[[
@module  theme
@summary 充放电终端主题 —— VoltAgent 翠绿信号
@description
  配色与布局逐像素映射自 HTML 效果稿（docs/充放电终端UI效果稿.html）：
    - 暗色三档：画布 #050507 / 卡片 #1B1A19 / 次级面 #242322
      （原两档只差 4% 亮度，10 寸屏上卡片与背景糊在一起，故加一档表面）
    - 亮色三档：画布 #F2F1EE / 卡片 #FFFFFF / 次级面 #F7F5F2
      （翠绿在亮底上必须加深到 #00A576，原 #00D992 对比度不足）
    - 暖炭/暖灰边框（深度靠边框权重表达）
    - 切主题用 M.set_theme / M.next_theme：原地覆盖 M.c 的键值，
      调用方需在回调栈之外延迟重建 UI
    - 翠绿 #00D992 只做高信号强调
    - 数字用等宽，动画慢而克制
  hzfont 矢量字库不含「·」「°」等符号，单位一律用 ASCII（C / A / V / W），
  分隔用空格或斜杠。
]]

local M = {}

-- ==================== 屏幕 ====================
M.screen = { w = 1024, h = 600 }

-- ==================== 配色（0xRRGGBB） ====================
-- 两套色板；M.c 是"当前生效"的表，切主题时原地覆盖键值（不换表引用），
-- 因为各模块用 local C = T.c 捕获的是同一个表的引用。
local PALETTES = {
    dark = {
        bg        = 0x050507, -- 画布（Abyss Black）
        panel     = 0x1B1A19, -- 卡片表面（比画布亮一档，暖中性）
        panel2    = 0x242322, -- 次级面（卡内小卡 / 徽章 / 顶栏浮件）
        line      = 0x3D3A39, -- 暖炭边框
        line_dim  = 0x322E2C, -- 分割线
        green     = 0x00D992, -- 翠绿（高信号）
        mint      = 0x2FD6A1, -- 亮绿
        emerald   = 0x10B981,
        snow      = 0xF2F2F2, -- 主文字
        parchment = 0xB8B3B0, -- 次文字
        steel     = 0x8B949E, -- 弱文字
        info      = 0x4CB3D4, -- 放电蓝
        port_on   = 0x222E29, -- 端口选中底色（次级面叠 6% 翠绿）
        cell_bg   = 0x0C0C0C, -- 电池图外壳内部
        cell_tick = 0x050507, -- 电池刻度线
    },
    light = {
        bg        = 0xF2F1EE, -- 暖白画布（不用纯白，避免刺眼）
        panel     = 0xFFFFFF, -- 卡片纯白，浮在暖白画布上
        panel2    = 0xF7F5F2, -- 次级面
        line      = 0xDBD6D0, -- 暖灰边框
        line_dim  = 0xE8E4DE, -- 分割线
        green     = 0x00A576, -- 亮底上必须加深，原 #00D992 对比度不足
        mint      = 0x00895F,
        emerald   = 0x0B8F63,
        snow      = 0x1B1A19, -- 暖炭黑（不是纯黑）
        parchment = 0x4E4A46,
        steel     = 0x7D7873, -- 亮底上"钢蓝"偏冷，换暖灰
        info      = 0x1E7FA8,
        port_on   = 0xE6F6F1, -- 端口选中：白卡叠 10% 翠绿（原来是深墨绿，亮色下像黑块）
        cell_bg   = 0xFFFFFF, -- 电池图外壳内部：白壳
        cell_tick = 0xE7EFE9, -- 电池刻度线：浅灰绿
    },
}

M.c = {}
local function apply(name)
    local p = PALETTES[name] or PALETTES.dark
    for k, v in pairs(p) do M.c[k] = v end
    M.theme = PALETTES[name] and name or "dark"
    return M.theme
end
apply("dark")

--[[切换主题：返回实际生效的主题名。只改色板，不动布局；
    UI 需要调用方延迟重建（在点击回调栈之外销毁旧控件）]]
function M.set_theme(name) return apply(name or "dark") end

-- 在暗 / 亮之间轮换，返回新主题名
function M.next_theme() return apply(M.theme == "dark" and "light" or "dark") end

-- ==================== 字号 ====================
-- 硬约束：最小 16 号（hzfont 中文下限，低于 16 会糊/裁），英文数字同此下限
M.f = {
    huge = 64, -- 电量百分比数字
    big  = 40, -- 功率数字
    val  = 26, -- 主口电流
    body = 22, -- 时钟 / 健康环 / 功率副
    text = 18, -- 标题 / 端口名 / foot
    sub  = 16, -- chip / 次级文字
    mini = 16, -- 极弱标签（下限 16）
}

-- 界面用到的字号一次载齐（与 app_main.font_load 一致）
M.font_sizes = { 16, 18, 22, 26, 40, 64 }

-- ==================== 布局（与效果稿 1024x600 逐像素一致） ====================
-- 外边距：左右 22 / 上 16 / 下 15，模块间距 12
M.l = {
    header  = { x = 22,  y = 16,  w = 980, h = 46  },
    battery = { x = 22,  y = 74,  w = 336, h = 461 },
    power   = { x = 370, y = 74,  w = 632, h = 226 },
    ports   = { x = 370, y = 312, w = 632, h = 223 },
    footer  = { x = 22,  y = 547, w = 980, h = 38  },
}

-- ==================== 节拍 ====================
M.perf = {
    frame_ms = 30,  -- 主循环 30fps（曲线 / 气泡动画）
    text_ms  = 200, -- 文字数据刷新 5Hz
    clock_ms = 1000,-- 时钟 1Hz
}

-- ==================== 对齐 ====================
M.LB = airui.TEXT_ALIGN_LEFT
M.RT = airui.TEXT_ALIGN_RIGHT
M.CT = airui.TEXT_ALIGN_CENTER

-- ==================== 封装 ====================
--[[标签：hzfont 无垂直居中，文字贴盒顶；行高 = 字号 + 3，
  声明 h 自动夹到行高之上，杜绝文字探出裁切]]
function M.label(parent, x, y, w, h, text, size, color, align)
    local lh = size + 3
    if not h or h < lh then h = lh end
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size, color = color,
        align = align or M.LB,
    })
end

--[[垂直居中的标签：在给定盒内让文字视觉居中（行高 = 字号 + 3）]]
function M.text_mid(parent, x, y, w, h, text, size, color, align)
    local lh = size + 3
    local ty = y + math.floor((h - lh) / 2)
    return M.label(parent, x, ty, w, lh, text, size, color, align)
end

--[[实心（圆角）容器：scrollable=false 从源头关闭滚动条]]
function M.box(parent, x, y, w, h, color, radius, bw, bc)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color, color_opacity = 255,
        radius = radius or 8,
        border_width = bw or 0, border_color = bc or 0,
        scrollable = false,
    })
end

--[[卡片：碳表面，默认无描边（内容区 = 外框）；
  需要描边时显式传 bw，且内部子控件按 w-2bw 摆]]
function M.card(parent, x, y, w, h, bw, bc)
    return M.box(parent, x, y, w, h, M.c.panel, 8, bw or 0, bc or M.c.line)
end

--[[按钮：style 见 airui.button（bg_color / bg_opa / text_color / radius /
   border_width / border_color / pressed_bg_color / pressed_text_color）]]
function M.button(parent, x, y, w, h, text, size, style, cb)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size, style = style, on_click = cb,
    })
end

--[[图形：line/circle/ellipse/rect/arc 多图元，坐标相对组件左上角；
  items 必须是连续数组（1..n 无空洞）。旧固件缺组件时返回 nil]]
function M.shape(parent, x, y, w, h, items)
    local ok, obj = pcall(function()
        return airui.shape({
            parent = parent, x = x, y = y, w = w, h = h, items = items,
        })
    end)
    if ok and obj then return obj end
    return nil
end

--[[透明热区：color_opacity=0 的 container + 闭包开关，命中不依赖固件显隐]]
function M.hot(parent, x, y, w, h, cb)
    local enabled = true
    local hit = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = 0xFFFFFF, color_opacity = 0,
        radius = 0, border_width = 0, scrollable = false,
        on_click = function()
            if enabled and cb then cb() end
        end,
    })
    local handle = { obj = hit }
    function handle.set_enabled(v)
        enabled = v and true or false
    end
    return handle
end

--[[事件回调里若需销毁控件，必须经 defer 延迟到本帧渲染之后]]
function M.defer(fn)
    sys.taskInit(fn)
end

return M
