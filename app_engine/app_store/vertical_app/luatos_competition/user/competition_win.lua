--[[
@module  competition_win
@summary LuatOS知识竞赛页面
@version 1.0
@date    2026.03.31
@author  蒋骞
]]

local win_id = nil
local main_container
local ui_elements = {}

local thirty_questions = require("thirty_questions")

local DEFAULT_QUESTION_SET = {
    { id = 1, question = "LuatOS 是基于哪个开源实时操作系统内核开发的？", options = {"FreeRTOS", "RT-Thread", "LiteOS", "TencentOS tiny"}, answer = "B" },
    { id = 2, question = "LuatOS 二次开发主要使用什么脚本语言？", options = {"MicroPython", "JavaScript", "Lua", "C/C++"}, answer = "C" },
    { id = 3, question = "LuatOS 中，以下哪个函数用于延时（毫秒级）阻塞等待？", options = {"sys.wait()", "sys.timerStart()", "os.sleep()", "delayMs()"}, answer = "A" },
    { id = 4, question = "关于 Air724UG 模组，LuatOS 支持的 GPIO 电平逻辑是？", options = {"1.8V", "3.3V", "5V", "可配置 1.8V/3.3V"}, answer = "D" },
    { id = 5, question = "LuatOS 中，若想每 1 秒执行某任务，最推荐使用哪个函数？", options = {"sys.timerLoopStart()", "while true + sys.wait()", "定时器+协程", "task.wait(1000)"}, answer = "A" },
    { id = 6, question = "LuatOS 支持以下哪种网络协议栈？", options = {"TCP/IP", "MQTT", "HTTP", "以上都是"}, answer = "D" },
    { id = 7, question = "使用 LuatOS 开发时，以下哪个工具用于固件烧录？", options = {"Luatools", "ST-Link", "J-Link", "OpenOCD"}, answer = "A" },
    { id = 8, question = "LuatOS 中，下列哪个模块用于操作GPIO？", options = {"gpio", "pin", "io", "led"}, answer = "A" },
    { id = 9, question = "LuatOS 支持哪种通信协议进行AT指令交互？", options = {"UART", "I2C", "SPI", "CAN"}, answer = "A" },
    { id = 10, question = "LuatOS 中，使用哪个函数创建协程任务？", options = {"sys.taskInit()", "coroutine.create()", "task.new()", "thread.start()"}, answer = "A" }
}

local QUESTION_SET = DEFAULT_QUESTION_SET
local ALL_QUESTIONS = {}

local SCORE_PER_QUESTION = 10
local user_answers = {}
local question_status = {}
local current_index = 1
local current_score = 0

local function init_random_seed()
    math.randomseed(os.time() or 12345)
    for i = 1, 10 do
        math.random()
    end
end

