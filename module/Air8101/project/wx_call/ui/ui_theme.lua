--[[
@module  ui_theme
@summary 亮橙色科技感配色表（0xRRGGBB）
@version 1.0.0
@date    2026.10.21
]]

local T = {
    -- 主色：亮橙
    ORANGE      = 0xFF7A00,
    ORANGE_LT   = 0xFFA22E,
    ORANGE_PALE = 0x4A2C10,   -- 橙色半透明（暗底上的胶囊/描边）
    DARK_TEXT   = 0x1A1006,   -- 橙底上的深色文字

    -- 背景层次
    BG          = 0x0E1013,
    BAR         = 0x14161B,
    CARD        = 0x191D23,
    CARD_LT     = 0x22272F,
    LINE        = 0x2A2F38,

    -- 文字
    TEXT        = 0xFFFFFF,
    TEXT_SUB    = 0x9AA1AC,
    TEXT_DIM    = 0x646B76,

    -- 状态
    GREEN       = 0x35D07F,
    RED         = 0xE23A2E,
    YELLOW      = 0xFFC53D,
}

return T
