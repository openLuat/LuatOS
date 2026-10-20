--[[
@module  airui_custom_hzfont
@summary 自定义TTF矢量字体全貌展示页面
@version 1.0.0
@date    2026.10.12
@author  江访
@usage
本文件为自定义TTF矢量字体全貌展示页面，分5个功能区域展示：
1、多文种混排：中文+拉丁+希腊+西里尔+日文假名
2、汉字能力：繁简对比与复杂字形
3、符号与数字：制表符+全角+罗马数字
4、注音符号与假名：注音+平假名+片假名
5、拉丁扩展-A：变音字符

使用说明：
1、需自行准备自定义TTF字体文件（如NotoSansSC_subset.ttf），烧录到设备文件系统
2、在lcd_drv.lua的airui.font_load中设置path参数指向TTF文件：
   airui.font_load({
       type = "hzfont",
       path = "/NotoSansSC_subset.ttf",  -- 替换为实际TTF路径
       size = 20,
       cache_size = 1024,
       antialias = 1,
   })

注意：本demo需要用到外部TTF字体文件，若不配置则回退显示内置hzfont效果
]]

local airui_custom_hzfont = {}

-- 页面UI元素
local main_container = nil

-- 基础颜色
local COLOR_TITLE_BG = 0x1565C0
local COLOR_TITLE_TEXT = 0xFFFFFF
local COLOR_CONTENT_BG = 0xF0F0F0
local COLOR_CARD_BG = 0xFFFFFF
local COLOR_BODY_TEXT = 0x37474F

-- 各区域强调色
local COLOR_MULTISCRIPT = 0xC62828
local COLOR_CJK = 0x00695C
local COLOR_SYMBOL = 0x6A1B9A
local COLOR_ZHUYIN = 0xE65100
local COLOR_LATIN = 0x283593

