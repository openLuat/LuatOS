--[[
@module idioms_classify_win
@summary 成语分类应用（找茬、错词本、成绩）
@version 1.0
@date    2026.04.17
@usage
订阅 "OPEN_IDIOMS_CLASSIFY_WIN" 事件打开窗口。
依赖全局 screen_w, screen_h 以及 idioms_data.lua。
]]

-- 屏幕尺寸（需要在实际运行时获取）
local screen_w = 480  -- 默认屏幕宽度
local screen_h = 800  -- 默认屏幕高度

local win_id = nil
local root_container = nil
local pages = {}
local current_page = "home"

-- 游戏状态
local find_current_index = 1
local find_round_correct = 0
local find_stats = { total = 0, correct = 0 }
local wrong_idioms = {}
local random_find_questions = {}
local TOTAL_QUESTIONS = 10
local answer_locked = false   -- 防止重复点击标志

-- 颜色常量
local COLOR_BG_MAIN = 0xFFF9F0
local COLOR_PRIMARY = 0xF9A826
local COLOR_SUCCESS = 0x6BCFAB
local COLOR_ERROR = 0xFF8A80
local COLOR_BUTTON = 0x82A8F0
local COLOR_EXIT = 0xE07C6C
local COLOR_CARD = 0xFFFFFFFF
local COLOR_TEXT_DARK = 0x333333
local COLOR_TEXT_LIGHT = 0x666666
local COLOR_PINK = 0xFF69B4  -- 粉色，用于闯关成绩按钮

-- 数据模块
local idiomData = require("idioms_data").idiomData
local findQuestions = require("idioms_data").findQuestions

-- 随机抽题
local function get_random_questions(arr, num)
    local shuffled = {}
    for i = 1, #arr do shuffled[i] = arr[i] end
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    local result = {}
    for i = 1, num do result[i] = shuffled[i] end
    return result
end

-- 页面切换
local function show_page(page_name)
    if not root_container then return end
    current_page = page_name
    for name, page in pairs(pages) do
        if page.container then
            page.container:set_hidden(name ~= page_name)
        end
    end
end

-- 预声明
local load_find_question
local handle_find_answer
local next_find_question
local load_wrong_list
local load_stats
local go_to_study

-- ========== 创建首页 ==========
local function create_home_page(parent)
    local page = { container = airui.container({
        parent = parent, x = 0, y = 0, w = screen_w, h = screen_h,
        color = COLOR_BG_MAIN, hidden = false
    }) }

    airui.label({
        parent = page.container, 
        text = "成语小课堂", 
        x = 0, 
        y = 60,
        w = screen_w,
         h = 48, 
         font_size = 32, 
         color = 0xD48F2B,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = page.container, 
        text = "每日积累 , 出口成章", 
        x = 0, 
        y = 110,
        w = screen_w, 
        h = 28, 
        font_size = 16, 
        color = 0xB97F2E,
        align = airui.TEXT_ALIGN_CENTER
    })

    local btn_w, btn_h, btn_gap = 280, 56, 16
    local btn_x = (screen_w - btn_w) / 2
    local start_y = 170

    airui.button({
        parent = page.container, text = "分类找茬", x = btn_x, y = start_y,
        w = btn_w, h = btn_h, font_size = 22, text_color = 0xFFFFFF,
        style = { bg_color = COLOR_PRIMARY, radius = 28, pressed_bg_color = 0xE68900 },
        on_click = function()
            find_current_index = 1
            find_round_correct = 0
            random_find_questions = get_random_questions(findQuestions, TOTAL_QUESTIONS)
            answer_locked = false
            show_page("find")
            load_find_question()
        end
    })

    airui.button({
        parent = page.container, 
        text = "错词本", 
        x = btn_x,
        y = start_y + btn_h + btn_gap,
        w = btn_w, h = btn_h, font_size = 22, 
        text_color = 0xFFFFFF,
        style = {
             bg_color = COLOR_BUTTON, 
             radius = 28, 
             pressed_bg_color = 0x6A8AD0 
            },
        on_click = function()
            show_page("wrong")
            load_wrong_list()
        end
    })

    airui.button({
        parent = page.container, 
        text = "闯关成绩", 
        x = btn_x,
        y = start_y + (btn_h + btn_gap) * 2,
        w = btn_w, h = btn_h, font_size = 22, 
        text_color = 0xFFFFFF,
        style = {
             bg_color = COLOR_PINK, 
             radius = 28, 
             pressed_bg_color = 0xE75480 
            },
        on_click = function()
            show_page("stats")
            load_stats()
        end
    })

    airui.button({
        parent = page.container, 
        text = "退出应用", 
        x = btn_x, 
        y = start_y + (btn_h + btn_gap) * 3,
        w = btn_w, h = btn_h, font_size = 22, 
        text_color = 0xFFFFFF,
        style = {
             bg_color = COLOR_EXIT, 
             radius = 28, 
             pressed_bg_color = 0xC95B4A 
            },
        on_click = function()
            if win_id then exwin.close(win_id) end
        end
    })

    return page
