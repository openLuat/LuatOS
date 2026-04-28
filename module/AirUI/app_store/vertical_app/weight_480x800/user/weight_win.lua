--[[
@module  weight_win
@summary 智能体重秤窗口模块
@version 1.0
@date    2026.04.08
@author  蒋骞
@usage
智能健康体检一体机应用，支持：
1. 身高体重测量
2. 人体成分分析
3. 全部顺序测量
4. 用户信息录入（性别、年龄）
5. 健康分析和报告生成
]]

local win_id = nil
local main_container, page_container

local current_page = nil
local countdown_interval = nil
local countdown_seconds = 0

local bmi_data = { height = 0, weight = 0, bmi = 0, analysis = '', color = 0x4CAF50 }
local body_data = { tzl = 0, tzw = 0, bmr = 0, analysis1 = '', analysis2 = '', analysis3 = '', color1 = 0x4CAF50, color2 = 0x4CAF50, color3 = 0x4CAF50 }
local user_gender = nil
local user_age = nil
local is_full_measuring = false
local full_measure_step = 0

local modal_container = nil
local modal_gender_male = nil
local modal_gender_female = nil
local modal_age_input = nil
local selected_gender = nil
local age_str = "30"

local show_splash = false
local home_page, menu_page, stature_guide_page, stature_result_page, body_guide_page, body_result_page, report_page

local stature_data_container, body_data_container
local report_bmi_grid, report_body_grid

local show_page
local datetime_timer = nil

local function format_number(num)
    if type(num) ~= "number" then
        return tostring(num)
    end
    if num == math.floor(num) then
        return tostring(num)
    end
    return string.format("%.2f", num)
end

local function random_range(min, max)
    local num = (math.random() * (max - min) + min)
    return math.floor(num * 100 + 0.5) / 100
end

local function get_bmi_color(bmi)
    if bmi < 18.5 then
        return 0xFFCC00
    elseif bmi < 24.9 then
        return 0x4CAF50
    else
        return 0xFF4444
    end
end

local function get_bmi_analysis(bmi)
    if bmi < 18.5 then
        return '偏瘦'
    elseif bmi < 24.9 then
        return '正常'
    else
        return '偏重'
    end
end

local function get_analysis_color(value)
    if value == '偏低' then
        return 0xFF8C42
    elseif value == '正常' then
        return 0x4CAF50
    else
        return 0xFF4444
    end
end

local function render_stature_result()
    if not stature_data_container then
        return
    end
    
    local data_rows = {
        { label = '身高：', value = format_number(bmi_data.height) .. ' cm' },
        { label = '体重：', value = format_number(bmi_data.weight) .. ' kg' },
        { label = 'BMI：', value = format_number(bmi_data.bmi) },
        { label = '健康分析：', value = '您的体重' .. bmi_data.analysis, color = bmi_data.color }
    }
    
    for i, row in ipairs(data_rows) do
        local row_container = airui.container({
            parent = stature_data_container,
            x = 16,
            y = math.floor((i - 1) * 62),
            w = 448,
            h = 55,
            color = 0xFFFFFF,
            radius = 16
        })
        
        airui.container({
            parent = row_container,
            x = 0,
            y = 4,
            w = 5,
            h = 47,
            color = 0x5BA3D9,
            radius = 2
        })
        
        airui.label({
            parent = row_container,
            x = 19,
            y = 15,
            w = 160,
            h = 25,
            text = row.label,
            font_size = 14,
            color = 0x5BA3D9,
            align = airui.TEXT_ALIGN_LEFT
        })
        
        local value_color = row.color or 0x333333
        airui.label({
            parent = row_container,
            x = 176,
            y = 15,
            w = 256,
            h = 25,
            text = row.value,
            font_size = 14,
            color = value_color,
            align = airui.TEXT_ALIGN_RIGHT
        })
    end
end

local function do_stature_measure(callback)
    local height = random_range(160, 200)
    local weight = random_range(50, 90)
    local bmi = weight / ((height / 100) * (height / 100))
    bmi = math.floor(bmi * 10) / 10
    
    log.info("do_stature_measure function", height, weight, bmi)
    bmi_data = {
        height = math.floor(height * 10) / 10,
        weight = math.floor(weight * 10) / 10,
        bmi = bmi,
        analysis = get_bmi_analysis(bmi),
        color = get_bmi_color(bmi)
    }
    
    render_stature_result()
    
    if callback then
        callback()
    end
end

local function render_body_result()
    if not body_data_container then
        return
    end
    
    local data_rows = {
        { label = '体脂率：', value = format_number(body_data.tzl) .. '%', color = body_data.color1 },
        { label = '体脂肪量：', value = format_number(body_data.tzw) .. ' kg', color = body_data.color2 },
        { label = '基础代谢：', value = body_data.bmr .. ' kcal', color = body_data.color3 },
        { label = '体脂率分析：', value = body_data.analysis1, color = body_data.color1 },
        { label = '体脂肪量分析：', value = body_data.analysis2, color = body_data.color2 },
        { label = '基础代谢分析：', value = body_data.analysis3, color = body_data.color3 }
    }
    
    for i, row in ipairs(data_rows) do
        local row_container = airui.container({
            parent = body_data_container,
            x = 16,
            y = math.floor((i - 1) * 47),
            w = 448,
            h = 43,
            color = 0xFFFFFF,
            radius = 16
        })
        
        airui.container({
            parent = row_container,
            x = 0,
            y = 4,
            w = 5,
            h = 35,
            color = 0x5BA3D9,
            radius = 2
        })
        
        airui.label({
            parent = row_container,
            x = 19,
            y = 12,
            w = 160,
            h = 20,
            text = row.label,
            font_size = 12,
            color = 0x5BA3D9,
            align = airui.TEXT_ALIGN_LEFT
        })
        
        airui.label({
            parent = row_container,
            x = 176,
            y = 12,
            w = 256,
            h = 20,
            text = row.value,
            font_size = 12,
            color = row.color or 0x333333,
            align = airui.TEXT_ALIGN_RIGHT
        })
    end