-- 创建UI
function airui_custom_hzfont.create_ui()
    -- 全屏主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 1024,
        h = 600,
        color = COLOR_CONTENT_BG,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 1024,
        h = 60,
        color = COLOR_TITLE_BG,
    })
    airui.label({
        parent = title_bar,
        text = "自定义TTF矢量字体",
        x = 20,
        y = 15,
        w = 300,
        h = 30,
        font_size = 20,
        color = COLOR_TITLE_TEXT,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 900,
        y = 15,
        w = 100,
        h = 35,
        text = "返回",
        size = 16,
        on_click = function()
            go_back()
        end
    })

    ---------------------------------------------------------------------------
    -- 卡片1：多文种混排
    ---------------------------------------------------------------------------
    local card1 = airui.container({
        parent = main_container,
        x = 20,
        y = 80,
        w = 480,
        h = 150,
        color = COLOR_CARD_BG,
        radius = 8,
    })
    airui.label({
        parent = card1,
        text = "多文种和谐混排",
        x = 12,
        y = 6,
        w = 450,
        h = 18,
        font_size = 12,
        color = COLOR_MULTISCRIPT,
    })
    airui.label({
        parent = card1,
        text = "Noto 中文  English  Ελληνικά",
        x = 12,
        y = 40,
        w = 450,
        h = 30,
        font_size = 16,
        color = COLOR_BODY_TEXT,
    })
    airui.label({
        parent = card1,
        text = "Русский  日本語  한국어  拉丁文",
        x = 12,
        y = 85,
        w = 450,
        h = 30,
        font_size = 16,
        color = COLOR_BODY_TEXT,
    })

    ---------------------------------------------------------------------------
    -- 卡片2：汉字覆盖
    ---------------------------------------------------------------------------
    local card2 = airui.container({
        parent = main_container,
        x = 522,
        y = 80,
        w = 480,
        h = 150,
        color = COLOR_CARD_BG,
        radius = 8,
    })
    airui.label({
        parent = card2,
        text = "CJK汉字覆盖 · 繁简共存",
        x = 12,
        y = 6,
        w = 450,
        h = 18,
        font_size = 12,
        color = COLOR_CJK,
    })
    airui.label({
        parent = card2,
        text = "字号15：合宙LuatOS物联网 龙飛鳳舞",
        x = 12,
        y = 40,
        w = 450,
        h = 30,
        font_size = 15,
        color = COLOR_BODY_TEXT,
    })
    airui.label({
        parent = card2,
        text = "字号13：龘靐齉齾爨癵驫麣 為學日增",
        x = 12,
        y = 85,
        w = 450,
        h = 30,
        font_size = 13,
        color = COLOR_BODY_TEXT,
    })

    ---------------------------------------------------------------------------
    -- 卡片3：符号与数字
    ---------------------------------------------------------------------------
    local card3 = airui.container({
        parent = main_container,
        x = 20,
        y = 250,
        w = 480,
        h = 150,
        color = COLOR_CARD_BG,
        radius = 8,
    })
    airui.label({
        parent = card3,
        text = "符号 · 全角字符 · 数字形式",
        x = 12,
        y = 6,
        w = 450,
        h = 18,
        font_size = 12,
        color = COLOR_SYMBOL,
    })
    airui.label({
        parent = card3,
        text = "─│┌┐└┘═║╔╗╚╝■□▲△●○",
        x = 12,
        y = 40,
        w = 450,
        h = 30,
        font_size = 16,
        color = COLOR_BODY_TEXT,
    })
    airui.label({
        parent = card3,
        text = "１２３４５ ⅠⅡⅢⅣⅤⅥ ＡＢＣＤ",
        x = 12,
        y = 85,
        w = 450,
        h = 30,
        font_size = 16,
        color = COLOR_BODY_TEXT,
    })

    ---------------------------------------------------------------------------
    -- 卡片4：注音与假名
    ---------------------------------------------------------------------------
    local card4 = airui.container({
        parent = main_container,
        x = 522,
        y = 250,
        w = 480,
        h = 150,
        color = COLOR_CARD_BG,
        radius = 8,
    })
    airui.label({
        parent = card4,
        text = "注音符号 · 日文假名",
        x = 12,
        y = 6,
        w = 450,
        h = 18,
        font_size = 12,
        color = COLOR_ZHUYIN,
    })
    airui.label({
        parent = card4,
        text = "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏ  |  あいうえお",
        x = 12,
        y = 40,
        w = 450,
        h = 30,
        font_size = 15,
        color = COLOR_BODY_TEXT,
    })
    airui.label({
        parent = card4,
        text = "かきくけこ  |  アイウエオ カキクケコ",
        x = 12,
        y = 85,
        w = 450,
        h = 30,
        font_size = 15,
        color = COLOR_BODY_TEXT,
    })

    ---------------------------------------------------------------------------
    -- 卡片5：拉丁扩展-A
    ---------------------------------------------------------------------------
    local card5 = airui.container({
        parent = main_container,
        x = 20,
        y = 420,
        w = 982,
        h = 110,
        color = COLOR_CARD_BG,
        radius = 8,
    })
    airui.label({
        parent = card5,
        text = "拉丁扩展-A  ·  128个变音字符",
        x = 12,
        y = 6,
        w = 450,
        h = 16,
        font_size = 11,
        color = COLOR_LATIN,
    })
    airui.label({
        parent = card5,
        text = "ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ",
        x = 12,
        y = 40,
        w = 950,
        h = 30,
        font_size = 16,
        color = COLOR_BODY_TEXT,
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 需在lcd_drv.lua的airui.font_load中配置TTF路径，未配置时回退内置hzfont效果",
        x = 20,
        y = 560,
        w = 800,
        h = 25,
        font_size = 14,
        color = 0x455A64,
    })
end

-- 初始化页面
function airui_custom_hzfont.init(params)
    airui_custom_hzfont.create_ui()
end

-- 清理页面
function airui_custom_hzfont.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return airui_custom_hzfont
