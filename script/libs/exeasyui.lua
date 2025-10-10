--[[
exEasyUI - 简化的UI组件库
版本号：1.6.1
作者： zengshuai 
日期：2025-10-09
=====================================

结构说明：
1. 常量定义 - UI颜色常量和调试配置
2. 硬件依赖 - 使用exlcd/extp初始化LCD和TP,并使用gtfont初始化字体(可选)
3. 核心部分 - 组件管理、事件分发、渲染系统
4. 组件部分 - 目前有6个组件
    - Button：按钮组件
    - CheckBox：复选框组件
    - Label：标签组件
    - Picture：图片组件
    - MessageBox：消息框组件
    - Window：窗口组件
    - ProgressBar：进度条组件

基于原exSimpleUI重构，将所有代码合并为单个文件，便于使用和维护。
支持触摸事件分发、组件渲染、主题切换等核心功能。
]]

local screen_data = require "screen_data_table"     -- 唯一引入屏幕配置参数的地方
local exlcd = require "exlcd"             -- 显示驱动模块
local extp = require "extp"                    -- 触摸驱动模块

gtfont_dev = gtfont_dev or nil                  -- 全局SPI设备句柄，避免被GC

-- ================================
-- 1. 常量定义
-- ================================

-- UI颜色常量
local COLOR_WHITE = 0xFFFF
local COLOR_BLACK = 0x0000
local COLOR_GRAY  = 0x8410
local COLOR_BLUE  = 0x001F
local COLOR_RED   = 0xF800
local COLOR_GREEN = 0x07E0
local COLOR_YELLOW = 0xFFE0
local COLOR_CYAN = 0x07FF
local COLOR_MAGENTA = 0xF81F
local COLOR_ORANGE = 0xFC00
local COLOR_PINK = 0xF81F

-- Windows 11 风格颜色（v1.6.0新增）
-- Light模式
local COLOR_WIN11_LIGHT_DIALOG_BG = 0xF79E      -- RGB(243, 243, 243) - 对话框背景
local COLOR_WIN11_LIGHT_BUTTON_BG = 0xFFDF      -- RGB(251, 251, 252) - 按钮背景
local COLOR_WIN11_LIGHT_BUTTON_BORDER = 0xE73C  -- RGB(229, 229, 229) - 按钮边框
-- Dark模式
local COLOR_WIN11_DARK_DIALOG_BG = 0x2104      -- RGB(32, 32, 32) - 对话框背景
local COLOR_WIN11_DARK_BUTTON_BG = 0x3186      -- RGB(51, 51, 51) - 按钮背景
local COLOR_WIN11_DARK_BUTTON_BORDER = 0x4A69  -- RGB(76, 76, 76) - 按钮边框

-- ================================
-- 2. 硬件依赖部分 (hw)
-- ================================

local hw = {}
local FontAdapter = { _backend = "default", _size = 12, _gray = false, _name = nil }

-- 硬件初始化入口
function hw.init(opts)
	-- 初始化显示屏
    -- 使用screen_data配置表中的参数初始化LCD，在配置表中修改即可
    local lcd_init_success exlcd.init(screen_data.lcdargs)
	

    -- 检查LCD初始化是否成功
    if lcd_init_success then
        log.error("ui_main", "LCD初始化失败")
        return  -- 初始化失败，退出任务
    end

	

	-- 通用显示设置
    lcd.setupBuff(nil, false)     -- 设置帧缓冲区
    lcd.autoFlush(false)          -- 禁止自动刷新

    -- -- 设置字体为模组自带的opposansm12中文字体
    -- lcd.setFont(lcd.font_opposansm12_chinese)

    -- 初始化触摸IC
    -- 使用配置表中的参数初始化触摸
    extp.init(screen_data.touch)
    extp.setPublishEnabled("all", true) -- 发布所有消息

    -- 自定义配置
    extp.setSlideThreshold(40)        -- 设置滑动阈值为40像素
    extp.setLongPressThreshold(600)   -- 设置长按阈值为600毫秒

    -- 字体后端装配（保持原逻辑，可选）
    local fcfg = opts.font or {}
    if fcfg.type == "gtfont" then
        local spi_id = (fcfg.spi and fcfg.spi.id) or 0
        local spi_cs = (fcfg.spi and fcfg.spi.cs) or 8
        local spi_clk = (fcfg.spi and fcfg.spi.clock) or (20 * 1000 * 1000)
        gtfont_dev = spi.deviceSetup(spi_id or 1, spi_cs or 12, 0, 0, 8, spi_clk or (20*1000*1000), spi.MSB, 1, 0)
        log.error("exEasyUI.gtfont", "spi.deviceSetup", type(gtfont_dev))
        if type(gtfont_dev) ~= "userdata" then
            log.error("exEasyUI.gtfont", "spi.deviceSetup error", type(gtfont_dev))
            gtfont_dev = nil
        end
        local gtfont_ok = gtfont.init(gtfont_dev)
        if gtfont_ok then
            FontAdapter._backend = "gtfont"
            FontAdapter._size = tonumber(fcfg.size or 16)
            FontAdapter._gray = not not fcfg.gray
            log.info("exEasyUI", "gtfont enabled", spi_id, spi_cs, FontAdapter._size)
        else
            FontAdapter._backend = "default"
            FontAdapter._size = 12
            FontAdapter._gray = false
            log.warn("exEasyUI", "gtfont init failed, fallback to default font")
        end
    else
        FontAdapter._backend = "default"
        FontAdapter._size = 12
        FontAdapter._gray = false
        FontAdapter._name = (fcfg and fcfg.name) or nil
        if lcd and lcd.setFont and lcd.font_opposansm12_chinese then
            lcd.setFont(lcd.font_opposansm12_chinese)
        end
    end
    return true
end

-- ================================
-- 3. 核心部分 (core + event)
-- ================================

local core = {}
local event = {}

-- 组件注册表
local registry = {}
local last_action = nil
local current_theme = "dark"

-- 调试开关
core.debug_touch = true

-- 调试配置函数
function core.debug(v)
    if v == nil then return { touch = not not core.debug_touch } end
    if type(v) == "boolean" then
        core.debug_touch = v
        return
    end
    if type(v) == "table" then
        if v.touch ~= nil then core.debug_touch = not not v.touch end
        return
    end
end

