--[[
@module  vending_machine_win
@summary 诗词填空游戏页面模块
@version 1.0
@date    2026.04.07
@author  LuatOS
]]

-- 全局变量定义
local win_id = nil            -- 窗口ID
local main_container, content -- 主容器和内容容器
local currentIndex = 0        -- 当前题目索引
local score = 0               -- 得分

-- 记录各题目的回答状态
local answeredStatus = { false, false, false, false, false, false, false, false, false, false }
local selectedOptionIndex = -1  -- 当前选中的选项索引
local quizCompletedFlag = false -- 答题完成标志
local feedbackMsg = ""          -- 反馈信息
local feedbackType = "neutral"  -- 反馈类型：neutral, correct, wrong
local exwin = require "exwin"

-- 诗词题库
local POEMS_DB = {
    {
        id = 1,
        stem = "床前明月光，________",
        correctAnswer = "疑是地上霜",
        options = { "疑似地上霜", "疑是地上霜", "低头思故乡", "处处闻啼鸟" },
        hint = "李白《静夜思》经典下句"
    },
    {
        id = 2,
        stem = "欲穷千里目，________",
        correctAnswer = "更上一层楼",
        options = { "更上一层楼", "黄河入海流", "山穷水复疑无路", "行到水穷处" },
        hint = "王之涣·登鹳雀楼"
    },
    {
        id = 3,
        stem = "春眠不觉晓，________",
        correctAnswer = "处处闻啼鸟",
        options = { "夜来风雨声", "处处闻啼鸟", "花落知多少", "鸟鸣山更幽" },
        hint = "孟浩然《春晓》次句"
    },
    {
        id = 4,
        stem = "锄禾日当午，________",
        correctAnswer = "汗滴禾下土",
        options = { "粒粒皆辛苦", "汗滴禾下土", "春种一粒粟", "秋收万颗子" },
        hint = "李绅《悯农》"
    },
    {
        id = 5,
        stem = "野火烧不尽，________",
        correctAnswer = "春风吹又生",
        options = { "一岁一枯荣", "春风吹又生", "离离原上草", "萋萋满别情" },
        hint = "白居易·赋得古原草送别"
    },
    {
        id = 6,
        stem = "举头望明月，________",
        correctAnswer = "低头思故乡",
        options = { "疑是地上霜", "低头思故乡", "对影成三人", "月是故乡明" },
        hint = "李白《静夜思》尾联"
    },
    {
        id = 7,
        stem = "采菊东篱下，________",
        correctAnswer = "悠然见南山",
        options = { "悠然见南山", "性本爱丘山", "此中有真意", "山气日夕佳" },
        hint = "陶渊明·饮酒其五"
    },
    {
        id = 8,
        stem = "大漠沙如雪，________",
        correctAnswer = "燕山月似钩",
        options = { "燕山月似钩", "沙场秋点兵", "青海长云暗雪山", "黄沙百战穿金甲" },
        hint = "李贺·马诗"
    },
    {
        id = 9,
        stem = "小荷才露尖尖角，________",
        correctAnswer = "早有蜻蜓立上头",
        options = { "早有蜻蜓立上头", "映日荷花别样红", "荷尽已无擎雨盖", "接天莲叶无穷碧" },
        hint = "杨万里·小池"
    },
    {
        id = 10,
        stem = "问君能有几多愁？________",
        correctAnswer = "恰似一江春水向东流",
        options = { "恰似一江春水向东流", "一江春水向东流", "流到瓜洲古渡头", "人生长恨水长东" },
        hint = "李煜·虞美人"
    }
}

--[[
标准化文本
@function normalizeText
@param str string 原始文本
@return string 标准化后的文本
@description 移除标点符号和空格，并转换为小写
]]
local function normalizeText(str)
if not str then return "" end
local result = str:gsub("[，,。？?！!；;：”“''‘’《》【】（）·～—%s]", ""):lower()
end
--[[
检查答案是否正确
@function isAnswerCorrect
@param question table 题目信息
@param selectedOptText string 选中的选项文本
@return boolean 是否正确
@description 标准化后比较答案
]]
local function isAnswerCorrect(question, selectedOptText)
    if not selectedOptText then return false end
    local normalizedSelected = normalizeText(selectedOptText)
    local normalizedCorrect = normalizeText(question.correctAnswer)
    return normalizedSelected == normalizedCorrect
end

--[[
检查是否所有题目都已完成
@function isAllCompleted
@return boolean 是否全部完成
@description 检查answeredStatus数组是否全为true
]]
local function isAllCompleted()
    for _, v in ipairs(answeredStatus) do
        if not v then return false end
    end
    return true
