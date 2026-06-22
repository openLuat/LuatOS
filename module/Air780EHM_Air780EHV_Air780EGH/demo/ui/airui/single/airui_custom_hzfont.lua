--[[
@module  airui_custom_hzfont
@summary 自定义TTF矢量字体全貌展示页面
@version 1.0.0
@date    2026.06.22
@author  江访
@usage
本文件为自定义TTF矢量字体全貌展示页面，在320×480竖屏上分5个功能区域展示：
1、多文种混排：中文+拉丁+希腊+西里尔+日文假名
2、汉字能力：繁简对比与复杂字形
3、符号与数字：制表符+全角+罗马数字
4、注音符号与假名：37个注音+平假名+片假名
5、拉丁扩展-A：128个变音字符

使用说明：
1、需自行准备自定义TTF字体文件（如NotoSansSC_subset.ttf）
2、在lcd_inner_drv.lua或lcd_custom_drv.lua的airui.font_load中设置path参数指向TTF文件：
   airui.font_load({
       type = "hzfont",
       path = "/NotoSansSC_subset.ttf",  -- 替换为实际TTF路径
       size = 20,
       cache_size = 1024,
       antialias = 1,
   })
3、将TTF字体文件烧录到设备文件系统

注意：本demo需要用到外部TTF字体文件，若不配置则回退显示内置hzfont效果
]]

-- ============================================================================
-- 常量定义
-- ============================================================================

local SCREEN_W = 320
local SCREEN_H = 480

-- 基础颜色
local COLOR_TITLE_BG = 0x1565C0
local COLOR_TITLE_TEXT = 0xFFFFFF
local COLOR_CONTENT_BG = 0xF0F0F0
local COLOR_CARD_BG = 0xFFFFFF
local COLOR_BODY_TEXT = 0x37474F
local COLOR_INFO_TEXT = 0xFFFFFF

-- 各区域强调色
local COLOR_MULTISCRIPT = 0xC62828
local COLOR_CJK = 0x00695C
local COLOR_SYMBOL = 0x6A1B9A
local COLOR_ZHUYIN = 0xE65100
local COLOR_LATIN = 0x283593

-- ============================================================================
-- 入口函数
-- ============================================================================