-- 添加组件到渲染队列
function core.add(component)
    registry[#registry + 1] = component
end

-- 从注册表移除组件
function core.remove(component)
    for i = #registry, 1, -1 do
        if registry[i] == component then
            table.remove(registry, i)
            return true
        end
    end
    return false
end

-- 清屏
function core.clear(color)
    lcd.clear(color or COLOR_BLACK)
end

-- 渲染所有可见组件
function core.render()
    for i = 1, #registry do
        local c = registry[i]
        if c and c.visible ~= false and c.draw then c:draw() end
    end
    lcd.flush()
end

-- 获取当前时间戳
local function now_ms()
    if mcu and mcu.ticks then return mcu.ticks() end
    return (os.clock() or 0) * 1000
end

-- 命中测试
local function hit_test(x, y, r)
    return x >= r.x and y >= r.y and x <= (r.x + r.w) and y <= (r.y + r.h)
end

-- 触摸事件分发（extp事件）
function core.handleTouchEvent(evt, x, y)
    local start_ms
    if core.debug_touch then
        start_ms = now_ms()
    end
    for i = #registry, 1, -1 do
        local c = registry[i]
        if c and c.enabled ~= false and c.handleEvent and 
           (c._capture == true or hit_test(x, y, { x = c.x, y = c.y, w = c.w, h = c.h })) then
            if c:handleEvent(evt, x, y) then
                if core.debug_touch and start_ms then
                    local dt = now_ms() - start_ms
                    log.info("exEasyUI", "consumed_by", tostring(c.__name or "component"), string.format("%.2fms", dt))
                end
                return true
            end
        end
    end
    if core.debug_touch and start_ms then
        local dt = now_ms() - start_ms
        if evt ~= "MOVE_X" and evt ~= "MOVE_Y" then
            log.info("exEasyUI", "not_consumed_cost", string.format("%.2fms", dt))
        end
    end
    return false
end

-- 系统初始化
function core.init(opts)
    opts = opts or {}
    
    -- 主题设置：根据传入参数设置当前主题（light/dark）
    if opts.theme == "light" or opts.theme == "dark" then
        current_theme = opts.theme
    end

    -- 触摸事件订阅与转发（extp）
    -- extp_down_x, extp_down_y 记录按下时的原始坐标
    -- extp_curr_x, extp_curr_y 记录当前触摸点坐标（用于MOVE/滑动等）
    local extp_down_x, extp_down_y
    local extp_curr_x, extp_curr_y

    -- extp_dispatch: 触摸事件分发函数，负责将底层触摸事件转换为UI事件
    -- evt: 事件类型（如TOUCH_DOWN、MOVE_X、SINGLE_TAP等）
    -- a, b: 事件参数（如坐标或偏移量）
    local function extp_dispatch(evt, a, b)
        if evt == "TOUCH_DOWN" then
            -- 记录触摸按下时的原始坐标，a和b通常为触摸点的x、y坐标，若无法转换为数字则默认为0
            extp_down_x, extp_down_y = tonumber(a) or 0, tonumber(b) or 0
            extp_curr_x, extp_curr_y = extp_down_x, extp_down_y
            if core.debug_touch then log.info("exEasyUI", "extp", "TOUCH_DOWN", extp_curr_x, extp_curr_y) end
            -- 分发TOUCH_DOWN事件
            core.handleTouchEvent("TOUCH_DOWN", extp_curr_x, extp_curr_y)
            last_action = "TOUCH_DOWN"
            return
        end

        -- 若未按下则忽略后续事件
        if not extp_down_x or not extp_down_y then return end

        if evt == "MOVE_X" then
            -- 处理横向滑动，a为x方向偏移
            local dx = tonumber(a) or 0
            extp_curr_x = extp_down_x + dx
            if core.debug_touch then log.info("exEasyUI", "extp", "MOVE_X", extp_curr_x, extp_curr_y) end
            core.handleTouchEvent("MOVE_X", extp_curr_x, extp_curr_y)
            last_action = "MOVE_X"
            return
        elseif evt == "MOVE_Y" then
            -- 处理纵向滑动，b为y方向偏移
            local dy = tonumber(b) or 0
            extp_curr_y = extp_down_y + dy
            if core.debug_touch then log.info("exEasyUI", "extp", "MOVE_Y", extp_curr_x, extp_curr_y) end
            core.handleTouchEvent("MOVE_Y", extp_curr_x, extp_curr_y)
            last_action = "MOVE_Y"
            return
        elseif evt == "SWIPE_LEFT" or evt == "SWIPE_RIGHT" then
            -- 处理左右滑动手势，a为x方向偏移
            local dx = tonumber(a) or 0
            extp_curr_x = extp_down_x + dx
            if core.debug_touch then log.info("exEasyUI", "extp", evt, extp_curr_x, extp_curr_y) end
            core.handleTouchEvent(evt, extp_curr_x, extp_curr_y)
            last_action = evt
        elseif evt == "SWIPE_UP" or evt == "SWIPE_DOWN" then
            -- 处理上下滑动手势，b为y方向偏移
            local dy = tonumber(b) or 0
            extp_curr_y = extp_down_y + dy
            if core.debug_touch then log.info("exEasyUI", "extp", evt, extp_curr_x, extp_curr_y) end
            core.handleTouchEvent(evt, extp_curr_x, extp_curr_y)
            last_action = evt
        elseif evt == "SINGLE_TAP" or evt == "LONG_PRESS" then
            -- 处理单击/长按事件，a/b为最终坐标（若无则用当前坐标）
            local ux = tonumber(a) or extp_curr_x or 0
            local uy = tonumber(b) or extp_curr_y or 0
            if core.debug_touch then log.info("exEasyUI", "extp", evt, ux, uy) end
            core.handleTouchEvent(evt, ux, uy)
            last_action = evt
        end

        -- 触摸序列结束后，清空坐标状态
        if last_action == "SINGLE_TAP" or last_action == "LONG_PRESS" or
           last_action == "SWIPE_LEFT" or last_action == "SWIPE_RIGHT" or
           last_action == "SWIPE_UP" or last_action == "SWIPE_DOWN" then
            extp_down_x, extp_down_y = nil, nil
            extp_curr_x, extp_curr_y = nil, nil
        end
    end

    -- 订阅底层触摸事件（baseTouchEvent），由extp_dispatch处理
    sys.subscribe("baseTouchEvent", extp_dispatch)
end

-- 获取当前主题
function core.getTheme()
    return current_theme
end

-- 事件系统：订阅事件
function event.on(name, cb)
    return sys.subscribe(name, cb)
end

-- 事件系统：发送事件
function event.emit(name, ...)
    return sys.publish(name, ...)
end

-- ================================
-- 4. 组件部分
-- ================================

-- 通用绘图函数
local function fill_rect(x1, y1, x2, y2, color)
    lcd.fill(x1, y1, x2, y2 + 1, color) -- 右下边界为不含区间, y2需要+1
end

local function stroke_rect(x1, y1, x2, y2, color)
    lcd.drawLine(x1, y1, x2, y1, color)
    lcd.drawLine(x2, y1, x2, y2, color)
    lcd.drawLine(x2, y2, x1, y2, color)
    lcd.drawLine(x1, y2, x1, y1, color)
end

-- v1.6.1新增：绘制图片占位符（方框+X叉）
local function draw_image_placeholder(x, y, w, h, bg_color, border_color)
    bg_color = bg_color or 0x8410  -- 默认灰色
    border_color = border_color or COLOR_WHITE
    
    -- 填充背景
    fill_rect(x, y, x + w - 1, y + h - 1, bg_color)
    
    -- 绘制边框
    stroke_rect(x, y, x + w - 1, y + h - 1, border_color)
    
    -- 绘制X叉（对角线）
    lcd.drawLine(x, y, x + w - 1, y + h - 1, border_color)
    lcd.drawLine(x + w - 1, y, x, y + h - 1, border_color)
    
    -- 如果尺寸足够大，绘制内缩的X叉使其更明显
    if w >= 20 and h >= 20 then
        local margin = math.min(w, h) // 8  -- 内缩边距
        lcd.drawLine(x + margin, y + margin, x + w - 1 - margin, y + h - 1 - margin, border_color)
        lcd.drawLine(x + w - 1 - margin, y + margin, x + margin, y + h - 1 - margin, border_color)
    end
end

-- FontAdapter 实现
local function font_line_height(style)
    if FontAdapter._backend == "gtfont" then
        local sz = (style and style.size) or FontAdapter._size or 16
        return sz
    end
    -- default backend：优先使用样式中的 size，没有则回退 12
    if style and style.size then
        return tonumber(style.size) or 12
    end
    return 12
end

local function font_set(style)
    style = style or {}
    if FontAdapter._backend == "gtfont" then
        FontAdapter._size = tonumber(style.size or FontAdapter._size or 16)
        FontAdapter._gray = (style.gray ~= nil) and not not style.gray or FontAdapter._gray
        if lcd and lcd.setFont and lcd.drawGtfontUtf8 then
            lcd.setFont(lcd.drawGtfontUtf8)
        end
        return
    end
    -- default backend
    FontAdapter._name = style.name or FontAdapter._name
    if lcd and lcd.setFont then
        -- 优先按 name，其次按 size 猜测常见字体名，最后回退
        if FontAdapter._name and lcd["font_" .. FontAdapter._name] then
            lcd.setFont(lcd["font_" .. FontAdapter._name])
        elseif style and style.size then
            local size_num = tonumber(style.size)
            if size_num then
                local guess = "font_opposansm" .. tostring(size_num) .. "_chinese"
                if lcd[guess] then
                    lcd.setFont(lcd[guess])
                elseif lcd.font_opposansm12_chinese then
                    lcd.setFont(lcd.font_opposansm12_chinese)
                end
            elseif lcd.font_opposansm12_chinese then
                lcd.setFont(lcd.font_opposansm12_chinese)
            end
        elseif lcd.font_opposansm12_chinese then
            lcd.setFont(lcd.font_opposansm12_chinese)
        end
    end
end

local function font_draw(text, x, y, color, style)
    color = color or COLOR_WHITE
    style = style or {}
    if FontAdapter._backend == "gtfont" then
        local sz = tonumber(style.size or FontAdapter._size or 16)
        if FontAdapter._gray and lcd.drawGtfontUtf8Gray then
            -- 固件灰度级目前不可调，传固定值4
            lcd.drawGtfontUtf8Gray(text, sz, 4, x, y, color)
        elseif lcd.drawGtfontUtf8 then
            lcd.drawGtfontUtf8(text, sz, x, y, color)
        else
            -- 回退：不应触达
            if lcd.drawStr then
                lcd.drawStr(x, y + 12, text, color)
            end
        end
        return
    end
    -- default backend：y 为顶部坐标，内部转换为基线
    if lcd and lcd.setFont then
        if FontAdapter._name and lcd["font_" .. FontAdapter._name] then
            lcd.setFont(lcd["font_" .. FontAdapter._name])
        else
            -- 尝试根据 size 选择合适字体
            local used = false
            if style and style.size then
                local guess = "font_opposansm" .. tostring(style.size) .. "_chinese"
                if lcd[guess] then
                    lcd.setFont(lcd[guess])
                    used = true
                end
            end
            if not used and lcd.font_opposansm12_chinese then
                lcd.setFont(lcd.font_opposansm12_chinese)
            end
        end
    end
    local lh = font_line_height(style)
    lcd.drawStr(x, y + lh, text, color)
end

-- 文本宽度测量
local function font_measure(text, style)
    if not text or text == "" then return 0 end
    style = style or {}
    if FontAdapter._backend == "gtfont" then
        local sz = tonumber(style.size or FontAdapter._size or 16)
        local w = 0
        local i = 1
        while i <= #text do
            local b = string.byte(text, i)
            if b == 32 then -- space
                w = w + math.ceil(sz / 2)
                i = i + 1
            elseif b < 128 then
                w = w + math.ceil(sz / 2)
                i = i + 1
            else
                w = w + sz
                -- 简化处理UTF-8宽字节
                if i + 2 <= #text then i = i + 3 else i = i + 1 end
            end
        end
        return w
    end
    -- default backend，尽量使用原生接口
    if lcd and lcd.setFont then
        -- 尝试在测量前设置到期望字体，以匹配绘制
        if FontAdapter._name and lcd["font_" .. FontAdapter._name] then
            lcd.setFont(lcd["font_" .. FontAdapter._name])
        elseif style and style.size then
            local guess = "font_opposansm" .. tostring(style.size) .. "_chinese"
            if lcd[guess] then
                lcd.setFont(lcd[guess])
            elseif lcd.font_opposansm12_chinese then
                lcd.setFont(lcd.font_opposansm12_chinese)
            end
        elseif lcd.font_opposansm12_chinese then
            lcd.setFont(lcd.font_opposansm12_chinese)
        end
    end
    if lcd and lcd.getStrWidth then return lcd.getStrWidth(text) end
    if lcd and lcd.strWidth then return lcd.strWidth(text) end
    if lcd and lcd.get_string_width then return lcd.get_string_width(text) end
    -- 估算：英文约为 size/2，中文约为 size
    local width = 0
    local i = 1
    while i <= #text do
        local byte = string.byte(text, i)
        if byte < 128 then
            width = width + math.ceil((tonumber(style.size) or 12) / 2)
            i = i + 1
        else
            width = width + (tonumber(style.size) or 12)
            i = i + 3
        end
    end
    return width
end

-- UTF-8字符获取（返回字符和字节长度）
local function get_utf8_char(text, i)
    if not text or i > #text then return "", 0 end
    local byte = string.byte(text, i)
    if byte < 128 then
        -- ASCII字符（1字节）
        return string.sub(text, i, i), 1
    elseif byte >= 224 and byte < 240 then
        -- 3字节UTF-8字符（中文等）
        if i + 2 <= #text then
            return string.sub(text, i, i + 2), 3
        else
            return string.sub(text, i, i), 1
        end
    elseif byte >= 192 and byte < 224 then
        -- 2字节UTF-8字符
        if i + 1 <= #text then
            return string.sub(text, i, i + 1), 2
        else
            return string.sub(text, i, i), 1
        end
    elseif byte >= 240 then
        -- 4字节UTF-8字符
        if i + 3 <= #text then
            return string.sub(text, i, i + 3), 4
        else
            return string.sub(text, i, i), 1
        end
    else
        -- 其他情况
        return string.sub(text, i, i), 1
    end
end

-- 文本换行处理（返回行数组）
-- 支持英文按单词换行，中文按字符换行
local function wrap_text_lines(text, maxWidth, style)
    if not text or text == "" then return {""} end
    if not maxWidth or maxWidth <= 0 then return {text} end
    
    local lines = {}
    local currentLine = ""
    local currentWidth = 0
    local wordBuffer = ""  -- 当前英文单词缓冲
    local wordWidth = 0    -- 当前单词宽度
    local i = 1
    
    while i <= #text do
        local char, charLen = get_utf8_char(text, i)
        local charWidth = font_measure(char, style)
        local byte = string.byte(text, i)
        
        -- 判断是否为英文字母或数字
        local isAlphaNum = (byte >= 48 and byte <= 57) or   -- 0-9
                          (byte >= 65 and byte <= 90) or    -- A-Z
                          (byte >= 97 and byte <= 122)      -- a-z
        
        if isAlphaNum then
            -- 英文字符或数字，加入单词缓冲
            wordBuffer = wordBuffer .. char
            wordWidth = wordWidth + charWidth
            i = i + charLen
        else
            -- 非英文字符（空格、标点、中文等）
            -- 先处理缓冲的单词
            if wordBuffer ~= "" then
                if currentWidth + wordWidth > maxWidth then
                    -- 单词放不下
                    if currentLine ~= "" then
                        -- 当前行有内容，换行后放单词
                        table.insert(lines, currentLine)
                        currentLine = wordBuffer
                        currentWidth = wordWidth
                    else
                        -- 单词本身超长，强制显示
                        currentLine = wordBuffer
                        currentWidth = wordWidth
                    end
                else
                    -- 单词可以放下
                    currentLine = currentLine .. wordBuffer
                    currentWidth = currentWidth + wordWidth
                end
                wordBuffer = ""
                wordWidth = 0
            end
            
            -- 处理当前字符（空格、标点、中文等）
            if char == " " then
                -- 空格：尝试加入当前行
                if currentWidth + charWidth <= maxWidth then
                    currentLine = currentLine .. char
                    currentWidth = currentWidth + charWidth
                else
                    -- 空格放不下，换行（空格不放到下一行开头）
                    if currentLine ~= "" then
                        table.insert(lines, currentLine)
                    end
                    currentLine = ""
                    currentWidth = 0
                end
            else
                -- 标点或中文
                if currentWidth + charWidth > maxWidth then
                    -- 字符放不下，换行
                    if currentLine ~= "" then
                        table.insert(lines, currentLine)
                    end
                    currentLine = char
                    currentWidth = charWidth
                else
                    -- 字符可以放下
                    currentLine = currentLine .. char
                    currentWidth = currentWidth + charWidth
                end
            end
            i = i + charLen
        end
    end
    
    -- 处理剩余的单词
    if wordBuffer ~= "" then
        if currentWidth + wordWidth > maxWidth and currentLine ~= "" then
            -- 单词放不下，换行
            table.insert(lines, currentLine)
            currentLine = wordBuffer
        else
            currentLine = currentLine .. wordBuffer
        end
    end
    
    -- 添加最后一行
    if currentLine ~= "" then
        table.insert(lines, currentLine)
    end
    
    -- 至少返回一个空行
    if #lines == 0 then
        lines = {""}
    end
    
    return lines
end

-- 兼容旧接口已移除，统一使用下方两个新 API

-- 新增：直接绘制文本 API（支持 style.size/name/gray）
local function draw_text_direct(x, y, text, opts)
    opts = opts or {}
    local color = opts.color or COLOR_WHITE
    local style = opts.style or {}
    font_draw(text or "", x, y, color, style)
end

-- 新增：在矩形内自适应（仅居中与边界约束，不缩放、不换行）
local function draw_text_in_rect_centered(x, y, w, h, text, opts)
    opts = opts or {}
    local color = opts.color or COLOR_WHITE
    local style = opts.style or {}
    local padding = opts.padding or 0

    local tw = font_measure(text or "", style)
    local lh = font_line_height(style)

    local inner_x = x + padding
    local inner_y = y + padding
    local inner_w = w - padding * 2
    local inner_h = h - padding * 2

    local tx = inner_x + (inner_w - tw) // 2
    local ty = inner_y + (inner_h - lh) // 2

    -- 夹紧，避免越界
    tx = math.max(inner_x, tx)
    tx = math.min(inner_x + inner_w - tw, tx)

    font_draw(text or "", tx, ty, color, style)
end

-- 旧的宽度测量包装已移除，请直接使用 font_measure(text, style)

-- Button组件 - 基础按钮，支持文本/图片、按下/抬起与点击回调，支持toggle模式
local Button = {}
Button.__index = Button

function Button:new(opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    o.x = opts.x or 0
    o.y = opts.y or 0
    o.w = opts.width or opts.w or 100
    o.h = opts.height or opts.h or 36
    
    -- 文本模式参数
    o.text = opts.text or "Button"
    o.textSize = opts.textSize or opts.size
    local dark = (current_theme == "dark")
    o.bgColor = opts.bgColor or (dark and COLOR_WIN11_DARK_BUTTON_BG or COLOR_WIN11_LIGHT_BUTTON_BG)
    o.textColor = opts.textColor or (dark and COLOR_WHITE or COLOR_BLACK)
    o.borderColor = opts.borderColor or (dark and COLOR_WIN11_DARK_BUTTON_BORDER or COLOR_WIN11_LIGHT_BUTTON_BORDER)
    
    -- 图片模式参数（v1.6.0新增，合并自ToolButton）
    o.src = opts.src
    o.src_pressed = opts.src_pressed
    o.src_toggled = opts.src_toggled
    
    -- Toggle模式参数（v1.6.0新增）
    o.toggle = opts.toggle or false
    o.toggled = opts.toggled or false
    o.onToggle = opts.onToggle
    
    -- 状态
    o.pressed = false
    o.onClick = opts.onClick
    o.visible = opts.visible ~= false
    o.enabled = opts.enabled ~= false
    o._imageCache = {}  -- v1.6.1：缓存图片加载状态，避免重复检查和重复打印警告
    return o
end

function Button:draw()
    if not self.visible then return end
    
    -- 图片模式：优先显示图片
    if self.src then
        local path
        if self.toggle and self.toggled then
            path = self.src_toggled or self.src
        elseif self.pressed then
            path = self.src_pressed or self.src
        else
            path = self.src
        end
        
        -- v1.6.1修复：检查文件是否存在，并改进占位符显示（使用缓存避免重复检查）
        if type(path) == "string" and path ~= "" and path:lower():sub(-4) == ".jpg" then
            -- 检查缓存
            if self._imageCache[path] == nil then
                -- 未缓存，首次检查文件是否存在
                if io and io.exists and io.exists(path) then
                    self._imageCache[path] = true  -- 缓存：文件存在
                else
                    self._imageCache[path] = false  -- 缓存：文件不存在
                    log.warn("Button", "图片文件不存在:", path)
                end
            end
            
            -- 根据缓存状态处理
            if self._imageCache[path] == true then
                lcd.showImage(self.x, self.y, path)
            else
                -- 文件不存在（已缓存），直接显示占位符，不再重复警告
                draw_image_placeholder(self.x, self.y, self.w, self.h, COLOR_GRAY, COLOR_WHITE)
            end
        else
            -- path无效或不是jpg，显示占位符
            draw_image_placeholder(self.x, self.y, self.w, self.h, COLOR_GRAY, COLOR_WHITE)
        end
        return
    end
    
    -- 文本模式：绘制文本按钮
    local bg = self.pressed and COLOR_GRAY or self.bgColor
    fill_rect(self.x, self.y, self.x + self.w - 1, self.y + self.h - 1, bg)
    stroke_rect(self.x, self.y, self.x + self.w - 1, self.y + self.h - 1, self.borderColor)
    draw_text_in_rect_centered(self.x, self.y, self.w, self.h, self.text, {
        color = self.textColor,
        style = { size = self.textSize },
        padding = 2
    })
end

function Button:setText(newText)
    self.text = tostring(newText or "")
end

function Button:handleEvent(evt, x, y)
    if not self.enabled then return false end
    local inside = hit_test(x, y, { x = self.x, y = self.y, w = self.w, h = self.h })
    
    if evt == "TOUCH_DOWN" and inside then
        self.pressed = true
        self._capture = true
        return true
    elseif evt == "MOVE_X" or evt == "MOVE_Y" then
        if self._capture then
            self.pressed = inside
            return true
        end
    elseif evt == "SINGLE_TAP" then
        local was_pressed = self.pressed
        self.pressed = false
        self._capture = false
        if was_pressed and inside then
            -- Toggle模式处理
            if self.toggle then
                self.toggled = not self.toggled
                if self.onToggle then self.onToggle(self.toggled, self) end
            end
            -- 触发点击回调
            if self.onClick then self.onClick(self) end
            return true
        end
        return true
    elseif evt == "LONG_PRESS" or evt == "SWIPE_LEFT" or evt == "SWIPE_RIGHT" or evt == "SWIPE_UP" or evt == "SWIPE_DOWN" then
        self.pressed = false
        self._capture = false
        return true
    end
    return false
end

-- CheckBox组件 - 复选框，支持选中状态切换
local CheckBox = {}
CheckBox.__index = CheckBox

function CheckBox:new(opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    o.x = opts.x or 0
    o.y = opts.y or 0
    o.boxSize = opts.boxSize or 16
    o.text = opts.text
    local dark = (current_theme == "dark")
    o.textColor = opts.textColor or (dark and COLOR_WHITE or COLOR_BLACK)
    o.borderColor = opts.borderColor or (dark and COLOR_WHITE or COLOR_BLACK)
    o.bgColor = opts.bgColor or (dark and COLOR_BLACK or COLOR_WHITE)
    o.tickColor = opts.tickColor or (dark and COLOR_WHITE or COLOR_BLACK)
    o.checked = opts.checked or false
    o.enabled = opts.enabled ~= false
    o.visible = opts.visible ~= false
    o.onChange = opts.onChange
    local text_w = (o.text and (#o.text * 6 + 6) or 0)
    o.w = o.boxSize + text_w
    o.h = math.max(o.boxSize, 16)
    return o
end

function CheckBox:draw()
    local x2 = self.x + self.boxSize - 1
    local y2 = self.y + self.boxSize - 1
    stroke_rect(self.x, self.y, x2, y2, self.borderColor)
    fill_rect(self.x + 2, self.y + 2, x2 - 2, y2 - 2, self.bgColor)
    if self.checked then
        local pad = 2
        fill_rect(self.x + pad, self.y + pad, x2 - pad, y2 - pad, self.tickColor)
    end
    if self.text then
        local lh = font_line_height(nil)
        local ty = self.y + (self.h - lh) // 2
        draw_text_direct(self.x + self.boxSize + 10, ty, self.text, { color = self.textColor })
    end
end

function CheckBox:setChecked(v)
    local nv = not not v
    if nv ~= self.checked then
        self.checked = nv
        if self.onChange then self.onChange(self.checked) end
    end
end

function CheckBox:toggle()
    self:setChecked(not self.checked)
end

function CheckBox:handleEvent(evt, x, y)
    if not self.enabled then return false end
    if evt == "SINGLE_TAP" then
        if x >= self.x and y >= self.y and x <= (self.x + self.w) and y <= (self.y + self.h) then
            self:toggle()
            return true
        end
    end
    return false
end

-- Label组件 - 文本标签，仅显示不响应事件
local Label = {}
Label.__index = Label

function Label:new(opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    o.x = opts.x or 0
    o.y = opts.y or 0
    o.text = tostring(opts.text or "")
    local dark = (current_theme == "dark")
    o.color = opts.color or (dark and COLOR_WHITE or COLOR_BLACK)
    o.font = opts.font
    o.size = opts.size or opts.textSize
    o.wordWrap = not not opts.wordWrap  -- 是否启用换行
    o._autoW = (opts.w == nil)
    o._autoH = true  -- 高度始终自动计算
    o.visible = opts.visible ~= false
    o.enabled = opts.enabled ~= false
    
    -- 宽度处理
    local style = { size = o.size }
    if opts.w then
        o.w = opts.w
        o._autoW = false
    else
        o.w = font_measure(o.text, style)
        o._autoW = true
    end
    
    -- 高度处理（根据是否换行）
    local lh = font_line_height(style)
    if o.wordWrap and not o._autoW then
        -- 启用换行且指定了宽度，计算多行高度
        local lines = wrap_text_lines(o.text, o.w, style)
        o.h = #lines * lh
        o._lines = lines
    else
        -- 单行高度
        o.h = lh
        o._lines = nil
    end
    
    return o
end

function Label:setText(t)
    self.text = tostring(t or "")
    local style = { size = self.size }
    local lh = font_line_height(style)
    
    -- 更新宽度（如果自动）
    if self._autoW then
        self.w = font_measure(self.text, style)
    end
    
    -- 更新高度和行缓存
    if self.wordWrap and not self._autoW then
        local lines = wrap_text_lines(self.text, self.w, style)
        self.h = #lines * lh
        self._lines = lines
    else
        self.h = lh
        self._lines = nil
    end
end

function Label:setSize(sz)
    self.size = tonumber(sz) or self.size
    local style = { size = self.size }
    local lh = font_line_height(style)
    
    -- 更新宽度（如果自动）
    if self._autoW then
        self.w = font_measure(self.text or "", style)
    end
    
    -- 更新高度和行缓存
    if self.wordWrap and not self._autoW then
        local lines = wrap_text_lines(self.text or "", self.w, style)
        self.h = #lines * lh
        self._lines = lines
    else
        self.h = lh
        self._lines = nil
    end
end

function Label:draw()
    if not self.visible then return end
    
    local style = { size = self.size }
    
    -- 若指定自定义字体指针，走默认后端路径（不支持换行）
    if self.font and lcd and lcd.setFont then
        lcd.setFont(self.font)
        local lh = font_line_height(nil)
        lcd.drawStr(self.x, self.y + lh, self.text, self.color)
        return
    end
    
    -- 换行模式
    if self.wordWrap and not self._autoW then
        local lines = self._lines or wrap_text_lines(self.text, self.w, style)
        local lh = font_line_height(style)
        for i = 1, #lines do
            local yPos = self.y + (i - 1) * lh
            draw_text_direct(self.x, yPos, lines[i], { color = self.color, style = style })
        end
        return
    end
    
    -- 无换行模式：截断显示
    if not self._autoW then
        -- 有指定宽度限制，需要截断
        local displayText = self.text
        local tw = font_measure(displayText, style)
        if tw > self.w then
            -- 逐字符截断，直到宽度合适
            local truncated = ""
            local i = 1
            while i <= #displayText do
                local char, charLen = get_utf8_char(displayText, i)
                local testText = truncated .. char
                if font_measure(testText, style) <= self.w then
                    truncated = testText
                    i = i + charLen
                else
                    break
                end
            end
            displayText = truncated
        end
        draw_text_direct(self.x, self.y, displayText, { color = self.color, style = style })
    else
        -- 自动宽度，直接显示
        draw_text_direct(self.x, self.y, self.text, { color = self.color, style = style })
    end
end

function Label:handleEvent(evt, x, y)
    return false -- 文本不拦截事件
end

-- Picture组件 - 显示单图或轮播多图
local Picture = {}
Picture.__index = Picture

function Picture:new(opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    o.x = opts.x or 0
    o.y = opts.y or 0
    o.w = opts.w or 80
    o.h = opts.h or 80
    o.src = opts.src
    o.sources = opts.sources
    o.index = opts.index or 1
    o.autoplay = not not opts.autoplay
    o.interval = opts.interval or 1000
    o._last_switch = now_ms()
    o.visible = opts.visible ~= false
    o.enabled = opts.enabled ~= false
    o._imageCache = {}  -- v1.6.1：缓存图片加载状态，避免重复检查和重复打印警告
    return o
end

function Picture:setSources(list)
    self.sources = list
    self.index = 1
end

function Picture:next()
    if self.sources and #self.sources > 0 then
        self.index = self.index % #self.sources + 1
    end
end

function Picture:prev()
    if self.sources and #self.sources > 0 then
        self.index = (self.index - 2) % #self.sources + 1
    end
end

function Picture:play() 
    self.autoplay = true 
end

function Picture:pause() 
    self.autoplay = false 
end

function Picture:draw()
    if not self.visible then return end
    -- 自动轮播
    if self.autoplay and self.sources and #self.sources > 1 then
        local t = now_ms()
        if (t - self._last_switch) >= self.interval then
            self:next()
            self._last_switch = t
        end
    end
    -- 选择当前图片路径
    local path
    if self.sources and #self.sources > 0 then
        path = self.sources[self.index]
    else
        path = self.src
    end
    
    -- v1.6.1修复：检查文件是否存在，并改进占位符显示（使用缓存避免重复检查）
    if type(path) == "string" and path ~= "" and path:lower():sub(-4) == ".jpg" then
        -- 检查缓存
        if self._imageCache[path] == nil then
            -- 未缓存，首次检查文件是否存在
            if io and io.exists and io.exists(path) then
                self._imageCache[path] = true  -- 缓存：文件存在
            else
                self._imageCache[path] = false  -- 缓存：文件不存在
                log.warn("Picture", "图片文件不存在:", path)
            end
        end
        
        -- 根据缓存状态处理
        if self._imageCache[path] == true then
            lcd.showImage(self.x, self.y, path)
        else
            -- 文件不存在（已缓存），显示占位符
            draw_image_placeholder(self.x, self.y, self.w, self.h, 0x4208, COLOR_WHITE)
        end
    elseif path then
        -- path不是jpg或无效路径，显示占位符
        draw_image_placeholder(self.x, self.y, self.w, self.h, 0x4208, COLOR_WHITE)
    end
    -- 如果path为nil，不显示任何内容（不绘制占位符）
end

function Picture:handleEvent(evt, x, y)
    return false -- 默认不消费事件
end

-- MessageBox组件 - 消息框，包含标题、文本和按钮组
local MessageBox = {}
MessageBox.__index = MessageBox

function MessageBox:new(opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    o.x = opts.x or 20
    o.y = opts.y or 40
    o.w = opts.width or opts.w or 280
    o.h = opts.height or opts.h or 160
    o.title = opts.title or "Info"
    o.message = opts.message or ""
    o.wordWrap = opts.wordWrap ~= false  -- v1.6.1修复：默认启用自动换行，除非显式传入false
    o.textSize = opts.textSize or opts.size  -- 文本字号
    local dark = (current_theme == "dark")
    o.borderColor = opts.borderColor or (dark and COLOR_WHITE or COLOR_BLACK)
    o.textColor = opts.textColor or (dark and COLOR_WHITE or COLOR_BLACK)
    o.bgColor = opts.bgColor or (dark and COLOR_BLACK or COLOR_WHITE)
    o.buttons = opts.buttons or { "OK" }
    o.onResult = opts.onResult
    o.visible = opts.visible ~= false  -- v1.6.1修复：支持从opts读取visible参数，默认true
    o.enabled = opts.enabled ~= false  -- v1.6.1修复：支持从opts读取enabled参数，默认true

    -- 内部按钮布局
    o._btns = {}
    local btn_w = 80
    local gap = 12
    local total_w = #o.buttons * btn_w + (#o.buttons - 1) * gap
    local bx = o.x + (o.w - total_w) // 2
    local by = o.y + o.h - 12 - 36
    for i = 1, #o.buttons do
        local label = o.buttons[i]
        local b = Button:new({ x = bx, y = by, w = btn_w, h = 36, text = label })
        b.onClick = function()
            if o.onResult then o.onResult(label) end
            o.visible = false
            -- v1.6.1修复：不再禁用enabled，允许MessageBox复用
        end
        o._btns[#o._btns + 1] = b
        bx = bx + btn_w + gap
    end
    
    -- 计算message文本可用区域
    o._msgPadding = 10  -- 左右内边距
    o._msgMaxWidth = o.w - o._msgPadding * 2
    o._msgStartY = 36  -- message文本起始Y（相对于MessageBox）
    -- v1.6.1修复：根据是否有按钮动态计算可用高度
    if #o.buttons > 0 then
        o._msgMaxHeight = o.h - 12 - 36 - o._msgStartY  -- 有按钮：预留底部边距12 + 按钮高度36
    else
        o._msgMaxHeight = o.h - 10 - o._msgStartY  -- 无按钮：只保留底部边距10
    end
    
    return o
end

function MessageBox:draw()
    if not self.visible then return end
    fill_rect(self.x, self.y, self.x + self.w - 1, self.y + self.h - 1, self.bgColor)
    stroke_rect(self.x, self.y, self.x + self.w - 1, self.y + self.h - 1, self.borderColor)
    
    -- 绘制标题
    draw_text_direct(self.x + 10, self.y + 8, self.title, { color = self.textColor, style = { size = self.textSize } })
    
    -- 绘制message文本
    local msgX = self.x + self._msgPadding
    local msgY = self.y + self._msgStartY
    local style = { size = self.textSize }
    
    if self.wordWrap then
        -- 换行模式：在固定高度内显示多行，超出截断
        local lines = wrap_text_lines(self.message, self._msgMaxWidth, style)
        local lh = font_line_height(style)
        local maxLines = math.floor(self._msgMaxHeight / lh)
        
        for i = 1, math.min(#lines, maxLines) do
            local yPos = msgY + (i - 1) * lh
            draw_text_direct(msgX, yPos, lines[i], { color = self.textColor, style = style })
        end
    else
        -- 无换行模式：单行显示
        draw_text_direct(msgX, msgY, self.message, { color = self.textColor, style = style })
    end
    
    -- 绘制按钮
    for i = 1, #self._btns do 
        self._btns[i]:draw() 
    end
end

function MessageBox:handleEvent(evt, x, y)
    if not self.enabled then return false end
    for i = 1, #self._btns do
        local b = self._btns[i]
        if hit_test(x, y, { x = b.x, y = b.y, w = b.w, h = b.h }) then
            return b:handleEvent(evt, x, y)
        end
    end
    return true -- 拦截其它事件
end

-- v1.6.1新增：MessageBox复用方法
function MessageBox:show()
    self.visible = true
    self.enabled = true
end

function MessageBox:hide()
    self.visible = false
end

function MessageBox:setTitle(title)
    self.title = tostring(title or "")
end

function MessageBox:setMessage(message)
    self.message = tostring(message or "")
    -- 如果启用了换行，更新行缓存
    if self.wordWrap then
        local style = { size = self.textSize }
        self._lines = wrap_text_lines(self.message, self._msgMaxWidth, style)
    end
end

-- Window组件 - 窗口容器，支持子组件管理和子页面导航
local Window = {}
Window.__index = Window

function Window:new(opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    local sw, sh = lcd.getSize()
    o.x = opts.x or 0
    o.y = opts.y or 0
    o.w = opts.w or sw
    o.h = opts.h or sh
    o.backgroundImage = opts.backgroundImage
    local dark = (current_theme == "dark")
    o.backgroundColor = opts.backgroundColor or (dark and COLOR_WIN11_DARK_DIALOG_BG or COLOR_WIN11_LIGHT_DIALOG_BG)
    o.children = {}
    o.visible = opts.visible ~= false
    o.enabled = opts.enabled ~= false
    o._managed = nil
    o:enableSubpageManager()
    -- 滚动配置（0.1 版：纵向/横向）
    o._scroll = nil
    return o
end

function Window:add(child)
    self.children[#self.children + 1] = child
end

function Window:remove(child)
    for i = #self.children, 1, -1 do
        if self.children[i] == child then 
            table.remove(self.children, i) 
            return true 
        end
    end
    return false
end

function Window:clear()
    self.children = {}
end

function Window:setBackgroundImage(path)
    self.backgroundImage = path
end

function Window:setBackgroundColor(color)
    self.backgroundColor = color
    self.backgroundImage = nil
end

function Window:draw()
    -- 背景
    if self.backgroundImage then
        lcd.showImage(self.x, self.y, self.backgroundImage)
    else
        lcd.fill(self.x, self.y, self.x + self.w, self.y + self.h, self.backgroundColor)
    end
    -- 子组件
    local offX, offY = 0, 0
    if self._scroll and self._scroll.enabled then
        if self._scroll.direction == "vertical" then
            offY = self._scroll.offsetY or 0
        elseif self._scroll.direction == "horizontal" then
            offX = self._scroll.offsetX or 0
        elseif self._scroll.direction == "both" then
            offX = self._scroll.offsetX or 0
            offY = self._scroll.offsetY or 0
        end
    end
    for i = 1, #self.children do
        local c = self.children[i]
        if c and c.visible ~= false and c.draw then
            local ox, oy = c.x, c.y
            if self._scroll and self._scroll.enabled then c.x = ox + offX c.y = oy + offY end
            c:draw()
            if self._scroll and self._scroll.enabled then c.x, c.y = ox, oy end
        end
    end
end

function Window:handleEvent(evt, x, y)
    if not self.enabled then return false end
    if not hit_test(x, y, { x = self.x, y = self.y, w = self.w, h = self.h }) then return false end
    -- 简易滚动（0.1）：vertical/horizontal
    if self._scroll and self._scroll.enabled then
        local sc = self._scroll
        local contentW = sc.contentWidth or self.w
        local contentH = sc.contentHeight or self.h
        local minX = math.min(0, self.w - (contentW or self.w))
        local maxX = 0
        local minY = math.min(0, self.h - (contentH or self.h))
        local maxY = 0
        if evt == "TOUCH_DOWN" then
            sc.startX = x
            sc.startY = y
            sc.baseOffsetX = sc.offsetX or 0
            sc.baseOffsetY = sc.offsetY or 0
            sc.dragging = false
            sc.captured = false
            -- 透传按下给命中的子组件，便于组件进入按下态；若后续进入拖拽会被取消
            local tx = x - (sc.offsetX or 0)
            local ty = y - (sc.offsetY or 0)
            sc.downTarget = nil
            for i = #self.children, 1, -1 do
                local c = self.children[i]
                if c and c.enabled ~= false and c.handleEvent and 
                   hit_test(tx, ty, { x = c.x, y = c.y, w = c.w, h = c.h }) then
                    sc.downTarget = c
                    c:handleEvent("TOUCH_DOWN", tx, ty)
                    break
                end
            end
            return true
        elseif evt == "MOVE_Y" or evt == "MOVE_X" then
            local dx = (x - (sc.startX or x))
            local dy = (y - (sc.startY or y))
            if not sc.dragging then
                local m = math.max(math.abs(dx), math.abs(dy))
                if m >= (sc.threshold or 10) then
                    sc.dragging = true
                    sc.captured = true
                    -- 进入拖拽，取消先前按下态
                    if sc.downTarget and sc.downTarget.handleEvent then
                        local tx = x - (sc.offsetX or 0)
                        local ty = y - (sc.offsetY or 0)
                        sc.downTarget:handleEvent("LONG_PRESS", tx, ty)
                    end
                    sc.downTarget = nil
                else
                    -- v1.6.1修复：未达拖拽阈值时（观望期），转发MOVE给downTarget让其实时更新状态
                    if sc.downTarget and sc.downTarget.handleEvent then
                        local tx = x - (sc.offsetX or 0)
                        local ty = y - (sc.offsetY or 0)
                        sc.downTarget:handleEvent(evt, tx, ty)
                    end
                end
            end
            if sc.dragging then
                local nx = sc.baseOffsetX + dx
                local ny = sc.baseOffsetY + dy
                if sc.direction == "vertical" then
                    if ny < minY then ny = minY end
                    if ny > maxY then ny = maxY end
                    sc.offsetY = ny
                elseif sc.direction == "horizontal" then
                    if nx < minX then nx = minX end
                    if nx > maxX then nx = maxX end
                    sc.offsetX = nx
                else -- both
                    if nx < minX then nx = minX end
                    if nx > maxX then nx = maxX end
                    if ny < minY then ny = minY end
                    if ny > maxY then ny = maxY end
                    sc.offsetX, sc.offsetY = nx, ny
                end
                return true
            end
            return true
        elseif evt == "SINGLE_TAP" or evt == "LONG_PRESS" then
            if sc.dragging then
                -- 滑动期间禁用点击；若启用分页，则在抬手时做“就近吸附”（无论是否触发 SWIPE）
                if sc.pagingEnabled and (sc.direction == "horizontal" or sc.direction == "both") then
                    local pageW = sc.pageWidth or self.w
                    local totalW = sc.contentWidth or self.w
                    local pages = math.max(1, math.floor((totalW + pageW - 1) / pageW))
                    local cur = math.floor((-(sc.offsetX or 0) + pageW / 2) / pageW)
                    if cur < 0 then cur = 0 end
                    if cur > pages - 1 then cur = pages - 1 end
                    sc.offsetX = -cur * pageW
                end
                sc.dragging = false
                sc.captured = false
                sc.downTarget = nil
                return true
            end
            -- 未拖拽：将事件分发给子组件（坐标转内容坐标）
            local tx = x - (sc.offsetX or 0)
            local ty = y - (sc.offsetY or 0)
            for i = #self.children, 1, -1 do
                local c = self.children[i]
                if c and c.enabled ~= false and c.handleEvent and 
                   hit_test(tx, ty, { x = c.x, y = c.y, w = c.w, h = c.h }) then
                    if c:handleEvent(evt, tx, ty) then sc.downTarget = nil return true end
                end
            end
            sc.downTarget = nil
            return true
        elseif evt == "SWIPE_LEFT" or evt == "SWIPE_RIGHT" or evt == "SWIPE_UP" or evt == "SWIPE_DOWN" then
            -- 抬手后的滑动手势：结束拖拽，并在需要时做分页吸附（仅横向）
            sc.dragging = false
            sc.captured = false
            if sc.pagingEnabled and (sc.direction == "horizontal" or sc.direction == "both") then
                local pageW = sc.pageWidth or self.w
                local totalW = sc.contentWidth or self.w
                local pages = math.max(1, math.floor((totalW + pageW - 1) / pageW))
                -- 当前页（offsetX 为负值向右移动内容）
                local cur = math.floor((-(sc.offsetX or 0) + pageW / 2) / pageW)
                if evt == "SWIPE_LEFT" then cur = cur + 1 elseif evt == "SWIPE_RIGHT" then cur = cur - 1 end
                if cur < 0 then cur = 0 end
                if cur > pages - 1 then cur = pages - 1 end
                sc.offsetX = -cur * pageW
            end
            return true
        else
            -- 其他事件（如 MOVE_X/SWIPE_*）在 0.1 版忽略或按需拦截
            return true
        end
    end
    -- 非滚动窗口：正常分发
    for i = #self.children, 1, -1 do
        local c = self.children[i]
        -- v1.6.1修复：添加_capture检查，让已捕获的组件（如按下的Button）能收到移出范围的MOVE事件
        if c and c.enabled ~= false and c.handleEvent and 
           (c._capture == true or hit_test(x, y, { x = c.x, y = c.y, w = c.w, h = c.h })) then
            if c:handleEvent(evt, x, y) then return true end
        end
    end
    return true -- 拦截窗口区域内未被子组件消费的事件
end

-- 启用简易滚动（0.1）
function Window:enableScroll(opts)
    opts = opts or {}
    self._scroll = {
        enabled = true,
        direction = opts.direction or "vertical",
        contentWidth = tonumber(opts.contentWidth or self.w) or self.w,
        contentHeight = tonumber(opts.contentHeight or self.h) or self.h,
        offsetX = 0,
        offsetY = 0,
        threshold = tonumber(opts.threshold or 10) or 10,
        pagingEnabled = not not opts.pagingEnabled,
        pageWidth = tonumber(opts.pageWidth or self.w) or self.w,
        dragging = false,
        captured = false,
    }
    return self
end

function Window:setContentSize(w, h)
    if not self._scroll then return end
    if w then self._scroll.contentWidth = tonumber(w) or self._scroll.contentWidth end
    if h then self._scroll.contentHeight = tonumber(h) or self._scroll.contentHeight end
end

-- 启用子页面管理
function Window:enableSubpageManager(opts)
    opts = opts or {}
    if not self._managed then
        self._managed = { 
            pages = {}, 
            backEventName = opts.backEventName or "NAV.BACK", 
            onBack = opts.onBack 
        }
        sys.subscribe(self._managed.backEventName, function()
            if self._managed.onBack then pcall(self._managed.onBack) end
            local anyVisible = false
            for _, pg in pairs(self._managed.pages) do
                if pg and pg.visible ~= false then anyVisible = true break end
            end
            if not anyVisible then
                self.visible = true
                self.enabled = true
            end
        end)
    end
    return self
end

-- 配置子页面工厂
function Window:configureSubpages(factories)
    if not self._managed then self:enableSubpageManager() end
    self._managed.factories = self._managed.factories or {}
    for k, v in pairs(factories or {}) do
        self._managed.factories[k] = v
    end
    return self
end

-- 显示子页面
function Window:showSubpage(name, factory)
    if not self._managed then error("enableSubpageManager must be called before showSubpage") end
    for key, pg in pairs(self._managed.pages) do
        if pg and pg.visible ~= false then
            pg.visible = false
            pg.enabled = false
        end
    end
    if not self._managed.pages[name] then
        local f = factory
        if not f and self._managed.factories then f = self._managed.factories[name] end
        if not f then error("no factory for subpage '" .. tostring(name) .. "'") end
        self._managed.pages[name] = f()
        self._managed.pages[name]._parentWindow = self
        core.add(self._managed.pages[name])
    end
    self.visible = false
    self._managed.pages[name].visible = true
    self._managed.pages[name].enabled = true
end

-- 返回上级页面
function Window:back()
    if self._parentWindow then
        self.visible = false
        self.enabled = false
        local parent = self._parentWindow
        local anyVisible = false
        if parent._managed and parent._managed.pages then
            for _, pg in pairs(parent._managed.pages) do
                if pg and pg.visible ~= false then anyVisible = true break end
            end
        end
        if not anyVisible then
            parent.visible = true
            parent.enabled = true
        end
    end
end

-- 关闭子页面
function Window:closeSubpage(name, opts)
    if not self._managed or not self._managed.pages then return false end
    opts = opts or {}
    local pg = self._managed.pages[name]
    if not pg then return false end
    pg.visible = false
    pg.enabled = false
    if opts.destroy == true then
        core.remove(pg)
        self._managed.pages[name] = nil
        collectgarbage("collect")
    end
    local anyVisible = false
    for _, p in pairs(self._managed.pages) do
        if p and p.visible ~= false then anyVisible = true break end
    end
    if not anyVisible then
        self.visible = true
        self.enabled = true
    end
    return true
end

-- ProgressBar组件 - 进度条，支持百分比显示和主题适配
local ProgressBar = {}
ProgressBar.__index = ProgressBar

function ProgressBar:new(opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    o.x = opts.x or 0
    o.y = opts.y or 0
    o.w = opts.width or opts.w or 200
    o.h = opts.height or opts.h or 24
    o.progress = math.max(0, math.min(100, opts.progress or 0))
    o.showPercentage = opts.showPercentage ~= false
    o.text = opts.text
    o.textSize = opts.textSize or opts.size
    local dark = (current_theme == "dark")
    o.backgroundColor = opts.backgroundColor or (dark and COLOR_GRAY or 0xC618)
    o.progressColor = opts.progressColor or (dark and COLOR_BLUE or 0x001F)
    o.borderColor = opts.borderColor or (dark and COLOR_WHITE or 0x8410)
    o.textColor = opts.textColor or (dark and COLOR_WHITE or COLOR_BLACK)
    o.visible = opts.visible ~= false
    o.enabled = opts.enabled ~= false
    return o
end

function ProgressBar:setProgress(value)
    self.progress = math.max(0, math.min(100, value))
end

function ProgressBar:getProgress()
    return self.progress
end

function ProgressBar:setText(text)
    self.text = text
end

function ProgressBar:draw()
    if not self.visible then return end
    
    -- 绘制背景（可选：只绘制内区，避免与边框重复像素）
    local padding = 1
    fill_rect(self.x + padding, self.y + padding, self.x + self.w - padding, self.y + self.h - padding, self.backgroundColor)
    
    -- 绘制边框
    stroke_rect(self.x, self.y, self.x + self.w, self.y + self.h, self.borderColor)
    
    -- 计算进度条填充
    padding = 1
    local inner_left = self.x + padding
    local inner_top = self.y + padding
    local inner_right = self.x + self.w - padding  -- 包含式
    local inner_bottom = self.y + self.h - padding -- 包含式
    local inner_width = inner_right - inner_left
    local fill_width = math.floor(inner_width * (self.progress / 100))
    if fill_width > 0 then
        local x1 = inner_left
        local x2 = inner_left + fill_width
        fill_rect(x1, inner_top, x2, inner_bottom, self.progressColor)
    end
    
    -- 绘制文本
    if self.showPercentage or self.text then
        local display_text = self.text or (self.progress .. "%")
        draw_text_in_rect_centered(self.x, self.y, self.w, self.h, display_text, {
            color = self.textColor,
            style = { size = self.textSize },
            padding = 2
        })
    end
end

function ProgressBar:handleEvent(evt, x, y)
    return false -- 进度条默认不处理触摸事件
end


-- ================================
-- 主模块导出
-- ================================

local M = {}

-- 核心API导出
M.init = core.init
M.add = core.add
M.remove = core.remove
M.clear = core.clear
M.render = core.render
M.handleTouchEvent = core.handleTouchEvent
M.debug = core.debug
M.getTheme = core.getTheme

-- 硬件支持
M.hw = hw

-- 事件系统
M.event = event

-- 组件构造函数
M.Button = function(opts) return Button:new(opts) end
M.CheckBox = function(opts) return CheckBox:new(opts) end
M.Label = function(opts) return Label:new(opts) end
M.Picture = function(opts) return Picture:new(opts) end
M.MessageBox = function(opts) return MessageBox:new(opts) end
M.Window = function(opts) return Window:new(opts) end
M.ProgressBar = function(opts) return ProgressBar:new(opts) end

-- 字体 API 导出
M.font = {
    set = function(style) return font_set(style) end,
    measure = function(text, style) return font_measure(text, style) end,
    lineHeight = function(style) return font_line_height(style) end
}

-- 对外导出常用颜色常量，便于在业务侧直接使用
M.COLOR_WHITE = COLOR_WHITE
M.COLOR_BLACK = COLOR_BLACK
M.COLOR_GRAY  = COLOR_GRAY
M.COLOR_BLUE  = COLOR_BLUE
M.COLOR_RED   = COLOR_RED
M.COLOR_GREEN = COLOR_GREEN
M.COLOR_YELLOW = COLOR_YELLOW
M.COLOR_CYAN = COLOR_CYAN
M.COLOR_MAGENTA = COLOR_MAGENTA
M.COLOR_ORANGE = COLOR_ORANGE
M.COLOR_PINK = COLOR_PINK
-- Windows 11 Light模式颜色
M.COLOR_WIN11_LIGHT_DIALOG_BG = COLOR_WIN11_LIGHT_DIALOG_BG
M.COLOR_WIN11_LIGHT_BUTTON_BG = COLOR_WIN11_LIGHT_BUTTON_BG
M.COLOR_WIN11_LIGHT_BUTTON_BORDER = COLOR_WIN11_LIGHT_BUTTON_BORDER
-- Windows 11 Dark模式颜色
M.COLOR_WIN11_DARK_DIALOG_BG = COLOR_WIN11_DARK_DIALOG_BG
M.COLOR_WIN11_DARK_BUTTON_BG = COLOR_WIN11_DARK_BUTTON_BG
M.COLOR_WIN11_DARK_BUTTON_BORDER = COLOR_WIN11_DARK_BUTTON_BORDER

return M