end

--[[
移动到下一个未回答的题目
@function moveToNextUnanswered
@return number 下一个未回答的题目索引
@description 从当前位置开始寻找，找不到则从开头寻找
]]
local function moveToNextUnanswered()
    -- 从当前位置之后寻找
    for i = currentIndex + 1, #POEMS_DB do
        if not answeredStatus[i] then
            return i
        end
    end
    -- 从开头寻找
    for i = 1, currentIndex do
        if not answeredStatus[i] then
            return i
        end
    end
    return -1 -- 所有题目都已回答
end

--[[
重置选择状态
@function resetSelection
@description 重置选中选项、反馈信息和反馈类型
]]
local function resetSelection()
    selectedOptionIndex = -1
    feedbackMsg = ""
    feedbackType = "neutral"
end

--[[
创建UI界面
@function create_ui
@description 创建主容器、顶部栏、退出按钮等UI元素
]]
local function create_ui()
    -- 创建主容器
    main_container = airui.container({ parent = airui.screen, x = 0, y = 0, w = 480, h = 800, color = 0xfef5e7 })

    -- 顶部装饰栏
    local top_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 50, color = 0xe5d5bb })
    airui.label({
        parent = top_bar,
        x = 50,
        y = 20,
        w = 200,
        h = 30,
        text = "诗词填空·选韵",
        font_size = 18,
        color = 0x5a3e2a
    })
    airui.label({
        parent = top_bar,
        x = 300,
        y = 20,
        w = 160,
        h = 30,
        text = "翰林院",
        font_size = 18,
        color = 0x5a3e2a,
        align =
            airui.TEXT_ALIGN_RIGHT
    })
    --添加图片组件
    airui.image({
        parent = top_bar,
        src = "/luadb/icon_flower.png",
        x = 10,
        y = 15,
        w = 30,
        h = 30,

    })
    airui.image({
        parent = top_bar,
        src = "/luadb/icon_book.png",
        x = 360,
        y = 15,
        w = 30,
        h = 30,

    })

    -- 内容区域
    content = airui.container({ parent = main_container, x = 0, y = 50, w = 480, h = 750, color = 0xfef5e7 })

    -- 右下角退出按钮
    local exit_btn = airui.button({
        parent = main_container,
        x = 400,
        y = 720,
        w = 60,
        h = 60,
        radius = 30,
        color = 0xf3ecd9,
        border_color = 0xe1cfb3,
        border_width = 1,
        text = "退出",
        font_size = 24,
        on_click = function()
            if win_id then exwin.close(win_id) end
        end
    })

    -- 渲染当前题目
    render_active_quiz()
end

