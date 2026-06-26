--[[
@module  airui_hzfont
@summary HzFont矢量字体演示
@version 1.0.0
@date    2026.06.22
@author  江访
@usage
本文件在800×480横屏上演示HzFont内置矢量字体的各项特性：
1、全字号无级缩放（12-255号字体）
2、CJK汉字覆盖与多文种混排
3、智能抗锯齿与外部字库支持

本demo使用lcd_drv.lua中加载的内置hzfont（默认路径为/MiSans_gb2312.ttf）
]]

-- ============================================================================
-- 常量定义
-- ============================================================================

local SCREEN_W = 800
local SCREEN_H = 480

-- 颜色定义
local COLOR_TITLE_BG = 0x1565C0
local COLOR_TITLE_TEXT = 0xFFFFFF
local COLOR_CONTENT_BG = 0xF0F0F0
local COLOR_CARD_BG = 0xFFFFFF
local COLOR_SECTION_BLUE = 0x1565C0
local COLOR_SECTION_RED = 0xC62828
local COLOR_SECTION_GREEN = 0x00695C
local COLOR_BODY_TEXT = 0x37474F

-- ============================================================================
-- 入口函数
-- ============================================================================

local function ui_main()
    ---------------------------------------------------------------------------
    -- 主容器
    ---------------------------------------------------------------------------
    local main_container = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = COLOR_CONTENT_BG,
    })

    ---------------------------------------------------------------------------
    -- 标题栏
    ---------------------------------------------------------------------------
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 48,
        color = COLOR_TITLE_BG,
    })
    airui.label({
        parent = title_bar,
        text = "HzFont 矢量字体演示",
        x = 0,
        y = 8,
        w = SCREEN_W,
        h = 32,
        font_size = 22,
        color = COLOR_TITLE_TEXT,
        align = airui.TEXT_ALIGN_CENTER,
    })

    ---------------------------------------------------------------------------
    -- 卡片1：全字号无级缩放（y=56, h=190）
    ---------------------------------------------------------------------------
    local card1 = airui.container({
        parent = main_container,
        x = 10,
        y = 56,
        w = 780,
        h = 190,
        color = COLOR_CARD_BG,
        radius = 6,
    })
    airui.label({
        parent = card1,
        text = "全字号无级缩放 · 支持12-255号字体",
        x = 16,
        y = 10,
        w = 748,
        h = 24,
        font_size = 15,
        color = COLOR_SECTION_BLUE,
    })
    -- 大字号展示
    airui.label({
        parent = card1,
        text = "字号36：HzFont矢量字体演示",
        x = 16,
        y = 40,
        w = 368,
        h = 50,
        font_size = 36,
        color = 0xE63946,
    })
    airui.label({
        parent = card1,
        text = "字号36：HzFont Vector Font",
        x = 396,
        y = 40,
        w = 368,
        h = 50,
        font_size = 36,
        color = 0x2A9D8F,
    })
    -- 中字号展示
    airui.label({
        parent = card1,
        text = "字号24：中文字体无级缩放  /  English Text Scaling",
        x = 16,
        y = 96,
        w = 748,
        h = 40,
        font_size = 24,
        color = 0x264653,
    })
    -- 小字号展示
    airui.label({
        parent = card1,
        text = "字号14：小字号清晰显示，适合密集文本排版和数据显示场景",
        x = 16,
        y = 140,
        w = 748,
        h = 22,
        font_size = 14,
        color = COLOR_BODY_TEXT,
    })
    airui.label({
        parent = card1,
        text = "字号18：中号字体通用显示，兼顾清晰度与信息密度  |  24号标题醒目突出",
        x = 16,
        y = 164,
        w = 748,
        h = 22,
        font_size = 18,
        color = 0x6C757D,
    })

    ---------------------------------------------------------------------------
    -- 卡片2：CJK覆盖与多文种混排（y=252, h=96）
    ---------------------------------------------------------------------------
    local card2 = airui.container({
        parent = main_container,
        x = 10,
        y = 252,
        w = 780,
        h = 96,
        color = COLOR_CARD_BG,
        radius = 6,
    })
    airui.label({
        parent = card2,
        text = "CJK汉字覆盖 · 多文种混排",
        x = 16,
        y = 10,
        w = 748,
        h = 24,
        font_size = 15,
        color = COLOR_SECTION_RED,
    })
    airui.label({
        parent = card2,
        text = "繁簡共存：龍鳳飛舞 为学日增  |  合宙LuatOS物联网操作系统  |  龘靐齉齾爨癵驫麣",
        x = 16,
        y = 36,
        w = 748,
        h = 24,
        font_size = 14,
        color = COLOR_BODY_TEXT,
    })
    airui.label({
        parent = card2,
        text = "English  Ελληνικά  Русский  日本語  한글  |  ÀÁÂÃÄÅ  ÇÈÉÊË  ÌÍÎÏ  ÐÑÒÓÔÕÖ",
        x = 16,
        y = 64,
        w = 748,
        h = 24,
        font_size = 16,
        color = COLOR_BODY_TEXT,
    })

    ---------------------------------------------------------------------------
    -- 卡片3：特性总结（y=354, h=80）
    ---------------------------------------------------------------------------
    local card3 = airui.container({
        parent = main_container,
        x = 10,
        y = 354,
        w = 780,
        h = 80,
        color = COLOR_CARD_BG,
        radius = 6,
    })
    airui.label({
        parent = card3,
        text = "HzFont 矢量字体特性总览",
        x = 16,
        y = 8,
        w = 748,
        h = 20,
        font_size = 14,
        color = COLOR_SECTION_GREEN,
    })
    airui.label({
        parent = card3,
        text = "• 支持外部字库加载，可使用自定义TTF字体  |  • 抗锯齿等级可调（1-3级）  |  • 内置GB2312字库即开即用",
        x = 16,
        y = 32,
        w = 748,
        h = 20,
        font_size = 14,
        color = COLOR_BODY_TEXT,
    })
    airui.label({
        parent = card3,
        text = "• 缓存字数2048，常用场景无需反复加载  |  • 全系列芯片适用  |  • 12-255字号无级缩放",
        x = 16,
        y = 54,
        w = 748,
        h = 20,
        font_size = 14,
        color = COLOR_BODY_TEXT,
    })

    ---------------------------------------------------------------------------
    -- 底部状态栏
    ---------------------------------------------------------------------------
    local bottom_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 456,
        w = SCREEN_W,
        h = 24,
        color = 0x455A64,
    })
    airui.label({
        parent = bottom_bar,
        text = "HzFont矢量字体  v1.0  |  内置字库演示",
        x = 10,
        y = 4,
        w = SCREEN_W - 20,
        h = 18,
        font_size = 11,
        color = 0xFFFFFF,
    })
end

sys.taskInit(ui_main)