end

local function do_body_measure(callback)
    local tzl = random_range(5, 30)
    local weight = bmi_data.weight > 0 and bmi_data.weight or random_range(50, 90)
    local tzw = weight * tzl / 100
    local height = bmi_data.height > 0 and bmi_data.height or random_range(160, 200)
    local age = user_age or 30
    local gender = user_gender or '男'
    local bmr
    if gender == '男' then
        bmr = 88.362 + 13.397 * weight + 4.799 * height - 5.677 * age
    else
        bmr = 447.593 + 9.247 * weight + 3.098 * height - 4.330 * age
    end
    bmr = math.floor(bmr)
    local analysis1
    if gender == '男' then
        if tzl < 15 then
            analysis1 = '偏低'
        elseif tzl <= 18 then
            analysis1 = '正常'
        else
            analysis1 = '偏高'
        end
    else
        if tzl < 20 then
            analysis1 = '偏低'
        elseif tzl <= 25 then
            analysis1 = '正常'
        else
            analysis1 = '偏高'
        end
    end
    local analysis3
    if gender == '男' then
        if bmr < 1400 then
            analysis3 = '偏低'
        elseif bmr <= 1800 then
            analysis3 = '正常'
        else
            analysis3 = '偏高'
        end
    else
        if bmr < 1200 then
            analysis3 = '偏低'
        elseif bmr <= 1500 then
            analysis3 = '正常'
        else
            analysis3 = '偏高'
        end
    end
    body_data = {
        tzl = math.floor(tzl * 10) / 10,
        tzw = math.floor(tzw * 10) / 10,
        bmr = bmr,
        analysis1 = analysis1,
        analysis2 = analysis1,
        analysis3 = analysis3,
        color1 = get_analysis_color(analysis1),
        color2 = get_analysis_color(analysis1),
        color3 = get_analysis_color(analysis3)
    }
    
    render_body_result()
    
    if callback then
        callback()
    end
end