--[[
渲染当前题目
@function render_active_quiz
@description 渲染题目、选项、按钮等界面元素
]]
local function render_active_quiz()
    -- 清空内容容器
    if content then
        content:clear()
    end

    -- 检查是否完成所有题目
    if quizCompletedFlag or isAllCompleted() then
        render_completion()
        return
    end

    -- 获取当前题目信息
    local question = POEMS_DB[currentIndex + 1]
    local totalCount = #POEMS_DB
    local answeredCount = 0
    -- 计算已回答的题目数量
    for _, v in ipairs(answeredStatus) do
        if v then answeredCount = answeredCount + 1 end
    end
    local progressPercent = (answeredCount / totalCount) * 100
    local isAlreadyCorrect = answeredStatus[currentIndex + 1]

    -- 标题
    local quiz_header = airui.container({ parent = content, x = 0, y = 20, w = 480, h = 60 })
    airui.label({
        parent = quiz_header,
        x = 100,
        y = 10,
        w = 280,
        h = 40,
        text = "择句填空",
        font_size = 24,
        color = 0x7f583b,
        align = airui.TEXT_ALIGN_CENTER,
        color_bg = 0xf4ecdd,
        radius = 30
    })
    airui.image({
        parent = quiz_header,
        src = "/luadb/res/icon_book.png",
        x = 80,
        y = 10,
        w = 50,
        h = 40,

    })


    -- 积分卡片
    local stats_card = airui.container({ parent = content, x = 20, y = 80, w = 440, h = 120, color = 0xfffaf2, radius = 36, border_color = 0xf0e2cf, border_width = 1 })
    airui.label({ parent = stats_card, x = 20, y = 20, w = 150, h = 30, text = " 诗才积分", font_size = 15, color = 0xa57148, font_weight = 600 })
    airui.label({
        parent = stats_card,
        x = 250,
        y = 10,
        w = 170,
        h = 40,
        text = tostring(score),
        font_size = 32,
        color = 0xc47a44,
        font_weight = 800,
        align =
            airui.TEXT_ALIGN_RIGHT
    })

    airui.image({
        parent = stats_card,
        src = "/luadb/res/icon_book.png",
        x = 200,
        y = 10,
        w = 30,
        h = 40,

    })

    -- 进度条
    local progress_track = airui.container({ parent = stats_card, x = 20, y = 70, w = 400, h = 8, color = 0xe7dac8, radius = 4 })
    local progress_fill = airui.container({ parent = progress_track, x = 0, y = 0, w = progressPercent * 4, h = 8, color = 0xc27e4a, radius = 4 })

    airui.label({
        parent = stats_card,
        x = 20,
        y = 90,
        w = 400,
        h = 20,
        text = "已悟 " ..
            answeredCount .. " / " .. totalCount .. " 章",
        font_size = 12,
        color = 0xb18862,
        align = airui.TEXT_ALIGN_RIGHT
    })

    airui.image({
        parent = stats_card,
        src = "/luadb/res/icon_book.png",
        x = 10,
        y = 90,
        w = 10,
        h = 20
    })

    -- 诗词填空卡片
    local question_card = airui.container({ parent = content, x = 20, y = 220, w = 440, h = 180, color = 0xffffff, radius = 48, border_color = 0xf3e5d0, border_width = 1 })
    local poem_stem = question.stem:gsub("________", "______")
    airui.label({
        parent = question_card,
        x = 20,
        y = 30,
        w = 400,
        h = 80,
        text = poem_stem,
        font_size = 24,
        color = 0x3c2a1f,
        align = airui.TEXT_ALIGN_CENTER,
        color_bg = 0xfef7e8,
        radius = 36
    })
    airui.label({
        parent = question_card,
        x = 20,
        y = 120,
        w = 400,
        h = 40,
        text = "💡 " .. question.hint,
        font_size = 13,
        color = 0xb4805a,
        align =
            airui.TEXT_ALIGN_CENTER
    })

    -- 选项区域
    local options_area = airui.container({ parent = content, x = 20, y = 420, w = 440, h = 200 })
    local prefixLetters = { "A", "B", "C", "D" }
    for i, opt in ipairs(question.options) do
        local option_item = airui.button({
            parent = options_area,
            x = 0,
            y = (i - 1) * 50,
            w = 440,
            h = 40,
            color = 0xfef6ec,
            border_color = 0xf0e0cb,
            border_width = 2,
            radius = 60,
            on_click = function()
                if isAlreadyCorrect then
                    feedbackMsg = "🏮 此诗已补全，无需再选，请进入下一题 🏮"
                    feedbackType = "neutral"
                    render_active_quiz()
                    return
                end
                selectedOptionIndex = i - 1
                feedbackMsg = ""
                render_active_quiz()
            end
        })
        if selectedOptionIndex == i - 1 then
            option_item:set_color(0xf7ebd9)
            option_item:set_border_color(0xc78754)
        end
        airui.label({ parent = option_item, x = 20, y = 10, w = 40, h = 20, text = prefixLetters[i] .. ".", font_size = 20, color = 0xbc8260, font_weight = 800 })
        airui.label({ parent = option_item, x = 60, y = 10, w = 300, h = 20, text = opt, font_size = 16, color = 0x5f4230 })
        local radio = airui.container({ parent = option_item, x = 380, y = 10, w = 22, h = 22, color = 0xffffff, border_color = 0xd6bc9a, border_width = 2, radius = 11 })
        if selectedOptionIndex == i - 1 then
            radio:set_color(0xc27e4a)
            radio:set_border_color(0xc27e4a)
            airui.container({ parent = radio, x = 5, y = 5, w = 12, h = 12, color = 0xffffff, radius = 6 })
        end
    end

    -- 按钮组
    local action_group = airui.container({ parent = content, x = 20, y = 640, w = 440, h = 60 })
    local prev_btn = airui.button({
        parent = action_group,
        x = 0,
        y = 0,
        w = 100,
        h = 50,
        color = 0xe7d9c6,
        text = "◀ 上题",
        font_size = 16,
        color_text = 0x7c5c3e,
        radius = 48,
        on_click = function()
            if quizCompletedFlag then return end
            if currentIndex > 0 then
                currentIndex = currentIndex - 1
                resetSelection()
                render_active_quiz()
            else
                feedbackMsg = "已是诗卷开篇，无上句可寻"
                feedbackType = "neutral"
                render_active_quiz()
                sys.timerStart(function()
                    if not quizCompletedFlag and feedbackMsg == "已是诗卷开篇，无上句可寻" then
                        feedbackMsg = ""
                        render_active_quiz()
                    end
                end, 1000)
            end
        end
    })

    local submit_btn = airui.button({
        parent = action_group,
        x = 110,
        y = 0,
        w = 100,
        h = 50,
        color = 0xc27e4a,
        text = "✓ 校验",
        font_size = 16,
        color_text = 0xffffff,
        radius = 48,
        on_click = function()
            if quizCompletedFlag then return end
            if answeredStatus[currentIndex + 1] then
                feedbackMsg = "🎋 此诗已补全，请进入下一题 🎋"
                feedbackType = "neutral"
                render_active_quiz()
                return
            end
            if selectedOptionIndex == -1 then
                feedbackMsg = "📜 请选择一个选项，补全诗句～"
                feedbackType = "neutral"
                render_active_quiz()
                return
            end

            local currentQuestion = POEMS_DB[currentIndex + 1]
            local selectedText = currentQuestion.options[selectedOptionIndex + 1]
            local isCorrect = isAnswerCorrect(currentQuestion, selectedText)

            if isCorrect then
                if not answeredStatus[currentIndex + 1] then
                    score = score + 1
                    answeredStatus[currentIndex + 1] = true
                    feedbackMsg = "✓ 妙哉！ \"" .. currentQuestion.correctAnswer .. "\" 正是此句！ +1 诗才 ✨"
                    feedbackType = "correct"
                    render_active_quiz()

                    if isAllCompleted() then
                        quizCompletedFlag = true
                        render_active_quiz()
                        return
                    end
                    local nextIdx = moveToNextUnanswered()
                    if nextIdx ~= -1 then
                        currentIndex = nextIdx - 1
                        resetSelection()
                        render_active_quiz()
                    else
                        quizCompletedFlag = true
                        render_active_quiz()
                    end
                    return
                else
                    feedbackMsg = "此题已经答对，继续下一段诗旅吧"
                    feedbackType = "neutral"
                    render_active_quiz()
                end
            else
                local hintMsg = currentQuestion.hint
                feedbackMsg = "❌ 续句不恰，再斟酌一番～  " .. (hintMsg and '📌 ' .. hintMsg or '')
                feedbackType = "wrong"
                render_active_quiz()
            end
        end
    })

    local skip_btn = airui.button({
        parent = action_group,
        x = 220,
        y = 0,
        w = 100,
        h = 50,
        color = 0xefe2cf,
        text = "⏩ 跳过",
        font_size = 16,
        color_text = 0x896b48,
        border_color = 0xe2cfb4,
        border_width = 1,
        radius = 48,
        on_click = function()
            if quizCompletedFlag then return end
            local nextUnanswered = moveToNextUnanswered()
            if nextUnanswered ~= -1 then
                currentIndex = nextUnanswered - 1
                resetSelection()
                render_active_quiz()
            else
                if isAllCompleted() then
                    quizCompletedFlag = true
                    render_active_quiz()
                else
                    local nextIdx = currentIndex + 1
                    if nextIdx < #POEMS_DB then
                        currentIndex = nextIdx
                        resetSelection()
                        render_active_quiz()
                    else
                        for i = 1, #POEMS_DB do
                            if not answeredStatus[i] then
                                currentIndex = i - 1
                                resetSelection()
                                render_active_quiz()
                                return
                            end
                        end
                        quizCompletedFlag = true
                        render_active_quiz()
                    end
                end
            end
        end
    })

    local next_btn = airui.button({
        parent = action_group,
        x = 330,
        y = 0,
        w = 100,
        h = 50,
        color = 0xe7d9c6,
        text = "下题 ▶",
        font_size = 16,
        color_text = 0x7c5c3e,
        radius = 48,
        on_click = function()
            if quizCompletedFlag then return end
            if not answeredStatus[currentIndex + 1] then
                feedbackMsg = "✨ 建议先完成本题填空，或使用「跳过」✨"
                feedbackType = "neutral"
                render_active_quiz()
                return
            end
            local nextUnanswered = moveToNextUnanswered()
            if nextUnanswered ~= -1 then
                currentIndex = nextUnanswered - 1
                resetSelection()
                render_active_quiz()
            else
                if isAllCompleted() then
                    quizCompletedFlag = true
                    render_active_quiz()
                else
                    if currentIndex + 1 < #POEMS_DB then
                        currentIndex = currentIndex + 1
                        resetSelection()
                        render_active_quiz()
                    else
                        for i = 1, #POEMS_DB do
                            if not answeredStatus[i] then
                                currentIndex = i - 1
                                resetSelection()
                                render_active_quiz()
                                return
                            end
                        end
                        quizCompletedFlag = true
                        render_active_quiz()
                    end
                end
            end
        end
    })

    -- 反馈信息
    local feedback_color = 0xefe3d3
    local feedback_text_color = 0x956e48
    if feedbackType == "correct" then
        feedback_color = 0xdbebc7
        feedback_text_color = 0x3c671d
    elseif feedbackType == "wrong" then
        feedback_color = 0xffe0cf
        feedback_text_color = 0xbd5a2b
    end
    local feedback = airui.container({ parent = content, x = 20, y = 710, w = 440, h = 40, color = feedback_color, radius = 40 })
    airui.label({
        parent = feedback,
        x = 20,
        y = 10,
        w = 400,
        h = 20,
        text = feedbackMsg ~= "" and feedbackMsg or "⚡ 选择正确选项，补全诗词意境 ⚡",
        font_size = 14,
        color = feedback_text_color,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 500
    })