end

-- ========== 分类找茬页面 ==========
local function create_find_page(parent)
    local page = { container = airui.container({
        parent = parent, x = 0, y = 0, w = screen_w, h = screen_h,
        color = COLOR_BG_MAIN, hidden = true
    }) }   

    page.progress_label = airui.label({
        parent = page.container, 
        text = "1/10", 
        x = 16, 
        y = 16,
        w = 100, h = 28, font_size = 18, 
        color = COLOR_PRIMARY
    })

    airui.label({
        parent = page.container, 
        text = "分类找茬", 
        x = 0, 
        y = 50,
        w = screen_w, h = 40, font_size = 26, 
        color = COLOR_TEXT_DARK,
        align = airui.TEXT_ALIGN_CENTER
    })
    page.category_label = airui.label({
        parent = page.container, 
        text = "", 
        x = 0, 
        y = 100,
        w = screen_w,
        h = 30,
        font_size = 20, 
        color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })

    local btn_w = (screen_w - 80) / 2
    local btn_h = 70
    local start_x = 20
    local start_y = 160
    local gap = 20
    page.idiom_buttons = {}
    for i = 1, 4 do
        local row = math.ceil(i / 2) - 1
        local col = (i - 1) % 2
        local btn = airui.button({
            parent = page.container, 
            text = "",
            x = start_x + col * (btn_w + gap), 
            y = start_y + row * (btn_h + gap),
            w = btn_w, h = btn_h, font_size = 20, 
            text_color = COLOR_TEXT_DARK,
            style = {
                bg_color = COLOR_CARD, border_color = COLOR_PRIMARY, border_width = 2,
                radius = 12, pressed_bg_color = 0xFFF0E0
            },
            on_click = function() handle_find_answer(i) end
        })
        page.idiom_buttons[i] = btn
    end

    -- 反馈区域
    local feedback_bg = airui.container({
        parent = page.container, 
        x = 20, 
        y = start_y + 2 * (btn_h + gap), 
        w = start_y + 2 * (btn_h + gap) + 10,
        w = screen_w - 40, h = 50, bg_color = COLOR_CARD, radius = 8
    })
    page.feedback_label = airui.label({
        parent = feedback_bg, 
        text = "", 
        x = 0, 
        y = 12,
        w = screen_w - 40, 
        h = 30, 
        font_size = 16, 
        color = COLOR_TEXT_LIGHT,
        align = airui.TEXT_ALIGN_CENTER
    })

    local bottom_y = start_y + 2 * (btn_h + gap) + 70
    airui.button({
        parent = page.container, 
        text = "返回", 
        x = 40, 
        y = bottom_y,
        w = 100, h = 44, font_size = 18, 
        text_color = 0xFFFFFF,
        style = {
             bg_color = COLOR_BUTTON, 
             radius = 22, 
             pressed_bg_color = 0x6A8AD0 
            },
        on_click = function() show_page("home") end
    })
    page.next_btn = airui.button({
        parent = page.container, 
        text = "下一题", 
        x = screen_w - 140, 
        y = bottom_y,
        w = 100, h = 44, font_size = 18, 
        text_color = 0xFFFFFF,
        style = {
             bg_color = COLOR_SUCCESS, 
             radius = 22, 
             pressed_bg_color = 0x5ABF99 
            },  
        on_click = next_find_question
    })
    -- 初始禁用下一题（通过样式变灰，但点击仍会触发，所以还需在 next_find_question 中判断）
    page.next_btn:set_style({ bg_color = 0xCCCCCC, pressed_bg_color = 0xCCCCCC })
    page.next_btn_disabled = true

    return page
