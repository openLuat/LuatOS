--[[
@module  theme
@summary 界面配色主题（深色 / 浅色），对应设计稿 CSS 变量
@version 1.0.0
@date    2026.10.12
@usage
theme.get()          -- 取当前主题色表
theme.set("light")   -- 切换主题（仅改表，不发消息；由调用方决定何时重建 UI）
theme.name           -- 当前主题名
]]

local config = require "config"

local theme = {}

-- 键名与设计稿 CSS 变量一一对应（十六进制 RGB，供 airui 使用）
theme.palettes = {
    dark = {
        bg            = 0x05080E,   -- 屏幕底色（--bg）—— 压暗，拉开与卡片的层次
        bg_grid       = 0x0B1420,   -- 背景网格线
        topbar        = 0x0A1220,   -- 顶栏
        navbar        = 0x080E18,   -- 左侧栏
        statusbar     = 0x070B10,   -- 侧栏底部区
        panel         = 0x0F1926,   -- 卡片/面板底色（比 bg 明显亮一档）
        panel_head    = 0x121D2C,   -- 卡片标题区
        ring          = 0x223044,   -- 面板/卡片描边（可见轮廓）
        accent_soft   = 0x0D2E3E,   -- 强调弱底
        cyan          = 0x22D3EE,   -- 主强调（--cyan）
        blue          = 0x3B82F6,   -- 次强调（--blue）
        amber         = 0xFF9D3D,   -- 警告（--amber）
        red           = 0xFF5B6E,   -- 报警（--red）
        green         = 0x2EE6A8,   -- 正常（--green）
        violet        = 0x8B7CFF,   -- 备用（--violet）
        gold          = 0xFFD166,   -- 备用（--gold）
        text          = 0xE9EFF8,   -- 主文字（--txt）
        text_bright   = 0xFFFFFF,   -- 数值大字
        text_soft     = 0x9AA9BE,   -- 次文字（--sub）
        text_dim      = 0x6B7C93,   -- 弱文字（--dim）
        text_faint    = 0x54647A,   -- 最弱文字
        text_row      = 0xAFC3D6,   -- 行文字
        nav_item      = 0x8698AE,   -- 导航未激活
        nav_active_bg = 0x0D2E3E,   -- 导航激活底
        head_text     = 0x6B7C93,   -- 表头文字
        chip_text     = 0xB6C6D8,   -- 芯片文字
        chip_bg       = 0x1A2534,   -- 芯片/小容器底（比 panel 再亮一档）
        bar_bg        = 0x222E3E,   -- 进度条底
        toggle_off    = 0x232F3E,   -- 开关关
        toggle_knob   = 0x9AA9BE,   -- 开关滑块
        axis          = 0x33465C,   -- 坐标轴
        accent_line   = 0x11616E,   -- 卡片竖条/装饰
    },
    light = {
        bg            = 0xEEF3F7,
        bg_grid       = 0xE3ECEF,
        topbar        = 0xFFFFFF,
        navbar        = 0xE9F0F5,
        statusbar     = 0xEEF4F8,
        panel         = 0xFBFDFE,
        panel_head    = 0xFFFFFF,
        ring          = 0xC9D6E2,
        accent_soft   = 0xD6F1F8,
        cyan          = 0x0E9BB8,
        blue          = 0x2E6FD6,
        amber         = 0xD9821F,
        red           = 0xE04656,
        green         = 0x14B583,
        violet        = 0x6E5FE0,
        gold          = 0xD9A22E,
        text          = 0x2A3F4D,
        text_bright   = 0x0F2430,
        text_soft     = 0x4A6B7D,
        text_dim      = 0x7A95A5,
        text_faint    = 0x93AAB8,
        text_row      = 0x3D5C6D,
        nav_item      = 0x7A95A5,
        nav_active_bg = 0xDDF1EC,
        head_text     = 0x7A95A5,
        chip_text     = 0x4A6B7D,
        chip_bg       = 0xEAF2F8,
        bar_bg        = 0xDFE6EA,
        toggle_off    = 0xDCE3E8,
        toggle_knob   = 0xA8BCC8,
        axis          = 0xA3C4D5,
        accent_line   = 0x7DD2C6,
    },
}

-- 默认主题由 config.theme 决定（"dark" / "light"），非法值回退到 "dark"
theme.name = theme.palettes[config.theme] and config.theme or "dark"

function theme.get()
    return theme.palettes[theme.name] or theme.palettes.dark
end

function theme.set(name)
    if theme.palettes[name] then
        theme.name = name
    end
end

function theme.is_dark()
    return theme.name ~= "light"
end

return theme