local function refresh_questions()
    if ALL_QUESTIONS and #ALL_QUESTIONS >= 10 then
        local indices = {}
        for i = 1, #ALL_QUESTIONS do
            indices[i] = i
        end
        
        for i = 1, 10 do
            local randomPos = math.random(i, #indices)
            indices[i], indices[randomPos] = indices[randomPos], indices[i]
        end
        
        local selected = {}
        for i = 1, 10 do
            table.insert(selected, ALL_QUESTIONS[indices[i]])
        end
        
        QUESTION_SET = selected
        log.info("dictionary_win", "从已加载的题库中随机抽取了10道题")
        return true
    else
        log.warn("dictionary_win", "题库不足，使用默认题库")
        QUESTION_SET = DEFAULT_QUESTION_SET
        return false
    end
end

local function load_questions_from_feishu(callback)
    log.info("dictionary_win", "正在从飞书获取题库...")
    
    sys.taskInit(function()
        local questions = thirty_questions.fetchQuestions()
        
        if questions and #questions > 0 then
            ALL_QUESTIONS = questions
            refresh_questions()
            log.info("dictionary_win", "成功从数据库中获取", #questions, "道题目，已随机抽取10道")
            if callback then callback(true) end
        else
            log.warn("dictionary_win", "飞书题库获取失败，使用默认题库")
            ALL_QUESTIONS = DEFAULT_QUESTION_SET
            QUESTION_SET = DEFAULT_QUESTION_SET
            if callback then callback(false) end
        end
    end)
end

local function init_state()
    user_answers = {}
    question_status = {}
    current_index = 1
    current_score = 0
    for i = 1, #QUESTION_SET do
        user_answers[i] = nil
        question_status[i] = false
    end
end

local function clear_container()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    ui_elements = {}
end

local function calculate_score()
    local score = 0
    for i = 1, #QUESTION_SET do
        if user_answers[i] and user_answers[i] == QUESTION_SET[i].answer then
            score = score + SCORE_PER_QUESTION
        end
    end
    current_score = score
end

local create_quiz_page
local create_home_page
local create_result_page
local create_loading_page

function create_loading_page()
    clear_container()
    
    main_container = airui.container({ parent = airui.screen, x = 0, y = 0, w = 480, h = 800, color = 0x0a0f1e })
    
    airui.label({
        parent = main_container,
        x = 0, y = 360, w = 480, h = 80,
        text = "正在加载题库...",
        font_size = 28,
        color = 0x7bc5ff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    sys.taskInit(function()
        init_random_seed()
        load_questions_from_feishu(function(success)
            sys.wait(500)
            create_home_page()
        end)
    end)
end

function create_quiz_page()
    clear_container()
    
    main_container = airui.container({ parent = airui.screen, x = 0, y = 0, w = 480, h = 800, color = 0x0a0f1e })
    
    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0, w = 480, h = 80,
        color = 0x0a1428
    })
    
    ui_elements.question_counter = airui.label({
        parent = title_bar,
        x = 24, y = 24, w = 80, h = 32,
        text = current_index .. "/" .. #QUESTION_SET,
        font_size = 18,
        color = 0x64b4ff,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    ui_elements.score_display = airui.label({
        parent = title_bar,
        x = 320, y = 24, w = 80, h = 32,
        text = "得分: " .. current_score,
        font_size = 18,
        color = 0xffd966,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    airui.label({
        parent = title_bar,
        x = 80, y = 24, w = 220, h = 32,
        text = ">.<LuatOS知识闯关>.<",
        font_size = 20,
        color = 0xe0f0ff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local exit_btn = airui.container({
        parent = title_bar,
        x = 400, y = 20, w = 60, h = 40,
        color = 0xc83c3c,
        on_click = function()
            create_home_page()
        end
    })
    
    airui.label({
        parent = exit_btn,
        x = 0, y = 8, w = 60, h = 24,
        text = "退出",
        font_size = 16,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local question_area = airui.container({
        parent = main_container,
        x = 0, y = 80, w = 480, h = 620,
        color = 0x0a0f1e
    })
    
    ui_elements.question_text = airui.label({
        parent = question_area,
        x = 24, y = 30, w = 432, h = 100,
        text = QUESTION_SET[current_index].question,
        font_size = 20,
        color = 0xeef5ff,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    if question_status[current_index] then
        local correct_answer = QUESTION_SET[current_index].answer
        airui.label({
            parent = question_area,
            x = 24, y = 140, w = 432, h = 30,
            text = "正确答案：" .. correct_answer,
            font_size = 18,
            color = 0xffd700,
            align = airui.TEXT_ALIGN_LEFT
        })
    end
    
    local options = QUESTION_SET[current_index].options
    local letters = {"A", "B", "C", "D"}
    ui_elements.option_items = {}
    
    local base_option_height = 100
    local base_spacing = 110
    local current_y = 180
    
    for i = 1, 4 do
        local x = 24
        local y = current_y
        local letter = letters[i]
        
        local function normalize_answer(ans)
            if not ans then return "" end
            ans = string.upper(ans:match("^%s*(.-)%s*$") or "")
            if ans:match("^[ABCD]$") then
                return ans
            elseif ans:match("^[1-4]$") then
                return string.char(64 + tonumber(ans))
            end
            return ans
        end
        
        local correct_answer = normalize_answer(QUESTION_SET[current_index].answer)
        local user_answer = user_answers[current_index]
        local option_text = options[i]
        
        log.info("competition_win", string.format("题目: %s, 当前选项: %s, 正确答案: %s", 
            QUESTION_SET[current_index].question:sub(1, 30), 
            letter, correct_answer))
        
        local text_length = #option_text
        local option_height = base_option_height
        if text_length > 20 then
            option_height = base_option_height + 20
        elseif text_length > 35 then
            option_height = base_option_height + 40
        end
        
        local bg_color = 0x142341
        if question_status[current_index] then
            if letter == correct_answer then
                bg_color = 0x2d8a3a
            elseif user_answer == letter then
                bg_color = 0x8a3d3d
            end
        elseif user_answer == letter then
            bg_color = 0x2d4a3a
        end
        
        local option_item = airui.container({
            parent = question_area,
            x = x, y = y, w = 432, h = option_height,
            color = bg_color,
            on_click = function()
                if not question_status[current_index] then
                    user_answers[current_index] = letter
                    create_quiz_page()
                end
            end
        })
        
        local prefix_y = (option_height - 40) / 2
        local option_prefix = airui.container({
            parent = option_item,
            x = 16, y = prefix_y, w = 40, h = 40,
            color = 0x000000
        })
        
        airui.label({
            parent = option_prefix,
            x = 0, y = 8, w = 40, h = 24,
            text = letter,
            font_size = 20,
            color = 0xb8d0ff,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        local text_y = (option_height - 24) / 2
        local text_h = option_height
        airui.label({
            parent = option_item,
            -- x = 68, y = text_y, w = 348, h = 24,
            x = 68, y = text_y, w = 348, h = text_h,
            text = option_text,
            font_size = 18,
            color = 0xcfdfff,
            align = airui.TEXT_ALIGN_LEFT
        })
        
        ui_elements.option_items[i] = option_item
        current_y = current_y + option_height + 10
    end
    
    local footer_bar = airui.container({
        parent = main_container,
        x = 0, y = 700, w = 480, h = 100,
        color = 0x08101e
    })
    
    local is_review_mode = question_status[current_index]
    
    local prev_btn = airui.container({
        parent = footer_bar,
        x = 30, y = 25, w = 100, h = 50,
        color = 0x1e3250,
        on_click = function()
            if current_index > 1 then
                current_index = current_index - 1
                create_quiz_page()
            end
        end
    })
    
    airui.label({
        parent = prev_btn,
        x = 0, y = 14, w = 100, h = 22,
        text = "<< 上一题",
        font_size = 16,
        color = 0xc0e0ff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    if is_review_mode then
        local back_btn = airui.container({
            parent = footer_bar,
            x = 350, y = 25, w = 100, h = 50,
            color = 0x8a3d3d,
            on_click = function()
                create_result_page()
            end
        })
        
        airui.label({
            parent = back_btn,
            x = 0, y = 14, w = 100, h = 22,
            text = "得分",
            font_size = 16,
            color = 0xffffff,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
    
    if not is_review_mode then
        local confirm_btn = airui.container({
            parent = footer_bar,
            x = 190, y = 25, w = 100, h = 50,
            color = 0x1a6dd4,
            on_click = function()
                if user_answers[current_index] and not question_status[current_index] then
                    question_status[current_index] = true
                    calculate_score()
                    if current_index == #QUESTION_SET then
                        create_quiz_page()
                        sys.taskInit(function()
                            sys.wait(2000)
                            create_result_page()
                        end)
                    else
                        create_quiz_page()
                    end
                end
            end
        })
        
        airui.label({
            parent = confirm_btn,
            x = 0, y = 14, w = 100, h = 22,
            text = "确认",
            font_size = 18,
            color = 0xffffff,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
    
    local next_btn = airui.container({
        parent = footer_bar,
        x = is_review_mode and 190 or 350, y = 25, w = 100, h = 50,
        color = 0x1e3250,
        on_click = function()
            if current_index < #QUESTION_SET then
                current_index = current_index + 1
                create_quiz_page()
            end
        end
    })
    
    airui.label({
        parent = next_btn,
        x = 0, y = 14, w = 100, h = 22,
        text = "下一题 >>",
        font_size = 16,
        color = 0xc0e0ff,
        align = airui.TEXT_ALIGN_CENTER
    })
end

function create_home_page()
    clear_container()
    
    main_container = airui.container({ parent = airui.screen, x = 0, y = 0, w = 480, h = 800, color = 0x0a0f1e })
    
    local logo_container = airui.container({
        parent = main_container,
        x = 0, y = 0, w = 480, h = 800,
        color = 0x0a0f1e
    })
    
    local logo_icon = airui.container({
        parent = logo_container,
        x = 170, y = 150, w = 140, h = 140,
        color = 0x1a6dd4
    })
    
    airui.label({
        parent = logo_icon,
        x = 0, y = 48, w = 140, h = 44,
        text = "竞答",
        font_size = 42,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    airui.label({
        parent = logo_container,
        x = 0, y = 320, w = 480, h = 60,
        text = "LuatOS知识竞答",
        font_size = 36,
        color = 0x7bc5ff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    airui.label({
        parent = logo_container,
        x = 0, y = 400, w = 480, h = 30,
        text = "题目数量: " .. #QUESTION_SET,
        font_size = 18,
        color = 0x99ccff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local start_btn = airui.container({
        parent = logo_container,
        x = 140, y = 480, w = 200, h = 70,
        color = 0x1a6dd4,
        on_click = function()
            log.info("dictionary_win", "开始答题按钮被点击")
            refresh_questions()
            init_state()
            create_quiz_page()
        end
    })
    
    airui.label({
        parent = start_btn,
        x = 0, y = 20, w = 200, h = 30,
        text = "开始答题",
        font_size = 24,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local refresh_btn = airui.container({
        parent = logo_container,
        x = 140, y = 580, w = 200, h = 70,
        color = 0x2d4a3a,
        on_click = function()
            log.info("dictionary_win", "刷新题库按钮被点击")
            create_loading_page()
        end
    })
    
    airui.label({
        parent = refresh_btn,
        x = 0, y = 20, w = 200, h = 26,
        text = "刷新题库",
        font_size = 18,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    local backhome_btn = airui.container({
        parent = logo_container,
        x = 140, y = 680, w = 200, h = 70,
        color = 0x2d4a3a,
        on_click = function()
            log.info("dictionary_win", "返回主界面按钮被点击")
            if win_id then 
                exwin.close(win_id)
            end
        end
    })
    
    airui.label({
        parent = backhome_btn,
        x = 0, y = 20, w = 200, h = 26,
        text = "返回主界面",
        font_size = 18,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
end

function create_result_page()
    clear_container()
    
    main_container = airui.container({ parent = airui.screen, x = 0, y = 0, w = 480, h = 800, color = 0x0a0f1e })
    
    local result_container = airui.container({
        parent = main_container,
        x = 0, y = 0, w = 480, h = 800,
        color = 0x0a0f1e
    })
    
    local stars_text = ""
    if current_score <= 60 then
        stars_text = "T_T"
    elseif current_score < 80 then
        stars_text = "-v-"
    else
        stars_text = ">v<"
    end
    
    airui.label({
        parent = result_container,
        x = 0, y = 120, w = 480, h = 100,
        text = stars_text,
        font_size = 72,
        color = 0xffd700,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local score_color = 0xff4444
    if current_score <= 60 then
        score_color = 0xffd700
    elseif current_score < 80 then
        score_color = 0xff8c42
    end
    
    airui.label({
        parent = result_container,
        x = 0, y = 260, w = 480, h = 120,
        text = current_score .. "分",
        font_size = 86,
        color = score_color,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local message = "再接再厉！"
    if current_score <= 60 then
        message = "再接再厉！"
    elseif current_score < 80 then
        message = "不错哟！"
    else
        message = "太厉害啦！"
    end
    
    airui.label({
        parent = result_container,
        x = 0, y = 420, w = 480, h = 50,
        text = message,
        font_size = 28,
        color = 0xe0f0ff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local review_btn = airui.container({
        parent = result_container,
        x = 40, y = 550, w = 120, h = 60,
        color = 0x2d4a3a,
        on_click = function()
            log.info("dictionary_win", "巩固知识按钮被点击")
            current_index = 1
            create_quiz_page()
        end
    })
    
    airui.label({
        parent = review_btn,
        x = 0, y = 16, w = 120, h = 28,
        text = "巩固知识",
        font_size = 18,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local continue_btn = airui.container({
        parent = result_container,
        x = 180, y = 550, w = 120, h = 60,
        color = 0x1a6dd4,
        on_click = function()
            log.info("dictionary_win", "继续闯关按钮被点击")
            refresh_questions()
            init_state()
            create_quiz_page()
        end
    })
    
    airui.label({
        parent = continue_btn,
        x = 0, y = 16, w = 120, h = 28,
        text = "继续闯关",
        font_size = 18,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local home_btn = airui.container({
        parent = result_container,
        x = 320, y = 550, w = 120, h = 60,
        color = 0x1a6dd4,
        on_click = function()
            log.info("dictionary_win", "返回首页按钮被点击")
            create_home_page()
        end
    })
    
    airui.label({
        parent = home_btn,
        x = 0, y = 16, w = 120, h = 28,
        text = "返回首页",
        font_size = 18,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
end

local function on_create()
    create_loading_page()
end

local function on_destroy()
    clear_container()
    win_id = nil
end

local function open_dictionary()
    if win_id then
        exwin.close(win_id)
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = function()
        end,
        on_lose_focus = function()
        end
    })
end

sys.subscribe("OPEN_COMPETITION_WIN", open_dictionary)

return {
    open = open_dictionary,
    refresh = function()
        create_loading_page()
    end
}