end

-- ========== 错词本页面 ==========
local function create_wrong_page(parent)
    local page = {
         container = airui.container({
        parent = parent, 
        x = 0, 
        y = 0, 
        w = screen_w, 
        h = screen_h,
        color = COLOR_BG_MAIN, hidden = true
    }) }

    airui.label({
        parent = page.container, 
        text = "错词本", 
        x = 0, 
        y = 50,
        w = screen_w, h = 40, font_size = 26, 
        color = COLOR_TEXT_DARK,
        align = airui.TEXT_ALIGN_CENTER
    })

    local list_container = airui.container({
        parent = page.container, 
        x = 20, 
        y = 110,
        w = screen_w - 40, h = screen_h - 180, bg_color = COLOR_CARD, radius = 12
    })
    page.list_container = list_container

    local function refresh_list()
        if page.list_container then
            page.list_container:destroy()
        end
        local new_container = airui.container({
            parent = page.container, 
            x = 20, 
            y = 110,
            w = screen_w - 40, h = screen_h - 180, bg_color = COLOR_CARD, radius = 12
        })
        page.list_container = new_container

        if #wrong_idioms == 0 then
            airui.label({
                parent = new_container, 
                text = "暂无错词，继续加油！", 
                x = 0, 
                y = 50,
                w = screen_w - 40, 
                h = 30, 
                font_size = 16, 
                color = 0x999999,
                align = airui.TEXT_ALIGN_CENTER
            })
        else
            local y_offset = 10
            for idx, idiom in ipairs(wrong_idioms) do
                local item = airui.container({
                    parent = new_container, 
                    x = 10, 
                    y = y_offset,   
                    w = screen_w - 60, h = 50, bg_color = (idx % 2 == 0) and 0xF8F8F8 or 0xFFFFFF,
                    radius = 8
                })
                airui.label({
                    parent = item,
                    text = idiom, 
                    x = 15, 
                    y = 10,
                    w = screen_w - 160, h = 30, font_size = 18, color = COLOR_TEXT_DARK
                })
                airui.button({
                    parent = item, 
                    text = "学习", 
                    x = screen_w - 200, 
                    y = 8,
                    w = 60, 
                    h = 34, 
                    font_size = 14, 
                    text_color = 0xFFFFFF,
                    style = {
                        bg_color = COLOR_BUTTON, 
                        radius = 17, 
                        pressed_bg_color = 0x6A8AD0 
                    },
                    on_click = (function(w) return function() go_to_study(w) end end)(idiom)
                })
                airui.button({
                    parent = item, 
                    text = "删除", 
                    x = screen_w - 130, 
                    y = 8,  
                    w = 60, 
                    h = 34, 
                    font_size = 14, 
                    text_color = 0xFFFFFF,
                    style = {
                        bg_color = COLOR_ERROR, 
                        radius = 17, 
                        pressed_bg_color = 0xE06A5E 
                    },
                    on_click = (function(idx) return function()
                        table.remove(wrong_idioms, idx)
                        refresh_list()
                    end end)(idx)
                })
                y_offset = y_offset + 60
            end
        end
    end

    page.refresh = refresh_list

    airui.button({
        parent = page.container, 
        text = "返回主页", 
        x = (screen_w - 120) / 2,
        y = screen_h - 60, w = 120, h = 44, font_size = 18, 
        text_color = 0xFFFFFF,
        style = {
             bg_color = COLOR_BUTTON, 
             radius = 22, 
             pressed_bg_color = 0x6A8AD0 
        },
        on_click = function() show_page("home") end
    })

    return page
