--[[
@module  word_builder_win
@summary 背单词应用窗口模块
@version 1.0
@date    2026.04.20
@author  杨乔杉
]]

local exwin = exwin
if not exwin then
    log.error("word_builder", "exwin is nil")
    return
end

local win_id = nil
local main_container = nil
local current_word_index = 1
local correct_count = 0
local wrong_count = 0
local current_mode = "study"
local word_list = {}
local word_loader = require "word_loader"
local is_processing = false

math.randomseed(os.time())

-- 颜色配置
local COLORS = {
    BACKGROUND = 0xf5f5f5,
    TITLE_BAR = 0x4CAF50,
    WHITE = 0xffffff,
    TEXT_WHITE = 0xffffff,
    TEXT_PRIMARY = 0x333333,
    PRIMARY = 0x2196F3,
    GRAY = 0x757575,
    SECONDARY = 0xFF9800,
    CORRECT = 0x00ff00,
    WRONG = 0xff0000
}

-- 基准分辨率（设计稿尺寸）
local BASE_WIDTH = 320
local BASE_HEIGHT = 480

-- 实际屏幕尺寸
local SCREEN_WIDTH = 320
local SCREEN_HEIGHT = 480

-- 缩放因子
local SCALE_X = 1.0
local SCALE_Y = 1.0

-- 应用配置
local CONFIG = {
    TEST_WORD_COUNT = 30,
    AUTO_NEXT_DELAY = 1500,
    OPTION_BTN_WIDTH = 200,
    OPTION_BTN_HEIGHT = 40,
    OPTION_BTN_GAP_X = 20,
    OPTION_BTN_GAP_Y = 20,
    OPTION_BTN_START_X = 10,
    OPTION_BTN_START_Y = 15
}

-- 初始化屏幕尺寸
local function init_screen_size()
    -- 使用 lcd.getSize() 获取屏幕尺寸
    if lcd and lcd.getSize then
        local size = lcd.getSize()
        if size and size.w and size.h then
            SCREEN_WIDTH = size.w
            SCREEN_HEIGHT = size.h
        end
    end
    
    SCALE_X = SCREEN_WIDTH / BASE_WIDTH
    SCALE_Y = SCREEN_HEIGHT / BASE_HEIGHT
    log.info("word_builder", "Screen size: " .. SCREEN_WIDTH .. "x" .. SCREEN_HEIGHT)
    log.info("word_builder", "Scale factors: " .. SCALE_X .. "x" .. SCALE_Y)
end

-- 根据基准值计算自适应值
local function scale_x(value)
    return math.floor(value * SCALE_X)
end

local function scale_y(value)
    return math.floor(value * SCALE_Y)
end

-- 根据基准值计算自适应字体大小
local function scale_font(size)
    return math.max(10, math.floor(size * math.min(SCALE_X, SCALE_Y)))
end

local function adjust_word_font(word_text)
    local font_size = 36
    if #word_text > 15 then
        font_size = 24
    elseif #word_text > 20 then
        font_size = 18
    end
    return font_size
end

local function copy_array(t)
    local result = {}
    for i, v in ipairs(t) do
        result[i] = v
    end
    return result
end

local function create_button(parent, x, y, width, height, text, bg_color, text_color, on_click)
    return airui.button({
        parent = parent,
        x = x, y = y,
        w = width, h = height,
        text = text,
        font_size = scale_font(16),
        style = {
            bg_color = bg_color,
            text_color = text_color,
            border_width = 0,
            radius = 5,
        },
        on_click = on_click
    })
end

local function init_word_list(mode)
    if mode == "test" then
        return word_loader.get_random_words(CONFIG.TEST_WORD_COUNT)
    else
        return word_loader.shuffle(word_loader.get_all_words())
    end
end

local function show_message(title, text, buttons, on_action)
    airui.msgbox({
        title = title,
        text = text,
        buttons = buttons or { "确定" },
        on_action = function(self, label)
            self:hide()
            if on_action then
                on_action(label)
            end
        end
    })
end

local word_label, phonetic_label, meaning_label, answer_container, mode_label, progress_label
local option_buttons = {}

local function update_progress()
    local total = #word_list
    local accuracy = 0
    if correct_count + wrong_count > 0 then
        accuracy = math.floor(correct_count / (correct_count + wrong_count) * 100)
    end
    local text = string.format("进度: %d/%d | 正确: %d | 错误: %d | 正确率: %d%%", 
        current_word_index, total, correct_count, wrong_count, accuracy)
    
    if progress_label then
        progress_label:set_text(text)
    end
end

local function clear_option_buttons()
    if option_buttons then
        for i = #option_buttons, 1, -1 do
            local btn = option_buttons[i]
            if btn and btn.destroy then
                btn:destroy()
            end
            table.remove(option_buttons, i)
        end
        option_buttons = {}
    end
end