end

--[[
渲染完成界面
@function render_completion
@description 渲染答题完成后的结果界面
]]
local function render_completion()
    -- 清空内容容器
    if content then
        content:clear()
    end

    local total = #POEMS_DB
    local finalScore = score
    local medal = ""
    -- 根据得分确定奖牌等级
    if finalScore == total then
        medal = "🏅 诗仙·满腹经纶"
    elseif finalScore >= total * 0.7 then
        medal = "📚 诗杰·才思敏捷"
    elseif finalScore >= total * 0.4 then
        medal = "🌱 诗童·初窥门径"
    else
        medal = "✍️ 墨客·勤学可嘉"
    end

    local completion_panel = airui.container({ parent = content, x = 40, y = 100, w = 400, h = 400, color = 0xfff7ec, radius = 56 })
    airui.label({
        parent = completion_panel,
        x = 0,
        y = 30,
        w = 400,
        h = 40,
        text = "🎉 诗卷圆满 🎉",
        font_size = 30,
        color = 0xc27e4a,
        align =
            airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = completion_panel,
        x = 0,
        y = 80,
        w = 400,
        h = 30,
        text = "慧心如兰，集句成章",
        font_size = 16,
        color = 0xa87042,
        align =
            airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = completion_panel,
        x = 0,
        y = 120,
        w = 400,
        h = 80,
        text = tostring(finalScore) ..
            " / " .. tostring(total),
        font_size = 54,
        color = 0xb26028,
        align = airui.TEXT_ALIGN_CENTER,
        font_weight = 800
    })
    airui.label({
        parent = completion_panel,
        x = 0,
        y = 220,
        w = 400,
        h = 30,
        text = medal,
        font_size = 16,
        color = 0x7f583b,
        align =
            airui.TEXT_ALIGN_CENTER
    })

    local restart_btn = airui.button({
        parent = completion_panel,
        x = 50,
        y = 280,
        w = 300,
        h = 60,
        color = 0xa57148,
        text = "🖌️ 重开诗卷",
        font_size = 18,
        color_text = 0xffffff,
        radius = 60,
        font_weight = 700,
        on_click = function()
            currentIndex = 0
            score = 0
            for i = 1, #answeredStatus do
                answeredStatus[i] = false
            end
            quizCompletedFlag = false
            selectedOptionIndex = -1
            feedbackMsg = ""
            feedbackType = "neutral"
            render_active_quiz()
        end
    })
end

--[[
窗口创建回调
@function on_create
@description 窗口创建时调用，初始化UI
]]
local function on_create()
    create_ui()
end

--[[
窗口销毁回调
@function on_destroy
@description 窗口销毁时调用，清理资源
]]
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
end

--[[
窗口获得焦点回调
@function on_get_focus
@description 窗口获得焦点时调用
]]
local function on_get_focus() end

--[[
窗口失去焦点回调
@function on_lose_focus
@description 窗口失去焦点时调用
]]
local function on_lose_focus() end

--[[
打开窗口处理函数
@function open_handler
@description 处理OPEN_VENDING_MACHINE_WIN事件，打开游戏窗口
]]
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

-- 订阅打开窗口事件
sys.subscribe("OPEN_VENDING_MACHINE_WIN", open_handler)