end

-- ========== 闯关成绩页面 ==========
local function create_stats_page(parent)
    local page = { container = airui.container({
        parent = parent, 
        x = 0, 
        y = 0, 
        w = screen_w, 
        h = screen_h,
        color = COLOR_BG_MAIN, hidden = true
    }) }

    airui.label({
        parent = page.container, 
        text = "闯关成绩", 
        x = 0, 
        y = 50,
        w = screen_w, 
        h = 40, 
        font_size = 26, 
        color = COLOR_TEXT_DARK,
        align = airui.TEXT_ALIGN_CENTER
    })

    local card = airui.container({
        parent = page.container, 
        x = 40, 
        y = 120,
        w = screen_w - 80, h = 200, bg_color = COLOR_CARD, radius = 16
    })

    local function add_stat_row(y, label)
        airui.label({
            parent = card, 
            text = label, 
            x = 30, 
            y = y,
            w = 150, h = 36, font_size = 20, color = COLOR_TEXT_DARK
        })
        return airui.label({
            parent = card, 
            text = "0", 
            x = 200, 
            y = y,
            w = 100, 
            h = 36, 
            font_size = 24, 
            color = COLOR_PRIMARY,
            align = airui.TEXT_ALIGN_RIGHT
        })
    end

    page.total_label = add_stat_row(30, "总题数：")
    page.correct_label = add_stat_row(90, "正确数：")
    page.accuracy_label = add_stat_row(150, "正确率：")

    airui.button({
        parent = page.container, 
        text = "返回", 
        x = (screen_w - 100) / 2, 
        y = screen_h - 80, 
        w = 100, 
        h = 44, 
        font_size = 18, 
        text_color = 0xFFFFFF,
        style = {
             bg_color = COLOR_BUTTON, 
             radius = 22, 
             pressed_bg_color = 0x6A8AD0 
        },
        on_click = function() show_page("home") end
    })

    return page
end

-- ========== 成语学习页面 ==========
local function create_study_page(parent)
    local page = { container = airui.container({
        parent = parent, 
        x = 0, 
        y = 0, 
        w = screen_w, 
        h = screen_h,
        color = COLOR_BG_MAIN, hidden = true
    }) }

    airui.label({
        parent = page.container, 
        text = "", 
        x = 0, 
        y = 50,
        w = screen_w, h = 40, font_size = 26, color = COLOR_TEXT_DARK,
        align = airui.TEXT_ALIGN_CENTER
    })

    local card = airui.container({
        parent = page.container, 
        x = 20, 
        y = 110,
        w = screen_w - 40, h = screen_h - 180, bg_color = COLOR_CARD, radius = 16
    })

    page.study_word = airui.label({
        parent = card, 
        text = "", 
        x = 0, y = 20,
        w = screen_w - 80, h = 48, font_size = 34, color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_CENTER
    })
    page.study_pinyin = airui.label({
        parent = card, 
        text = "", 
        x = 0, y = 80,   
        w = screen_w - 80, h = 30, font_size = 18, color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = card, 
        text = "释义：", x = 20, y = 130,
        w = 80, h = 28, font_size = 18, color = COLOR_TEXT_DARK
    })
    page.study_explain = airui.label({
        parent = card, 
        text = "", 
        x = 20, 
        y = 160, 
        w = screen_w - 100, 
        h = 80, 
        font_size = 16, color = COLOR_TEXT_LIGHT
    })
    airui.label({
        parent = card, 
        text = "造句：", x = 20, y = 260,
        w = 80, h = 28, font_size = 18, color = COLOR_TEXT_DARK
    })
    page.study_sentence = airui.label({
        parent = card, 
        text = "", 
        x = 20, 
        y = 290, 
        w = screen_w - 100, 
        h = 80, 
        font_size = 16, color = COLOR_TEXT_LIGHT
    })

    airui.button({
        parent = page.container, 
        text = "返回错词本", 
        x = (screen_w - 140) / 2,
        y = screen_h - 60, 
        w = 140, h = 44, font_size = 18, 
        text_color = 0xFFFFFF,
        style = {
             bg_color = COLOR_BUTTON, 
             radius = 22, 
             pressed_bg_color = 0x6A8AD0 
        },  
        on_click = function() show_page("wrong") end
    })

    return page
