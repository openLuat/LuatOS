--[[
@module  airui_custom_hzfont
@summary Noto Sans SC Subset 矢量字体全貌展示页面
@version 1.0.0
@date    2026.06.06
@author  江访
@usage
本文件为Noto Sans SC Subset矢量字体全貌展示页面，核心业务逻辑为：

1、在800×480横屏上分7个功能区域展示字体特性：
   - 多文种和谐混排：中文+拉丁+希腊+西里尔+日文假名同屏展示
   - CJK统一汉字：展示6762汉字的完整覆盖能力，含繁简字形与复杂结构
   - 制表符与几何图形：76个制表符+几何形状的显示效果
   - 全角字符与数字形式：FF01-FF5E全角英数+罗马数字Ⅰ-Ⅻ
   - 注音符号与假名：37个注音符号+平假名+片假名
   - 拉丁扩展-A：欧洲语言变音字符（ÀÁÂÃÄÅ等128个）
   - 字体度量与设计信息：unitsPerEm/ascender/descender等排版参数

2、所有内容通过airui.label组件渲染，使用airui.font_load加载外部TTF字体文件

3、在PC模拟器上运行本demo前，需确保lcd_drv.lua中PC分支已配置外部TTF路径
   本demo配套的字体文件为 NotoSansSC_subset.ttf，需置于脚本同目录下

更多说明参考本目录下的readme.md文件
]]

-- ============================================================================
-- 常量定义（UPPER_SNAKE_CASE）
-- ============================================================================

-- 屏幕尺寸
local SCREEN_W = 800
local SCREEN_H = 480

-- 标题栏参数
local TITLE_BAR_H = 48
local TITLE_BAR_COLOR = 0x1565C0
local TITLE_TEXT_COLOR = 0xFFFFFF

-- 内容区参数
local CONTENT_TOP = 52        -- 内容区起始Y（标题栏下方4px间距）
local CONTENT_BG_COLOR = 0xF0F0F0  -- 内容区浅灰背景
local CARD_BG_COLOR = 0xFFFFFF     -- 卡片白色背景
local CARD_RADIUS = 6              -- 卡片圆角半径
local CARD_PAD_X = 16              -- 卡片内部水平边距
local CARD_PAD_Y = 8               -- 卡片内部垂直边距

-- 各区域强调色（Material Design 800色系，与Noto现代设计风格匹配）
local COLOR_MULTISCRIPT = 0x1565C0  -- 深蓝：多文种区
local COLOR_CJK = 0xC62828          -- 暖红：CJK区
local COLOR_BOXDRAW = 0x00695C      -- 墨绿：制表符区
local COLOR_FULLWIDTH = 0x6A1B9A    -- 紫色：全角区
local COLOR_ZHUYIN = 0xE65100       -- 橙色：注音区
local COLOR_LATIN = 0x283593        -- 靛蓝：拉丁区
local COLOR_INFO = 0x455A64         -- 蓝灰：信息区

-- 字体基本信息（用于页脚展示）
local FONT_SPEC_NAME = "Noto Sans SC Subset"
local FONT_SPEC_DESIGNER = "Google / Adobe"
local FONT_SPEC_WEIGHT = 400
local FONT_SPEC_UNITS = 1000
local FONT_SPEC_ASCENDER = 880
local FONT_SPEC_DESCENDER = -120
local FONT_SPEC_GLYPHS = 8027
local FONT_SPEC_CJK_COUNT = 6762

-- ============================================================================
-- 内部函数：创建区域标题标签
-- ============================================================================
--[[
创建带背景色的区域标题标签，用于标识每个功能区域的主题

@param parent      父容器
@param x, y, w, h  标签位置与尺寸
@param text        标题文本
@param color       标题文字颜色（使用的区域强调色）
@param font_size   标题字号
@return 创建的label对象
]]
local function create_section_title(parent, x, y, w, h, text, color, font_size)
    return airui.label({
        parent = parent,
        text = text,
        x = x,
        y = y,
        w = w,
        h = h,
        font_size = font_size,
        color = color,
    })