local function generate_options(correct_word)
    local options = {correct_word}
    local all_words = word_loader.get_all_words()
    local used_words = {[correct_word] = true}
    local max_attempts = 100
    local attempts = 0
    
    while #options < 4 and attempts < max_attempts and #all_words > 0 do
        attempts = attempts + 1
        local idx = math.random(#all_words)
        local word_item = all_words[idx]
        if word_item and word_item.word and not used_words[word_item.word] then
            table.insert(options, word_item.word)
            used_words[word_item.word] = true
        end
    end
    
    return word_loader.shuffle(options)
end

local function show_current_word()
    local word = word_list[current_word_index]
    
    if not word then
        word_label:set_text("暂无单词")
        phonetic_label:set_text("")
        meaning_label:set_text("请添加单词后再开始学习")
        return
    end
    
    -- 公共操作
    meaning_label:set_text("释义: " .. word.meaning)
    answer_container:set_color(current_mode == "study" and COLORS.BACKGROUND or COLORS.WHITE)
    clear_option_buttons()
    
    if current_mode == "study" then
        local font_size = adjust_word_font(word.word)
        word_label:set_font_size(font_size)
        word_label:set_color(COLORS.TITLE_BAR)
        word_label:set_text(word.word)
        phonetic_label:set_text(word.phonetic)
    else
        word_label:set_color(COLORS.TITLE_BAR)
        word_label:set_text("请选择正确的单词")
        phonetic_label:set_text("")
    end
end

local function update_option_buttons(word)
    if not word then
        clear_option_buttons()
        return
    end
    local options = generate_options(word.word)
    
    -- 计算自适应的选项按钮尺寸
    local opt_btn_width = scale_x(CONFIG.OPTION_BTN_WIDTH)
    local opt_btn_height = scale_y(CONFIG.OPTION_BTN_HEIGHT)
    local opt_btn_gap_x = scale_x(CONFIG.OPTION_BTN_GAP_X)
    local opt_btn_gap_y = scale_y(CONFIG.OPTION_BTN_GAP_Y)
    local opt_btn_start_x = scale_x(CONFIG.OPTION_BTN_START_X)
    local opt_btn_start_y = scale_y(CONFIG.OPTION_BTN_START_Y)
    
    for i = 1, #options do
        local opt = options[i]
        if option_buttons[i] then
            option_buttons[i]:set_text(opt)
            option_buttons[i]:set_clickable(true)
        else
            local row = math.floor((i-1)/2)
            local col = (i-1)%2
            local x = opt_btn_start_x + col * (opt_btn_width + opt_btn_gap_x)
            local y = opt_btn_start_y + row * (opt_btn_height + opt_btn_gap_y)
            
            local btn = airui.button({
                parent = answer_container,
                x = x, y = y,
                w = opt_btn_width, 
                h = opt_btn_height,
                text = opt,
                font_size = scale_font(14),
                style = {
                    bg_color = COLORS.PRIMARY,
                    text_color = COLORS.TEXT_WHITE,
                    border_width = 0,
                    radius = 5
                },
                on_click = function()
                    if is_processing then return end
                    local current_word = word_list[current_word_index]
                    if not current_word then return end
                    is_processing = true
                    
                    for _, b in ipairs(option_buttons) do
                        if b.set_clickable then
                            b:set_clickable(false)
                        end
                    end
                    
                    local is_correct = opt == current_word.word
                    
                    if is_correct then
                        correct_count = correct_count + 1
                        word_label:set_text("正确！")
                        word_label:set_color(COLORS.CORRECT)
                    else
                        wrong_count = wrong_count + 1
                        word_label:set_text("错误！正确答案: " .. current_word.word)
                        word_label:set_color(COLORS.WRONG)
                    end
                    update_progress()
                    
                    sys.timerStart(function()
                        is_processing = false
                        if current_word_index < #word_list then
                            current_word_index = current_word_index + 1
                            show_current_word()
                            update_option_buttons(word_list[current_word_index])
                        else
                            show_message("完成", "恭喜完成所有测试！\n正确: " .. correct_count .. " | 错误: " .. wrong_count, {"确定"})
                        end
                    end, CONFIG.AUTO_NEXT_DELAY)
                end
            })
            table.insert(option_buttons, btn)
        end
    end
end

local function navigate_word(offset)
    if #word_list == 0 then
        return
    end
    local new_index = current_word_index + offset
    if new_index >= 1 and new_index <= #word_list then
        current_word_index = new_index
        show_current_word()
        update_progress()
    end
end

local function prev_word()
    navigate_word(-1)
end

local function next_word()
    navigate_word(1)
end

local function switch_mode(mode)
    current_mode = mode
    current_word_index = 1
    correct_count = 0
    wrong_count = 0
    word_list = init_word_list(mode)
    
    if mode_label then
        mode_label:set_text("模式: " .. (current_mode == "study" and "学习" or "测试"))
    end
    
    show_current_word()
    if current_mode == "test" and #word_list > 0 then
        update_option_buttons(word_list[current_word_index])
    else
        clear_option_buttons()
    end
    update_progress()
end

local function create_ui()
    -- 初始化屏幕尺寸
    init_screen_size()
    
    -- 使用自适应尺寸
    local padding = scale_x(15)
    local title_bar_height = scale_y(50)
    local word_container_height = scale_y(120)
    local answer_container_height = scale_y(120)
    local nav_container_height = scale_y(55)
    local bottom_bar_height = scale_y(55)
    local button_height = scale_y(38)
    local button_width = scale_x(80)
    local button_gap = scale_x(25)
    
    main_container = airui.container({ x = 0, y = 0, w = SCREEN_WIDTH, h = SCREEN_HEIGHT, color = COLORS.BACKGROUND, parent = airui.screen })
    
    local title_bar = airui.container({ parent = main_container, x = 0, y = 0, w = SCREEN_WIDTH, h = title_bar_height, color = COLORS.TITLE_BAR })
    airui.label({ parent = title_bar, x = padding, y = scale_y(8), w = scale_x(150), h = scale_y(35), text = "背单词", font_size = scale_font(26), color = COLORS.TEXT_WHITE })
    mode_label = airui.label({ parent = title_bar, x = SCREEN_WIDTH - scale_x(100), y = scale_y(12), w = scale_x(100), h = scale_y(25), text = "模式: " .. (current_mode == "study" and "学习" or "测试"), font_size = scale_font(14), color = COLORS.TEXT_WHITE })
    
    progress_label = airui.label({ parent = main_container, x = padding, y = title_bar_height + scale_y(15), w = SCREEN_WIDTH - padding * 2, h = scale_y(20), text = "", font_size = scale_font(12), color = COLORS.TEXT_PRIMARY })
    
    local word_container = airui.container({ parent = main_container, x = padding, y = title_bar_height + scale_y(35), w = SCREEN_WIDTH - padding * 2, h = word_container_height, color = COLORS.WHITE, radius = 5 })
    word_label = airui.label({ parent = word_container, x = scale_x(10), y = scale_y(15), w = word_container.w - scale_x(20), h = scale_y(45), text = "", font_size = scale_font(28), color = COLORS.TITLE_BAR, align = 2 })
    phonetic_label = airui.label({ parent = word_container, x = 0, y = scale_y(60), w = word_container.w, h = scale_y(20), text = "", font_size = scale_font(14), color = COLORS.GRAY, align = 2 })
    meaning_label = airui.label({ parent = word_container, x = scale_x(10), y = scale_y(80), w = word_container.w - scale_x(20), h = scale_y(35), text = "", font_size = scale_font(14), color = COLORS.TEXT_PRIMARY, align = 2 })
    
    local answer_y = title_bar_height + scale_y(35) + word_container_height + scale_y(10)
    answer_container = airui.container({ parent = main_container, x = padding, y = answer_y, w = SCREEN_WIDTH - padding * 2, h = answer_container_height, color = COLORS.WHITE, radius = 5 })
    
    local nav_y = answer_y + answer_container_height + scale_y(10)
    local nav_container = airui.container({ parent = main_container, x = padding, y = nav_y, w = SCREEN_WIDTH - padding * 2, h = nav_container_height, color = COLORS.WHITE, radius = 5 })
    local nav_btn_x = scale_x(10)
    create_button(nav_container, nav_btn_x, scale_y(8), button_width, button_height, "上一个", COLORS.GRAY, COLORS.TEXT_WHITE, prev_word)
    create_button(nav_container, nav_btn_x + button_width + button_gap, scale_y(8), button_width, button_height, "下一个", COLORS.PRIMARY, COLORS.TEXT_WHITE, next_word)
    create_button(nav_container, nav_btn_x + button_width * 2 + button_gap * 2, scale_y(8), button_width, button_height, "切换", COLORS.SECONDARY, COLORS.TEXT_WHITE, function()
        switch_mode(current_mode == "study" and "test" or "study")
    end)
    
    local bottom_bar = airui.container({ parent = main_container, x = 0, y = SCREEN_HEIGHT - bottom_bar_height, w = SCREEN_WIDTH, h = bottom_bar_height, color = COLORS.WHITE })
    local bottom_btn_width = (SCREEN_WIDTH - scale_x(50)) / 2
    create_button(bottom_bar, padding, scale_y(8), bottom_btn_width, button_height, "重新开始", COLORS.PRIMARY, COLORS.TEXT_WHITE, function()
        switch_mode(current_mode)
    end)
    create_button(bottom_bar, padding + bottom_btn_width + scale_x(20), scale_y(8), bottom_btn_width, button_height, "返回首页", COLORS.GRAY, COLORS.TEXT_WHITE, function()
        exwin.close(win_id)
    end)
    
    word_list = init_word_list(current_mode)
    show_current_word()
    if current_mode == "test" and #word_list > 0 then
        update_option_buttons(word_list[current_word_index])
    else
        clear_option_buttons()
    end
    update_progress()
end

local function on_create()
    local word_count = word_loader.load("/luadb/words.txt")
    log.info("word_builder", "Loaded " .. word_count .. " words on startup")
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    word_list = {}
    current_word_index = 1
    correct_count = 0
    wrong_count = 0
    
    if exapp and exapp.close then
        exapp.close()
    end
end

local function on_get_focus()
end

local function on_lose_focus()
end

sys.subscribe("OPEN_WORD_BUILDER_WIN", function()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end)