end

-- ========== 业务逻辑 ==========
load_find_question = function()
    local page = pages.find
    if not page then return end
    local q = random_find_questions[find_current_index]
    if not q then return end

    page.progress_label:set_text(find_current_index .. "/" .. TOTAL_QUESTIONS)
    page.category_label:set_text(q.category)

    -- 设置四个按钮文本
    for i = 1, 4 do
        local btn = page.idiom_buttons[i]
        if btn then
            local text = (q.idioms and q.idioms[i]) or ""
            btn:set_text(text)
            btn:set_style({ bg_color = COLOR_CARD, text_color = COLOR_TEXT_DARK })
        end
    end

    page.feedback_label:set_text("请点击选择答案")
    -- 恢复下一题按钮样式为禁用状态
    page.next_btn:set_style({ bg_color = 0xCCCCCC, pressed_bg_color = 0xCCCCCC })
    page.next_btn_disabled = true
    answer_locked = false
end

handle_find_answer = function(selected_index)
    if answer_locked then return end   -- 已经回答过本题，防止重复点击
    local page = pages.find
    if not page then return end
    local q = random_find_questions[find_current_index]
    if not q then return end

    answer_locked = true   -- 锁定，防止再次点击

    find_stats.total = find_stats.total + 1

    if selected_index == q.answer then
        local correct_btn = page.idiom_buttons[selected_index]
        correct_btn:set_style({ bg_color = COLOR_SUCCESS, text_color = 0xFFFFFF })
        page.feedback_label:set_text("正确！ " .. (q.reason or ""))
        find_stats.correct = find_stats.correct + 1
        find_round_correct = find_round_correct + 1
    else
        local wrong_btn = page.idiom_buttons[selected_index]
        wrong_btn:set_style({ bg_color = COLOR_ERROR, text_color = 0xFFFFFF })
        local correct_btn = page.idiom_buttons[q.answer]
        correct_btn:set_style({ bg_color = COLOR_SUCCESS, text_color = 0xFFFFFF })
        page.feedback_label:set_text("错误！ " .. (q.reason or ""))

        local wrong_word = q.wrong
        if wrong_word and wrong_word ~= "" then
            local exists = false
            for _, v in ipairs(wrong_idioms) do
                if v == wrong_word then exists = true; break end
            end
            if not exists then
                table.insert(wrong_idioms, wrong_word)
            end
        end
    end

    -- 启用下一题按钮（恢复样式，与返回按钮颜色一致）
    page.next_btn:set_style({ bg_color = COLOR_BUTTON, pressed_bg_color = 0x6A8AD0 })
    page.next_btn_disabled = false
end