local function render_report_bmi()
    if not report_bmi_grid then
        return
    end
    
    local icon_container = airui.container({
        parent = report_bmi_grid,
        x = 0,
        y = 8,
        w = 64,
        h = 64
    })
    
    -- airui.label({
    --     parent = icon_container,
    --     x = 0,
    --     y = 8,
    --     w = 64,
    --     h = 32,
    --     -- text = '📊',
    --     text = '体质指数',
    --     font_size = 24,
    --     color = 0x5BA3D9,
    --     align = airui.TEXT_ALIGN_CENTER
    -- })

    airui.image({
        parent = icon_container,
        x = 0,
        y = 8,
        w = 64,
        h = 56,
        src = '/luadb/HL.png',
        opacity = 255
    })
    
    -- airui.label({
    --     parent = icon_container,
    --     x = 0,
    --     y = 36,
    --     w = 64,
    --     h = 19,
    --     text = '体质指数',
    --     font_size = 11,
    --     color = 0x5BA3D9,
    --     align = airui.TEXT_ALIGN_CENTER
    -- })
    
    local report_items = {
        { label = '身高', value = format_number(bmi_data.height) .. ' cm' },
        { label = '体重', value = format_number(bmi_data.weight) .. ' kg' },
        { label = 'BMI', value = format_number(bmi_data.bmi) },
        { label = '分析', value = bmi_data.analysis, color = bmi_data.color }
    }
    
    for i, item in ipairs(report_items) do
        airui.label({
            parent = report_bmi_grid,
            x = 88,
            y = 8 + math.floor((i - 1) * 17),
            w = 160,
            h = 15,
            text = item.label,
            font_size = 11,
            color = 0x5BA3D9,
            align = airui.TEXT_ALIGN_LEFT
        })
        
        airui.label({
            parent = report_bmi_grid,
            x = 256,
            y = 8 + math.floor((i - 1) * 17),
            w = 120,
            h = 15,
            text = item.value,
            font_size = 11,
            color = item.color or 0x333333,
            align = airui.TEXT_ALIGN_RIGHT
        })
    end

    airui.label({
        parent = report_bmi_grid,
        x = 16,
        y = 6 + math.floor(#report_items * 17),
        w = 416,
        h = 15,
        text = '正常成年人的BMI范围为18.5~23.9',
        font_size = 11,
        color = 0x999999,
        align = airui.TEXT_ALIGN_LEFT
    })
end

local function render_report_body()
    if not report_body_grid then
        return
    end
    
    local icon_container = airui.container({
        parent = report_body_grid,
        x = 0,
        y = 8,
        w = 64,
        h = 64
    })
    
    -- airui.label({
    --     parent = icon_container,
    --     x = 0,
    --     y = 8,
    --     w = 64,
    --     h = 32,
    --     -- text = '🧬',
    --     text = '人体成分',
    --     font_size = 24,
    --     color = 0x5BA3D9,
    --     align = airui.TEXT_ALIGN_CENTER
    -- })
    airui.image({
        parent = icon_container,
        x = 0,
        y = 8,
        w = 64,
        h = 56,
        src = '/luadb/ch.png',
        opacity = 255
    })
    
    -- airui.label({
    --     parent = icon_container,
    --     x = 0,
    --     y = 36,
    --     w = 64,
    --     h = 19,
    --     text = '人体成分',
    --     font_size = 11,
    --     color = 0x5BA3D9,
    --     align = airui.TEXT_ALIGN_CENTER
    -- })
    
    local report_items = {
        { label = '体脂率', value = format_number(body_data.tzl) .. '%', color = body_data.color1 },
        { label = '体脂肪量', value = format_number(body_data.tzw) .. ' kg', color = body_data.color2 },
        { label = '基础代谢', value = body_data.bmr .. ' kcal', color = body_data.color3 },
        { label = '体脂率分析', value = body_data.analysis1, color = body_data.color1 }
    }
    
    for i, item in ipairs(report_items) do
        airui.label({
            parent = report_body_grid,
            x = 88,
            y = 8 + math.floor((i - 1) * 17),
            w = 160,
            h = 15,
            text = item.label,
            font_size = 11,
            color = 0x5BA3D9,
            align = airui.TEXT_ALIGN_LEFT
        })
        
        airui.label({
            parent = report_body_grid,
            x = 256,
            y = 8 + math.floor((i - 1) * 17),
            w = 120,
            h = 15,
            text = item.value,
            font_size = 11,
            color = item.color or 0x333333,
            align = airui.TEXT_ALIGN_RIGHT
        })
    end

    local gender = user_gender or '男'
    local range_text = gender == '女' and '正常女性的体脂率范围为20.0%~25.0%' or '正常男性的体脂率范围为15.0%~18.0%'
    airui.label({
        parent = report_body_grid,
        x = 16,
        y = 6 + math.floor(#report_items * 17),
        w = 416,
        h = 15,
        text = range_text,
        font_size = 11,
        color = 0x999999,
        align = airui.TEXT_ALIGN_LEFT
    })
end

local function destroy_current_page()
    if current_page == 'home' and home_page then
        home_page:destroy()
        home_page = nil
        if datetime_timer then
            sys.timerStop(datetime_timer)
            datetime_timer = nil
        end
    elseif current_page == 'menu' and menu_page then
        menu_page:destroy()
        menu_page = nil
    elseif current_page == 'stature_guide' and stature_guide_page then
        stature_guide_page:destroy()
        stature_guide_page = nil
    elseif current_page == 'stature_result' and stature_result_page then
        stature_result_page:destroy()
        stature_result_page = nil
        stature_data_container = nil
    elseif current_page == 'body_guide' and body_guide_page then
        body_guide_page:destroy()
        body_guide_page = nil
    elseif current_page == 'body_result' and body_result_page then
        body_result_page:destroy()
        body_result_page = nil
        body_data_container = nil
    elseif current_page == 'report' and report_page then
        report_page:destroy()
        report_page = nil
        report_bmi_grid = nil
        report_body_grid = nil
    end
end

local function hide_all_pages()
    destroy_current_page()
end

local function stop_countdown()
    if countdown_interval then
        sys.timerStop(countdown_interval)
        countdown_interval = nil
    end
end

local function update_countdown_buttons()
    local btn_text = '退出'
    if countdown_seconds > 0 then
        btn_text = '退出[' .. countdown_seconds .. 's]'
    end
end

local function start_countdown(seconds)
    stop_countdown()
    countdown_seconds = seconds
    update_countdown_buttons()
    
    countdown_interval = sys.timerLoopStart(function()
        countdown_seconds = countdown_seconds - 1
        update_countdown_buttons()
        
        if countdown_seconds <= 0 then
            stop_countdown()
            if current_page == 'menu' then
                show_page('home')
            elseif current_page == 'stature_result' then
                show_page('home')
            elseif current_page == 'body_guide' then
                show_page('menu')
            elseif current_page == 'body_result' then
                show_page('home')
            elseif current_page == 'report' then
                show_page('home')
            else
                show_page('home')
            end
            is_full_measuring = false
            full_measure_step = 0
        end
    end, 1000)
end

local function create_home_page()
    home_page = airui.container({
        parent = page_container,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xFFFFFF
    })
    
    local top_bar = airui.container({
        parent = home_page,
        x = 0,
        y = 0,
        w = 480,
        h = 50,
        color = 0x5BA3D9
    })
    
    local back_btn = airui.button({
        parent = top_bar,
        x = 16,
        y = 10,
        w = 96,
        h = 32,
        text = '返回',
        font_size = 14,
        style = {
            bg_color = 0x40404040,
            pressed_bg_color = 0x60606060,
            text_color = 0xFFFFFF,
            radius = 15
        },
        on_click = function()
            log.info("weight_win", "点击返回，关闭APP")
            if win_id then
                exwin.close(win_id)
            end
        end
    })
    
    local datetime_label = airui.label({
        parent = top_bar,
        x = 80,
        y = 16,
        w = 390,
        h = 19,
        text = '',
        font_size = 12,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    local function update_datetime()
        if datetime_label then
            local t = os.date('*t')
            datetime_label:set_text(string.format('%04d-%02d-%02d %02d:%02d', t.year, t.month, t.day, t.hour, t.min))
        end
    end
    
    update_datetime()
    if datetime_timer then
        sys.timerStop(datetime_timer)
    end
    datetime_timer = sys.timerLoopStart(update_datetime, 60000)
    
    local click_area = airui.container({
        parent = home_page,
        x = 0,
        y = 50,
        w = 480,
        h = 672,
        color = 0xFFFFFF,
        on_click = function()
            show_page('menu')
        end
    })
    
    airui.image({
        parent = click_area,
        x = 80,
        y = 120,
        w = 320,
        h = 320,
        src = '/luadb/home_img.png',
        opacity = 255
    })
    
    airui.label({
        parent = click_area,
        x = 0,
        y = 480,
        w = 480,
        h = 80,
        text = '点击开始体检',
        font_size = 18,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local footer = airui.container({
        parent = home_page,
        x = 0,
        y = 722,
        w = 480,
        h = 78,
        color = 0x5BA3D9
    })
    
    airui.label({
        parent = footer,
        x = 0,
        y = 32,
        w = 480,
        h = 32,
        text = '欢迎使用智能健康体检一体机，请站上设备开始体检',
        font_size = 15,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    if show_splash then
        local splash_overlay
        
        local function hide_splash()
            show_splash = false
            if splash_overlay then
                splash_overlay:destroy()
            end
        end
        
        splash_overlay = airui.container({
            parent = home_page,
            x = 0,
            y = 0,
            w = 480,
            h = 800,
            color = 0xFFFFFF,
            on_click = hide_splash
        })
        
        local icon_container = airui.container({
            parent = splash_overlay,
            x = 120,
            y = 281,
            w = 240,
            h = 240,
            color = 0xE0F0FF,
            radius = 120,
            on_click = hide_splash
        })
        
        airui.label({
            parent = icon_container,
            x = 0,
            y = 80,
            w = 240,
            h = 80,
            -- text = '💪',
            text = '体检开始',
            font_size = 60,
            color = 0x5BA3D9,
            align = airui.TEXT_ALIGN_CENTER
        })
        
        airui.label({
            parent = splash_overlay,
            x = 0,
            y = 560,
            w = 480,
            h = 40,
            text = '点击图标开始',
            font_size = 17,
            color = 0x5BA3D9,
            align = airui.TEXT_ALIGN_CENTER
        })
    end
end

local function show_user_modal(callback)
    if modal_container then
        modal_container:destroy()
    end
    
    selected_gender = user_gender
    age_str = tostring(user_age or age_str)
    modal_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0x00000000
    })
    
    -- local overlay = airui.container({
    --     parent = modal_container,
    --     x = 0,
    --     y = 0,
    --     w = 480,
    --     h = 800,
    --     color = 0x000000,
    --     opacity = 150
    -- })
    
    local modal_content = airui.container({
        parent = modal_container,
        x = 60,
        y = 281,
        w = 360,
        h = 320,
        color = 0xFFFFFF,
        radius = 20
    })
    
    local modal_header = airui.container({
        parent = modal_content,
        x = 0,
        y = 0,
        w = 360,
        h = 48,
        color = 0x5BA3D9
    })
    
    airui.label({
        parent = modal_header,
        x = 0,
        y = 12,
        w = 360,
        h = 24,
        text = '完善用户信息',
        font_size = 14,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local modal_body = airui.container({
        parent = modal_content,
        x = 0,
        y = 48,
        w = 360,
        h = 272,
        color = 0xFFFFFF
    })
    
    airui.label({
        parent = modal_body,
        x = 19,
        y = 16,
        w = 320,
        h = 19,
        text = '年龄',
        font_size = 12,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })

    local age_keyboard = airui.keyboard({
        mode = 'numeric',
        auto_hide = true,
        preview = true,
        preview_height = 32,
        x = 0,
        w = 360,
        h = 160,
        on_commit = function(self)
            if modal_age_input then
                age_str = modal_age_input:get_text() or age_str
                modal_age_input:set_text(age_str)
            end
            self:hide()
        end
    })
    
    modal_age_input = airui.textarea({
        parent = modal_body,
        x = 19,
        y = 44,
        w = 322,
        h = 40,
        text = age_str,
        font_size = 15,
        color = 0x333333,
        background_color = 0xF5F5F5,
        border_color = 0xCCCCCC,
        radius = 9,
        align = airui.TEXT_ALIGN_CENTER,
        keyboard = age_keyboard,
        on_click = function()
            if age_keyboard and age_keyboard.show then
                age_keyboard:show()
            end
        end
    })
    
    airui.label({
        parent = modal_body,
        x = 19,
        y = 96,
        w = 320,
        h = 19,
        text = '性别',
        font_size = 12,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    local male_btn, female_btn, male_label, female_label
    
    local function update_gender_buttons()
        if male_btn then
            if male_btn.set_color then
                male_btn:set_color(selected_gender == "男" and 0x2196F3 or 0xF5F5F5)
            end
            if male_label and male_label.set_color then
                male_label:set_color(selected_gender == "男" and 0xFFFFFF or 0x333333)
            end
        end
        if female_btn then
            if female_btn.set_color then
                female_btn:set_color(selected_gender == "女" and 0x2196F3 or 0xF5F5F5)
            end
            if female_label and female_label.set_color then
                female_label:set_color(selected_gender == "女" and 0xFFFFFF or 0x333333)
            end
        end
        -- 强制重绘
        if modal_container and modal_container.invalidate then
            modal_container:invalidate()
        end
    end
    
    local male_color = selected_gender == "男" and 0x2196F3 or 0xF5F5F5
    local male_text_color = selected_gender == "男" and 0xFFFFFF or 0x333333
    male_btn = airui.container({
        parent = modal_body,
        x = 19,
        y = 124,
        w = 152,
        h = 40,
        color = male_color,
        radius = 24,
        on_click = function()
            selected_gender = "男"
            update_gender_buttons()
        end
    })
    male_label = airui.label({
        parent = male_btn,
        x = 0,
        y = 11,
        w = 152,
        h = 18,
        text = "男",
        color = male_text_color,
        font_size = 12,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local female_color = selected_gender == "女" and 0x2196F3 or 0xF5F5F5
    local female_text_color = selected_gender == "女" and 0xFFFFFF or 0x333333
    female_btn = airui.container({
        parent = modal_body,
        x = 189,
        y = 124,
        w = 152,
        h = 40,
        color = female_color,
        radius = 24,
        on_click = function()
            selected_gender = "女"
            update_gender_buttons()
        end
    })
    female_label = airui.label({
        parent = female_btn,
        x = 0,
        y = 11,
        w = 152,
        h = 18,
        text = "女",
        color = female_text_color,
        font_size = 12,
        align = airui.TEXT_ALIGN_CENTER
    })

    local skip_btn = airui.button({
        parent = modal_body,
        x = 19,
        y = 184,
        w = 152,
        h = 40,
        text = '跳过',
        font_size = 12,
        style = {
            bg_color = 0xCCCCCC,
            pressed_bg_color = 0xBBBBBB,
            text_color = 0x333333,
            radius = 24
        },
        on_click = function()
            if age_keyboard and age_keyboard.hide then
                age_keyboard:hide()
            end
            if modal_container then
                modal_container:destroy()
                modal_container = nil
            end
            if callback then
                callback()
            end
        end
    })
    
    local confirm_btn = airui.button({
        parent = modal_body,
        x = 189,
        y = 184,
        w = 152,
        h = 40,
        text = '确认',
        font_size = 12,
        style = {
            bg_color = 0x5BA3D9,
            pressed_bg_color = 0x4A92C8,
            text_color = 0xFFFFFF,
            radius = 24
        },
        on_click = function()
            if selected_gender then
                user_gender = selected_gender
            end
            if modal_age_input then
                local input_age = tonumber(modal_age_input:get_text())
                if input_age and input_age > 0 then
                    user_age = input_age
                    age_str = tostring(input_age)
                end
            end
            if age_keyboard and age_keyboard.hide then
                age_keyboard:hide()
            end
            if modal_container then
                modal_container:destroy()
                modal_container = nil
            end
            if callback then
                callback()
            end
        end
    })
end

local function create_menu_page()
    menu_page = airui.container({
        parent = page_container,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xFFFFFF
    })
    
    local top_bar = airui.container({
        parent = menu_page,
        x = 0,
        y = 0,
        w = 480,
        h = 50,
        color = 0x5BA3D9
    })
    
    local exit_btn = airui.button({
        parent = top_bar,
        x = 16,
        y = 10,
        w = 96,
        h = 32,
        text = '退出',
        font_size = 12,
        style = {
            bg_color = 0x40404040,
            pressed_bg_color = 0x60606060,
            text_color = 0xFFFFFF,
            radius = 19
        },
        on_click = function()
            user_gender = nil
            user_age = nil
            selected_gender = nil
            age_str = "30"
            show_page('home')
        end
    })
    
    airui.label({
        parent = top_bar,
        x = 0,
        y = 13,
        w = 480,
        h = 25,
        text = '健康体检',
        font_size = 17,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local content_area = airui.container({
        parent = menu_page,
        x = 0,
        y = 50,
        w = 480,
        h = 750,
        color = 0xF0F4F8
    })
    
    local menu_grid = airui.container({
        parent = content_area,
        x = 0,
        y = 0,
        w = 480,
        h = 750
    })
    
    local bmi_item = airui.container({
        parent = menu_grid,
        x = 72,
        y = 156,
        w = 144,
        h = 176
    })
    
    local bmi_icon = airui.container({
        parent = bmi_item,
        x = 24,
        y = 0,
        w = 96,
        h = 96,
        color = 0xE0F0FF,
        radius = 48,
        on_click = function()
            show_page('stature_guide')
        end
    })
    
    airui.image({
        parent = bmi_icon,
        x = 0,
        y = 24,
        w = 96,
        h = 48,
        src = '/luadb/HL.png',
        opacity = 255
    })
    
    local bmi_btn = airui.button({
        parent = bmi_item,
        x = 0,
        y = 109,
        w = 144,
        h = 35,
        text = '身高体重',
        font_size = 14,
        style = {
            bg_color = 0x5BA3D9,
            pressed_bg_color = 0x4A92C8,
            text_color = 0xFFFFFF,
            radius = 24
        },
        on_click = function()
            show_page('stature_guide')
        end
    })
    
    local body_item = airui.container({
        parent = menu_grid,
        x = 264,
        y = 156,
        w = 144,
        h = 176
    })
    
    local body_icon = airui.container({
        parent = body_item,
        x = 24,
        y = 0,
        w = 96,
        h = 96,
        color = 0xE0F0FF,
        radius = 48,
        on_click = function()
            if user_gender and user_age then
                show_page('body_guide')
            else
                show_user_modal(function()
                    show_page('body_guide')
                end)
            end
        end
    })
    
    airui.image({
        parent = body_icon,
        x = 0,
        y = 24,
        w = 96,
        h = 48,
        src = '/luadb/ch.png',
        opacity = 255
    })
    
    local body_btn = airui.button({
        parent = body_item,
        x = 0,
        y = 109,
        w = 144,
        h = 35,
        text = '人体成分',
        font_size = 14,
        style = {
            bg_color = 0x5BA3D9,
            pressed_bg_color = 0x4A92C8,
            text_color = 0xFFFFFF,
            radius = 24
        },
        on_click = function()
            if user_gender and user_age then
                show_page('body_guide')
            else
                show_user_modal(function()
                    show_page('body_guide')
                end)
            end
        end
    })
    
    local full_item = airui.container({
        parent = menu_grid,
        x = 168,
        y = 384,
        w = 144,
        h = 208
    })
    
    local full_icon = airui.container({
        parent = full_item,
        x = 8,
        y = 0,
        w = 128,
        h = 128,
        color = 0xE0F0FF,
        radius = 64,
        on_click = function()
            is_full_measuring = true
            full_measure_step = 1
            show_page('stature_guide')
        end
    })
    
    airui.image({
        parent = full_icon,
        x = 0,
        y = 32,
        w = 128,
        h = 64,
        src = '/luadb/circle.png',
        opacity = 255
    })
    
    local full_btn = airui.button({
        parent = full_item,
        x = 0,
        y = 141,
        w = 144,
        h = 35,
        text = '全部顺序测量',
        font_size = 14,
        style = {
            bg_color = 0x5BA3D9,
            pressed_bg_color = 0x4A92C8,
            text_color = 0xFFFFFF,
            radius = 24
        },
        on_click = function()
            is_full_measuring = true
            full_measure_step = 1
            show_page('stature_guide')
        end
    })
end

local function create_stature_guide_page()
    stature_guide_page = airui.container({
        parent = page_container,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xFFFFFF
    })
    
    local top_bar = airui.container({
        parent = stature_guide_page,
        x = 0,
        y = 0,
        w = 480,
        h = 50,
        color = 0x5BA3D9
    })
    
    local exit_btn = airui.button({
        parent = top_bar,
        x = 16,
        y = 10,
        w = 80,
        h = 32,
        text = '退出',
        font_size = 12,
        style = {
            bg_color = 0x40404040,
            pressed_bg_color = 0x60606060,
            text_color = 0xFFFFFF,
            radius = 19
        },
        on_click = function()
            show_page('menu')
        end
    })
    
    airui.label({
        parent = top_bar,
        x = 0,
        y = 13,
        w = 480,
        h = 25,
        text = '身高体重',
        font_size = 17,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local content_area = airui.container({
        parent = stature_guide_page,
        x = 0,
        y = 50,
        w = 480,
        h = 750,
        color = 0xF0F4F8
    })
    
    local big_icon = airui.container({
        parent = content_area,
        x = 152,
        y = 160,
        w = 176,
        h = 280
    })
    
    local circle_icon = airui.container({
        parent = big_icon,
        x = 0,
        y = 0,
        w = 176,
        h = 176,
        color = 0x8BCBFF,
        radius = 88,
        on_click = function()
            do_stature_measure(function()
                if is_full_measuring then
                    full_measure_step = 2
                    if user_gender and user_age then
                        show_page('body_guide')
                    else
                        show_user_modal(function()
                            show_page('body_guide')
                        end)
                    end
                else
                    show_page('stature_result')
                end
                log.info("circle_icon click!!!!!!!!!!!!!!!!!!", bmi_data)
            end)
        end
    })
    
    -- airui.label({
    --     parent = circle_icon,
    --     x = 0,
    --     y = 48,
    --     w = 176,
    --     h = 80,
    --     -- text = '🧍',
    --     text = '身高体重测量',
    --     font_size = 68,
    --     color = 0xFFFFFF,
    --     align = airui.TEXT_ALIGN_CENTER
    -- })
    airui.image({
        parent = circle_icon,
        x = 0,
        y = 48,
        w = 176,
        h = 80,
        src = '/luadb/HL.png',
        opacity = 255
    })
    
    airui.label({
        parent = big_icon,
        x = 0,
        y = 192,
        w = 176,
        h = 64,
        text = '请站到测量识别区，然后站稳、站直、平视前方',
        font_size = 15,
        color = 0x5BA3D9,
        align = airui.TEXT_ALIGN_CENTER
    })
end

local function create_stature_result_page()
    stature_result_page = airui.container({
        parent = page_container,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xFFFFFF
    })
    
    local top_bar = airui.container({
        parent = stature_result_page,
        x = 0,
        y = 0,
        w = 480,
        h = 50,
        color = 0x5BA3D9
    })
    
    local exit_btn = airui.button({
        parent = top_bar,
        x = 20,
        y = 10,
        w = 96,
        h = 32,
        text = '退出',
        font_size = 12,
        style = {
            bg_color = 0x40404040,
            pressed_bg_color = 0x60606060,
            text_color = 0xFFFFFF,
            radius = 19
        },
        on_click = function()
            user_gender = nil
            user_age = nil
            selected_gender = nil
            age_str = "30"
            show_page('home')
        end
    })
    
    airui.label({
        parent = top_bar,
        x = 0,
        y = 13,
        w = 480,
        h = 25,
        text = '身高体重',
        font_size = 17,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local content_area = airui.container({
        parent = stature_result_page,
        x = 0,
        y = 50,
        w = 480,
        h = 750,
        color = 0xF0F4F8
    })
    
    stature_data_container = airui.container({
        parent = content_area,
        x = 0,
        y = 16,
        w = 480,
        h = 480
    })
    
    local re_measure_btn = airui.button({
        parent = content_area,
        x = 48,
        y = 640,
        w = 160,
        h = 48,
        text = '重新测量',
        font_size = 14,
        style = {
            bg_color = 0xCCCCCC,
            pressed_bg_color = 0xBBBBBB,
            text_color = 0x333333,
            radius = 32
        },
        on_click = function()
            do_stature_measure()
            log.info("重新测量!!!!!!!!!!!!!!!!!!!")
        end
    })
    
    local next_btn = airui.button({
        parent = content_area,
        x = 272,
        y = 640,
        w = 160,
        h = 48,
        text = '下一项',
        font_size = 14,
        style = {
            bg_color = 0x5BA3D9,
            pressed_bg_color = 0x4A92C8,
            text_color = 0xFFFFFF,
            radius = 32
        },
        on_click = function()
            if user_gender and user_age then
                show_page('body_guide')
            else
                show_user_modal(function()
                    show_page('body_guide')
                end)
            end
        end
    })
end

local function create_body_guide_page()
    body_guide_page = airui.container({
        parent = page_container,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xFFFFFF
    })
    
    local top_bar = airui.container({
        parent = body_guide_page,
        x = 0,
        y = 0,
        w = 480,
        h = 50,
        color = 0x5BA3D9
    })
    
    local exit_btn = airui.button({
        parent = top_bar,
        x = 16,
        y = 10,
        w = 96,
        h = 32,
        text = '退出',
        font_size = 12,
        style = {
            bg_color = 0x40404040,
            pressed_bg_color = 0x60606060,
            text_color = 0xFFFFFF,
            radius = 19
        },
        on_click = function()
            show_page('menu')
        end
    })
    
    airui.label({
        parent = top_bar,
        x = 0,
        y = 13,
        w = 480,
        h = 25,
        text = '人体成分',
        font_size = 17,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local content_area = airui.container({
        parent = body_guide_page,
        x = 0,
        y = 50,
        w = 480,
        h = 750,
        color = 0xF0F4F8
    })
    
    local big_icon = airui.container({
        parent = content_area,
        x = 152,
        y = 160,
        w = 176,
        h = 280
    })
    
    local circle_icon = airui.container({
        parent = big_icon,
        x = 0,
        y = 0,
        w = 176,
        h = 176,
        color = 0x8BCBFF,
        radius = 88,
        on_click = function()
            do_body_measure(function()
                if is_full_measuring then
                    show_page('report')
                else
                    show_page('body_result')
                end
            end)
        end
    })
    
    -- airui.label({
    --     parent = circle_icon,
    --     x = 0,
    --     y = 48,
    --     w = 176,
    --     h = 80,
    --     -- text = '✋',
    --     text = '人体成分测量',
    --     font_size = 68,
    --     color = 0xFFFFFF,
    --     align = airui.TEXT_ALIGN_CENTER
    -- })
        airui.image({
        parent = circle_icon,
        x = 0,
        y = 48,
        w = 176,
        h = 80,
        src = '/luadb/ch.png',
        opacity = 255
    })

    airui.label({
        parent = big_icon,
        x = 0,
        y = 192,
        w = 176,
        h = 64,
        text = '请握住把手，手臂伸直，不要晃动',
        font_size = 15,
        color = 0x5BA3D9,
        align = airui.TEXT_ALIGN_CENTER
    })
end

local function create_body_result_page()
    body_result_page = airui.container({
        parent = page_container,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xFFFFFF
    })
    
    local top_bar = airui.container({
        parent = body_result_page,
        x = 0,
        y = 0,
        w = 480,
        h = 50,
        color = 0x5BA3D9
    })
    
    local exit_btn = airui.button({
        parent = top_bar,
        x = 20,
        y = 10,
        w = 96,
        h = 32,
        text = '退出',
        font_size = 12,
        style = {
            bg_color = 0x40404040,
            pressed_bg_color = 0x60606060,
            text_color = 0xFFFFFF,
            radius = 19
        },
        on_click = function()
            user_gender = nil
            user_age = nil
            selected_gender = nil
            age_str = "30"
            show_page('home')
        end
    })
    
    airui.label({
        parent = top_bar,
        x = 0,
        y = 13,
        w = 480,
        h = 25,
        text = '人体成分',
        font_size = 17,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local content_area = airui.container({
        parent = body_result_page,
        x = 0,
        y = 50,
        w = 480,
        h = 750,
        color = 0xF0F4F8
    })
    
    body_data_container = airui.container({
        parent = content_area,
        x = 0,
        y = 16,
        w = 480,
        h = 560
    })
    
    local re_measure_btn = airui.button({
        parent = content_area,
        x = 48,
        y = 640,
        w = 160,
        h = 48,
        text = '重新测量',
        font_size = 14,
        style = {
            bg_color = 0xCCCCCC,
            pressed_bg_color = 0xBBBBBB,
            text_color = 0x333333,
            radius = 32
        },
        on_click = function()
            do_body_measure()
        end
    })
    
    local view_report_btn = airui.button({
        parent = content_area,
        x = 272,
        y = 640,
        w = 160,
        h = 48,
        text = '查看报告',
        font_size = 14,
        style = {
            bg_color = 0x5BA3D9,
            pressed_bg_color = 0x4A92C8,
            text_color = 0xFFFFFF,
            radius = 32
        },
        on_click = function()
            show_page('report')
        end
    })
end

local function create_report_page()
    report_page = airui.container({
        parent = page_container,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xFFFFFF
    })
    
    local top_bar = airui.container({
        parent = report_page,
        x = 0,
        y = 0,
        w = 480,
        h = 50,
        color = 0x5BA3D9
    })
    
    local exit_btn = airui.button({
        parent = top_bar,
        x = 20,
        y = 10,
        w = 96,
        h = 32,
        text = '退出',
        font_size = 12,
        style = {
            bg_color = 0x40404040,
            pressed_bg_color = 0x60606060,
            text_color = 0xFFFFFF,
            radius = 19
        },
        on_click = function()
            user_gender = nil
            user_age = nil
            selected_gender = nil
            age_str = "30"
            show_page('home')
        end
    })
    
    airui.label({
        parent = top_bar,
        x = 0,
        y = 13,
        w = 480,
        h = 25,
        text = '检测报告',
        font_size = 17,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local user_info_label = airui.label({
        parent = top_bar,
        x = 320,
        y = 16,
        w = 144,
        h = 19,
        text = '',
        font_size = 11,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    local function update_user_info()
        if user_gender and user_age then
            user_info_label:set_text(user_gender .. ' ' .. user_age .. '岁')
        else
            user_info_label:set_text('')
        end
    end
    
    update_user_info()
    
    local content_area = airui.container({
        parent = report_page,
        x = 0,
        y = 50,
        w = 480,
        h = 640,
        color = 0xF0F4F8
    })
    
    local bmi_section = airui.container({
        parent = content_area,
        x = 0,
        y = 8,
        w = 480,
        h = 136
    })
    
    airui.label({
        parent = bmi_section,
        x = 24,
        y = 8,
        w = 160,
        h = 24,
        text = '<体质指数>',
        font_size = 15,
        color = 0x5BA3D9,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    report_bmi_grid = airui.container({
        parent = bmi_section,
        x = 16,
        y = 40,
        w = 448,
        h = 120,
        color = 0xFFFFFF,
        radius = 19
    })
    
    local body_section = airui.container({
        parent = content_area,
        x = 0,
        y = 144,
        w = 480,
        h = 136
    })
    
    airui.label({
        parent = body_section,
        x = 24,
        y = 8,
        w = 160,
        h = 24,
        text = '<人体成分>',
        font_size = 15,
        color = 0x5BA3D9,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    report_body_grid = airui.container({
        parent = body_section,
        x = 16,
        y = 40,
        w = 448,
        h = 96,
        color = 0xFFFFFF,
        radius = 19
    })
    
    local footer_bar = airui.container({
        parent = report_page,
        x = 0,
        y = 690,
        w = 480,
        h = 110,
        color = 0x5BA3D9
    })
    
    local qr_container = airui.container({
        parent = footer_bar,
        x = 160,
        y = 16,
        w = 160,
        h = 96
    })
    
    local qr_placeholder = airui.container({
        parent = qr_container,
        x = 48,
        y = 0,
        w = 64,
        h = 64,
        color = 0xFFFFFF,
        radius = 13
    })
    
    airui.label({
        parent = qr_placeholder,
        x = 0,
        y = 19,
        w = 64,
        h = 24,
        text = '微信扫码',
        font_size = 11,
        color = 0x5BA3D9,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    airui.label({
        parent = qr_container,
        x = 0,
        y = 72,
        w = 160,
        h = 24,
        text = '微信扫码 报告直达手机',
        font_size = 12,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
end

local function hide_user_modal()
    if modal_container then
        modal_container:destroy()
        modal_container = nil
    end
    modal_gender_male = nil
    modal_gender_female = nil
end

local function create_ui()
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0xFFFFFF
    })
    
    page_container = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 800
    })
    
    show_page('home')
end

show_page = function(page_name)
    hide_all_pages()
    current_page = page_name
    
    if page_name == 'home' then
        create_home_page()
        stop_countdown()
        if datetime_timer then
            sys.timerStop(datetime_timer)
            datetime_timer = nil
        end
    elseif page_name == 'menu' then
        create_menu_page()
        start_countdown(120)
    elseif page_name == 'stature_guide' then
        create_stature_guide_page()
        start_countdown(120)
    elseif page_name == 'stature_result' then
        create_stature_result_page()
        render_stature_result()
        start_countdown(120)
    elseif page_name == 'body_guide' then
        create_body_guide_page()
        start_countdown(120)
    elseif page_name == 'body_result' then
        create_body_result_page()
        render_body_result()
        start_countdown(120)
    elseif page_name == 'report' then
        create_report_page()
        render_report_bmi()
        render_report_body()
        start_countdown(120)
    end
end

local function on_create()
    create_ui()
end

local function on_destroy()
    stop_countdown()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    page_container = nil
    home_page, menu_page, stature_guide_page, stature_result_page, body_guide_page, body_result_page, report_page = nil, nil, nil, nil, nil, nil, nil
    stature_data_container, body_data_container = nil, nil
    report_bmi_grid, report_body_grid = nil, nil
    modal_container = nil
    win_id = nil
end

local function on_get_focus()
    
end

local function on_lose_focus()
    
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus
    })
end

sys.subscribe("OPEN_WEIGHT_WIN", open_handler)

return {
    show_page = show_page,
    do_stature_measure = do_stature_measure,
    do_body_measure = do_body_measure
}
