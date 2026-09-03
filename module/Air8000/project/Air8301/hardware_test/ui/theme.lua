--[[
@module  theme
@summary UI 共享主题模块（Air8301 硬件测试）
@version 1.0
@date    2026.08.14
@author  江访
@usage
require "theme" 后通过 _G.T 访问颜色常量、标题栏、按钮等共享组件。
对齐工厂引擎 app_engine 的 iOS 风格 UI 视觉语言。
]]

local T = {}

-- ==================== 颜色常量（对齐 app_engine iOS 风格） ====================
T.COLOR_PRIMARY        = 0x007AFF   -- iOS 蓝（标题栏、主按钮、强调色）
T.COLOR_PRIMARY_DARK   = 0x0056B3   -- 深蓝（按钮按下态）
T.COLOR_ACCENT         = 0xFF9800   -- 橙色（指示器、菜单项）
T.COLOR_BG             = 0xF5F5F5   -- 浅灰背景
T.COLOR_CARD           = 0xFFFFFF   -- 白色卡片
T.COLOR_TEXT           = 0x333333   -- 深灰主文字
T.COLOR_TEXT_SECONDARY = 0x757575   -- 中灰副文字
T.COLOR_DIVIDER        = 0xE0E0E0   -- 分隔线、边框
T.COLOR_WHITE          = 0xFFFFFF   -- 白色（深色背景上文字）
T.COLOR_DANGER         = 0xE63946   -- 红色（危险操作、错误状态）
T.COLOR_GREEN          = 0x34C759   -- 绿色（成功、连接状态）
T.COLOR_ORANGE         = 0xFF9800   -- 橙色（警告、中等信号）

-- ==================== 布局常量（480×272 横屏紧凑模式） ====================
T.SCREEN_W        = 480
T.SCREEN_H        = 272
T.TITLEBAR_H      = 48         -- 标题栏高度
T.CONTENT_Y       = 48         -- 内容区起始 Y
T.CONTENT_H       = 224        -- 内容区高度 (272-48)
T.MARGIN          = 10         -- 卡片外边距
T.CARD_W          = 460        -- 卡片宽度 (480-2*10)
T.CARD_RADIUS     = 8          -- 卡片圆角
T.BTN_RADIUS      = 6          -- 按钮圆角
T.BACK_BTN_W      = 50         -- 返回按钮宽度

-- ==================== 字号常量 ====================
T.FONT_TITLE      = 18         -- 标题栏标题
T.FONT_BACK       = 16         -- 返回按钮
T.FONT_CARD_TITLE = 14         -- 卡片小标题
T.FONT_BODY       = 16         -- 正文
T.FONT_SMALL      = 14         -- 辅助小字

--[[
创建标题栏（蓝色背景 + 返回按钮 + 标题文字）
对齐 app_engine settings_titlebar.lua 风格

@param userdata parent   父容器
@param string   title    标题文字
@param function on_back  返回按钮点击回调
@return userdata header  标题栏容器
]]
function T.titlebar(parent, title, on_back)
    local header = airui.container({
        parent = parent,
        x = 0, y = 0, w = T.SCREEN_W, h = T.TITLEBAR_H,
        color = T.COLOR_PRIMARY,
    })

    -- 返回按钮（"<" 箭头，宽触控区域）
    local back = airui.container({
        parent = header,
        x = 0, y = 0, w = T.BACK_BTN_W + 10, h = T.TITLEBAR_H,
        on_click = on_back,
    })
    airui.label({
        parent = back,
        x = 0, y = 14, w = T.BACK_BTN_W, h = T.FONT_BACK + 4,
        text = "<",
        font_size = T.FONT_BACK + 4,
        color = T.COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 标题文字（水平+垂直居中）
    airui.label({
        parent = header,
        x = T.BACK_BTN_W, y = 15,
        w = T.SCREEN_W - 2 * T.BACK_BTN_W, h = T.FONT_TITLE,
        text = title,
        font_size = T.FONT_TITLE,
        color = T.COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER,
    })

    return header
end

--[[
创建信息卡片（白色背景 + 圆角 + 小标题 + 内容标签）

@param userdata parent       父容器
@param number   y            Y 坐标
@param number   h            卡片高度
@param string   title_text   小标题文字
@param string   content_text 内容初始文字
@return userdata card        卡片容器
@return userdata title_label 小标题 label
@return userdata content_label 内容 label
]]
function T.info_card(parent, y, h, title_text, content_text)
    local card = airui.container({
        parent = parent,
        x = T.MARGIN, y = y, w = T.CARD_W, h = h,
        color = T.COLOR_CARD, radius = T.CARD_RADIUS,
    })
    local title_label = airui.label({
        parent = card,
        x = 10, y = 4, w = T.CARD_W - 20, h = 20,
        text = title_text,
        font_size = T.FONT_CARD_TITLE,
        color = T.COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local content_label = airui.label({
        parent = card,
        x = 10, y = 26, w = T.CARD_W - 20, h = h - 30,
        text = content_text or "",
        font_size = T.FONT_BODY,
        color = T.COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT,
    })
    return card, title_label, content_label
end

--[[
创建主操作按钮（蓝色背景 + 白色文字）

@param userdata parent  父容器
@param number   x       X 坐标
@param number   y       Y 坐标
@param number   w       宽度
@param number   h       高度
@param string   text    按钮文字
@param function on_click 点击回调
@return userdata btn    按钮容器
]]
function T.btn_primary(parent, x, y, w, h, text, on_click)
    local btn = airui.container({
        parent = parent,
        x = x, y = y, w = w, h = h,
        color = T.COLOR_PRIMARY, radius = T.BTN_RADIUS,
        on_click = on_click,
    })
    airui.label({
        parent = btn,
        x = 0, y = 0, w = w, h = h,
        text = text,
        font_size = T.FONT_BODY,
        color = T.COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER,
    })
    return btn
end

--[[
创建危险操作按钮（红色背景 + 白色文字）

@param userdata parent  父容器
@param number   x       X 坐标
@param number   y       Y 坐标
@param number   w       宽度
@param number   h       高度
@param string   text    按钮文字
@param function on_click 点击回调
@return userdata btn    按钮容器
]]
function T.btn_danger(parent, x, y, w, h, text, on_click)
    local btn = airui.container({
        parent = parent,
        x = x, y = y, w = w, h = h,
        color = T.COLOR_DANGER, radius = T.BTN_RADIUS,
        on_click = on_click,
    })
    airui.label({
        parent = btn,
        x = 0, y = 0, w = w, h = h,
        text = text,
        font_size = T.FONT_BODY,
        color = T.COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER,
    })
    return btn
end

--[[
创建成功按钮（绿色背景 + 白色文字）
]]
function T.btn_success(parent, x, y, w, h, text, on_click)
    local btn = airui.container({
        parent = parent,
        x = x, y = y, w = w, h = h,
        color = T.COLOR_GREEN, radius = T.BTN_RADIUS,
        on_click = on_click,
    })
    airui.label({
        parent = btn,
        x = 0, y = 0, w = w, h = h,
        text = text,
        font_size = T.FONT_BODY,
        color = T.COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER,
    })
    return btn
end

_G.T = T
return T