next_find_question = function()
    if pages.find.next_btn_disabled then return end  -- 如果尚未作答，不能进入下一题

    find_current_index = find_current_index + 1
    if find_current_index > TOTAL_QUESTIONS then
        local round_acc = math.floor((find_round_correct / TOTAL_QUESTIONS) * 100)
        local total_acc = 0
        if find_stats.total > 0 then
            total_acc = math.floor((find_stats.correct / find_stats.total) * 100)
        end

        pages.find.container:set_hidden(true)

        local modal_bg = airui.container({
            parent = airui.screen, x = 0, y = 0, w = screen_w, h = screen_h,
            bg_color = 0x000000, color_opacity = 200, z_index = 9999
        })
        local modal = airui.container({
            parent = modal_bg, x = 40, y = 60, w = screen_w - 80, h = 320,
            bg_color = COLOR_CARD, radius = 20, z_index = 10000
        })
        airui.label({
            parent = modal, text = "闯关完成！", x = 0, y = 25,
            w = screen_w - 80, h = 40, font_size = 24, color = COLOR_PRIMARY,
            align = airui.TEXT_ALIGN_CENTER
        })
        airui.label({
            parent = modal, text = "本轮成绩：" .. find_round_correct .. "/" .. TOTAL_QUESTIONS .. " 题",
            x = 0, y = 85, w = screen_w - 80, h = 30, font_size = 18, color = COLOR_TEXT_DARK,
            align = airui.TEXT_ALIGN_CENTER
        })
        airui.label({
            parent = modal, text = "本轮正确率：" .. round_acc .. "%",
            x = 0, y = 125, w = screen_w - 80, h = 30, font_size = 18, color = COLOR_TEXT_DARK,
            align = airui.TEXT_ALIGN_CENTER
        })
        airui.label({
            parent = modal, text = "总题数：" .. find_stats.total .. " 题",
            x = 0, y = 165, w = screen_w - 80, h = 30, font_size = 18, color = COLOR_TEXT_DARK,
            align = airui.TEXT_ALIGN_CENTER
        })
        airui.label({
            parent = modal, text = "总正确率：" .. total_acc .. "%",
            x = 0, y = 205, w = screen_w - 80, h = 30, font_size = 18, color = COLOR_TEXT_DARK,
            align = airui.TEXT_ALIGN_CENTER
        })
        airui.button({
            parent = modal, text = "确定", x = (screen_w - 80 - 100) / 2, y = 270,
            w = 100, h = 36, font_size = 18, text_color = 0xFFFFFF,
            style = { bg_color = COLOR_PRIMARY, radius = 18, pressed_bg_color = 0xE68900 },
            on_click = function()
                modal_bg:destroy()
                pages.find.container:set_hidden(false)
                show_page("home")
            end
        })
        return
    end
    load_find_question()
end

load_wrong_list = function()
    if pages.wrong and pages.wrong.refresh then
        pages.wrong.refresh()
    end
end

load_stats = function()
    local page = pages.stats
    if not page then return end
    page.total_label:set_text(tostring(find_stats.total))
    page.correct_label:set_text(tostring(find_stats.correct))
    local acc = 0
    if find_stats.total > 0 then
        acc = math.floor((find_stats.correct / find_stats.total) * 100)
    end
    page.accuracy_label:set_text(acc .. "%")
end

go_to_study = function(idiom)
    local page = pages.study
    if not page then return end
    local data = idiomData[idiom]
    if not data then
        data = { pinyin = "暂无", explain = "暂无详细释义，可自行查阅词典。", sentence = "暂无例句" }
    end
    page.study_word:set_text(idiom)
    page.study_pinyin:set_text(data.pinyin)
    page.study_explain:set_text(data.explain)
    page.study_sentence:set_text(data.sentence)
    show_page("study")
end

-- ========== 窗口生命周期 ==========
local function on_create()
    root_container = airui.container({
        parent = airui.screen, x = 0, y = 0, w = screen_w, h = screen_h,
        color = COLOR_BG_MAIN
    })
    pages.home = create_home_page(root_container)
    pages.find = create_find_page(root_container)
    pages.wrong = create_wrong_page(root_container)
    pages.stats = create_stats_page(root_container)
    pages.study = create_study_page(root_container)
    show_page("home")
end

local function on_destroy()
    if root_container then
        root_container:destroy()
        root_container = nil
    end
    pages = {}
    find_current_index = 1
    find_round_correct = 0
    find_stats = { total = 0, correct = 0 }
    wrong_idioms = {}
    random_find_questions = {}
end

local function on_get_focus()
    if current_page == "stats" then load_stats() end
    if current_page == "wrong" then load_wrong_list() end
end

local function on_lose_focus() end

local function open_handler()
    -- 直接打开窗口，不做复杂的状态检查
    -- 窗口的on_create和on_destroy会处理状态管理
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_IDIOMS_CLASSIFY_WIN", open_handler)