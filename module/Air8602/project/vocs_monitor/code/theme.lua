--[[
@module  theme
@summary 界面配色主题（深色 / 浅色），对应设计稿 CSS 变量
@version 1.0.0
@date    2026.10.10
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
        bg            = 0x06090D,   -- 屏幕底色
        bg_grid       = 0x000E11,   -- 背景网格线
        topbar        = 0x0F1822,   -- 顶栏
        navbar        = 0x070B10,   -- 左侧导航
        statusbar     = 0x070B10,   -- 底栏
        panel         = 0x0C141C,   -- 面板底色
        panel_head    = 0x0E1620,   -- 面板标题区
        ring          = 0x0B292C,   -- 面板/顶栏描边
        accent_soft   = 0x0F2A26,   -- 强调色弱底
        cyan          = 0x00E5C0,
        blue          = 0x2EA8FF,
        amber         = 0xFFB020,
        text          = 0xD6E6EE,
        text_bright   = 0xEAFAFF,
        text_soft     = 0x9DBCCC,
        text_dim      = 0x5D7D8F,
        text_faint    = 0x44616F,
        text_row      = 0xB9D6E2,
        nav_item      = 0x3F5F70,
        nav_active_bg = 0x0A1F1D,
        head_text     = 0x4F6C7C,
        chip_text     = 0x8FB4C6,
        chip_bg       = 0x0A1A18,
        bar_bg        = 0x191D20,
        toggle_off    = 0x1A1E22,
        toggle_knob   = 0x5D7D8F,
        axis          = 0x094240,
        accent_line   = 0x077266,   -- 面板右上角装饰角标
    },
    light = {
        bg            = 0xEEF3F7,
        bg_grid       = 0xE3ECEF,
        topbar        = 0xFFFFFF,
        navbar        = 0xE9F0F5,
        statusbar     = 0xEEF4F8,
        panel         = 0xFBFDFE,
        panel_head    = 0xFFFFFF,
        ring          = 0xC7E6E3,
        accent_soft   = 0xCFEAE5,
        cyan          = 0x00A88E,
        blue          = 0x1D8FE0,
        amber         = 0xD98A00,
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
        chip_bg       = 0xEAF5F2,
        bar_bg        = 0xDFE6EA,
        toggle_off    = 0xF0F0F0,
        toggle_knob   = 0xA8BCC8,
        axis          = 0xA3D5D2,
        accent_line   = 0x7DD2C6,   -- 面板右上角装饰角标
    },
}

-- 默认主题由 config.theme 决定（"dark" / "light"），非法值回退到 "light"
theme.name = theme.palettes[config.theme] and config.theme or "light"

function theme.get()
    return theme.palettes[theme.name] or theme.palettes.light
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