end

-- ============================================================================
-- 内部函数：创建区域正文标签
-- ============================================================================
--[[
创建正文内容标签，使用深灰色文字，字号较大以突出字体本身

@param parent      父容器
@param x, y, w, h  标签位置与尺寸
@param text        正文文本
@param font_size   正文字号
@return 创建的label对象
]]
local function create_section_body(parent, x, y, w, h, text, font_size)
    return airui.label({
        parent = parent,
        text = text,
        x = x,
        y = y,
        w = w,
        h = h,
        font_size = font_size,
        color = 0x37474F,  -- 统一深灰色，让字体本身成为视觉焦点
    })
end

-- ============================================================================
-- 内部函数：创建圆角白色卡片容器
-- ============================================================================
--[[
创建带圆角的白色卡片容器，用于包裹每个功能区域

@param parent 父容器
@param x, y, w, h 卡片位置与尺寸
@return 创建的container对象
]]
local function create_card(parent, x, y, w, h)
    return airui.container({
        parent = parent,
        x = x,
        y = y,
        w = w,
        h = h,
        color = CARD_BG_COLOR,
        radius = CARD_RADIUS,
    })
end

-- ============================================================================
-- 入口函数：构建整个字体展示页面
-- ============================================================================
--[[
字体展示页面的UI入口函数

PC模拟器运行前确保：
1、lcd_drv.lua中PC分支使用 airui.font_load({path="./NotoSansSC_subset.ttf", ...})
2、NotoSansSC_subset.ttf字体文件与lua脚本在同一目录
]]
local function ui_main()
    ---------------------------------------------------------------------------
    -- 步骤1：创建全屏主容器
    ---------------------------------------------------------------------------
    local main_container = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = CONTENT_BG_COLOR,
    })

    ---------------------------------------------------------------------------
    -- 步骤2：标题栏（深蓝色，居中白色文字）
    ---------------------------------------------------------------------------
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = TITLE_BAR_H,
        color = TITLE_BAR_COLOR,
    })
    airui.label({
        parent = title_bar,
        text = FONT_SPEC_NAME .. "  —  矢量字体全貌展示",
        x = 0,
        y = 8,
        w = SCREEN_W,
        h = 32,
        font_size = 22,
        color = TITLE_TEXT_COLOR,
        align = airui.TEXT_ALIGN_CENTER,
    })

    ---------------------------------------------------------------------------
    -- 步骤3：区域1 — 多文种和谐混排（全宽，y=54, h=74）
    -- 各种文字在同一行中视觉和谐
    ---------------------------------------------------------------------------
    local card_multiscript = create_card(main_container, 8, 54, 784, 74)
    create_section_title(card_multiscript,
        12, 8, 760, 20,
        "多文种和谐混排", COLOR_MULTISCRIPT, 13)
    create_section_body(card_multiscript,
        12, 30, 760, 36,
        "Noto 中文 English Ελληνικά Русский 日本語", 23)

    ---------------------------------------------------------------------------
    -- 步骤4：区域2 — CJK统一汉字覆盖（全宽，y=132, h=80）
    -- 展示6762汉字的覆盖能力，含繁简对比和复杂字形
    ---------------------------------------------------------------------------
    local card_cjk = create_card(main_container, 8, 132, 784, 80)
    create_section_title(card_cjk,
        12, 8, 760, 20,
        "CJK统一汉字 · " .. tostring(FONT_SPEC_CJK_COUNT) .. "字完整覆盖  GB2312超集", COLOR_CJK, 13)
    -- 用小字号展示繁简对比和复杂字形，体现字体在不同字号下的清晰度
    create_section_body(card_cjk,
        12, 30, 760, 44,
        "字号14: 合宙LuatOS物联网操作系统开源项目  |  字号14: 龘靐齉齾爨癵驫麣 龍飛鳳舞 為學日增", 14)

    ---------------------------------------------------------------------------
    -- 步骤5：区域3 — 制表符与几何图形（左半，y=216, h=76）
    -- 76个制表符是Noto的特色覆盖，在嵌入式UI中用于绘制表格和边框
    ---------------------------------------------------------------------------
    local card_boxdraw = create_card(main_container, 8, 216, 388, 76)
    create_section_title(card_boxdraw,
        12, 8, 364, 20,
        "制表符 · 几何形状  Box Drawing (76字符)", COLOR_BOXDRAW, 13)
    create_section_body(card_boxdraw,
        12, 30, 364, 40,
        "─│┌┐└┘  ═║╔╗╚╝  ┌──┬──┐  ■□▲△●○◎◇◆", 18)

    ---------------------------------------------------------------------------
    -- 步骤6：区域4 — 全角字符与数字形式（右半，y=216, h=76）
    -- 226个全角字符 + 罗马数字Ⅰ-Ⅻ（新版新增）
    ---------------------------------------------------------------------------
    local card_fullwidth = create_card(main_container, 400, 216, 392, 76)
    create_section_title(card_fullwidth,
        12, 8, 368, 20,
        "全角字符 · 数字形式  Fullwidth + Roman", COLOR_FULLWIDTH, 13)
    create_section_body(card_fullwidth,
        12, 30, 368, 40,
        "ＡＢＣＬｕａＴＯＳ  １２３  ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ", 18)

    ---------------------------------------------------------------------------
    -- 步骤7：区域5 — 注音符号与假名（左半，y=296, h=76）
    -- 37个注音符号（新版新增）+ 平假名92 + 片假名96
    ---------------------------------------------------------------------------
    local card_zhuyin = create_card(main_container, 8, 296, 388, 76)
    create_section_title(card_zhuyin,
        12, 8, 364, 20,
        "注音符号 · 假名  Zhuyin + Kana (225字符)", COLOR_ZHUYIN, 13)
    create_section_body(card_zhuyin,
        12, 30, 364, 40,
        "ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏ  あいうえおかきくけこ  イウエオ", 18)

    ---------------------------------------------------------------------------
    -- 步骤8：区域6 — 拉丁扩展-A（右半，y=296, h=76）
    -- 128个拉丁扩展字符（新版从6个大幅扩展到128个），覆盖欧洲主要语言
    ---------------------------------------------------------------------------
    local card_latin = create_card(main_container, 400, 296, 392, 76)
    create_section_title(card_latin,
        12, 8, 368, 20,
        "拉丁扩展-A  128个变音字符 · 欧洲语言", COLOR_LATIN, 13)
    create_section_body(card_latin,
        12, 30, 368, 40,
        "ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞß  ĀāĂă", 18)

    ---------------------------------------------------------------------------
    -- 步骤9：区域7 — 字体度量与设计信息（全宽底部，y=376, h=68）
    -- 展示字体的排版参数和设计哲学
    ---------------------------------------------------------------------------
    local card_info = create_card(main_container, 8, 376, 784, 68)
    create_section_title(card_info,
        12, 8, 760, 18,
        "字体档案  ·  " .. FONT_SPEC_DESIGNER .. "联合设计", COLOR_INFO, 12)
    -- 分两行展示详细信息
    create_section_body(card_info,
        12, 28, 760, 18,
        "Weight " .. tostring(FONT_SPEC_WEIGHT) .. "  ·  UnitsPerEm " .. tostring(FONT_SPEC_UNITS)
        .. "  ·  Ascender " .. tostring(FONT_SPEC_ASCENDER) .. "  ·  Descender " .. tostring(FONT_SPEC_DESCENDER)
        .. "  ·  共" .. tostring(FONT_SPEC_GLYPHS) .. "字形", 12)
    create_section_body(card_info,
        12, 48, 760, 16,
        "设计理念：—让所有文字在同一页面和谐共处。覆盖范围远超嵌入式常见GB2312(6763字)", 11)
end

-- 启动UI任务
sys.taskInit(ui_main)