local function ui_main()
    ---------------------------------------------------------------------------
    -- 全屏主容器
    ---------------------------------------------------------------------------
    local main_container = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = COLOR_CONTENT_BG,
    })

    ---------------------------------------------------------------------------
    -- 标题栏（44px）
    ---------------------------------------------------------------------------
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 44,
        color = COLOR_TITLE_BG,
    })
    airui.label({
        parent = title_bar,
        text = "自定义TTF矢量字体",
        x = 0,
        y = 8,
        w = SCREEN_W,
        h = 28,
        font_size = 18,
        color = COLOR_TITLE_TEXT,
        align = airui.TEXT_ALIGN_CENTER,
    })

    ---------------------------------------------------------------------------
    -- 卡片1：多文种混排（y=50, h=82）
    ---------------------------------------------------------------------------
    local card1 = airui.container({
        parent = main_container,
        x = 8,
        y = 50,
        w = 304,
        h = 82,
        color = COLOR_CARD_BG,
        radius = 5,
    })
    airui.label({
        parent = card1,
        text = "多文种和谐混排",
        x = 12,
        y = 6,
        w = 280,
        h = 18,
        font_size = 12,
        color = COLOR_MULTISCRIPT,
    })
    airui.label({
        parent = card1,
        text = "Noto 中文  English  Ελληνικά",
        x = 12,
        y = 28,
        w = 280,
        h = 22,
        font_size = 16,
        color = COLOR_BODY_TEXT,
    })
    airui.label({
        parent = card1,
        text = "Русский  日本語  한국어  拉丁文",
        x = 12,
        y = 52,
        w = 280,
        h = 22,
        font_size = 16,
        color = COLOR_BODY_TEXT,
    })

    ---------------------------------------------------------------------------
    -- 卡片2：汉字覆盖（y=138, h=82）
    ---------------------------------------------------------------------------
    local card2 = airui.container({
        parent = main_container,
        x = 8,
        y = 138,
        w = 304,
        h = 82,
        color = COLOR_CARD_BG,
        radius = 5,
    })
    airui.label({
        parent = card2,
        text = "CJK汉字覆盖 · 繁简共存",
        x = 12,
        y = 6,
        w = 280,
        h = 18,
        font_size = 12,
        color = COLOR_CJK,
    })
    airui.label({
        parent = card2,
        text = "字号15：合宙LuatOS物联网 龙飛鳳舞",
        x = 12,
        y = 28,
        w = 280,
        h = 22,
        font_size = 15,
        color = COLOR_BODY_TEXT,
    })
    airui.label({
        parent = card2,
        text = "字号13：龘靐齉齾爨癵驫麣 為學日增",
        x = 12,
        y = 52,
        w = 280,
        h = 22,
        font_size = 13,
        color = COLOR_BODY_TEXT,
    })

    ---------------------------------------------------------------------------
    -- 卡片3：符号与数字（y=226, h=82）
    ---------------------------------------------------------------------------
    local card3 = airui.container({
        parent = main_container,
        x = 8,
        y = 226,
        w = 304,
        h = 82,
        color = COLOR_CARD_BG,
        radius = 5,
    })
    airui.label({
        parent = card3,
        text = "符号 · 全角字符 · 数字形式",
        x = 12,
        y = 6,
        w = 280,
        h = 18,
        font_size = 12,
        color = COLOR_SYMBOL,
    })
    airui.label({
        parent = card3,
        text = "─│┌┐└┘═║╔╗╚╝■□▲△●○",
        x = 12,
        y = 28,
        w = 280,
        h = 22,
        font_size = 16,
        color = COLOR_BODY_TEXT,
    })
    airui.label({
        parent = card3,
        text = "１２３４５ ⅠⅡⅢⅣⅤⅥ ＡＢＣＤ",
        x = 12,
        y = 52,
        w = 280,
        h = 22,
        font_size = 16,
        color = COLOR_BODY_TEXT,
    })

    ---------------------------------------------------------------------------
    -- 卡片4：注音与假名（y=314, h=82）
    ---------------------------------------------------------------------------
    local card4 = airui.container({
        parent = main_container,
        x = 8,
        y = 314,
        w = 304,
        h = 82,
        color = COLOR_CARD_BG,
        radius = 5,
    })
    airui.label({
        parent = card4,
        text = "注音符号 · 日文假名",
        x = 12,
        y = 6,
        w = 280,
        h = 18,
        font_size = 12,
        color = COLOR_ZHUYIN,
    })
    airui.label({
        parent = card4,
        text = "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏ  |  あいうえお",
        x = 12,
        y = 28,
        w = 280,
        h = 22,
        font_size = 15,
        color = COLOR_BODY_TEXT,
    })
    airui.label({
        parent = card4,
        text = "かきくけこ  |  アイウエオ カキクケコ",
        x = 12,
        y = 52,
        w = 280,
        h = 22,
        font_size = 15,
        color = COLOR_BODY_TEXT,
    })

    ---------------------------------------------------------------------------
    -- 卡片5：拉丁扩展-A（y=402, h=58）
    ---------------------------------------------------------------------------
    local card5 = airui.container({
        parent = main_container,
        x = 8,
        y = 402,
        w = 304,
        h = 58,
        color = COLOR_CARD_BG,
        radius = 5,
    })
    airui.label({
        parent = card5,
        text = "拉丁扩展-A  ·  128个变音字符",
        x = 12,
        y = 6,
        w = 280,
        h = 16,
        font_size = 11,
        color = COLOR_LATIN,
    })
    airui.label({
        parent = card5,
        text = "ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ",
        x = 12,
        y = 26,
        w = 280,
        h = 24,
        font_size = 16,
        color = COLOR_BODY_TEXT,
    })

    ---------------------------------------------------------------------------
    -- 底部状态栏
    ---------------------------------------------------------------------------
    local bottom_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 462,
        w = SCREEN_W,
        h = 18,
        color = 0x455A64,
    })
    airui.label({
        parent = bottom_bar,
        text = "自定义TTF字体 · 外部字库演示",
        x = 8,
        y = 2,
        w = 304,
        h = 14,
        font_size = 10,
        color = COLOR_INFO_TEXT,
    })
end

sys.taskInit(ui_main)
