
--[[
@module  tpms_dashboard_win
@summary  智能胎压监测系统 - 实时显示四轮胎压和温度
@version 1.0
@date    2026-05-09
@author  马亚丹
]]

local win_id = nil
local main_container = nil

-- UI控件引用
local tire_cards = {}
local tire_card_labels = {}
local tire_containers = {}
local pressure_labels = {}
local temp_labels = {}
local alert_labels = {}
local avg_pressure_label = nil
local max_temp_label = nil
local alert_count_label = nil
local sys_status_label = nil
local led_indicator = nil
local toast_container = nil
local toast_timer = nil

-- 选中状态
local selected_tire_index = nil  -- 当前选中的轮胎索引

-- 轮胎数据
local positions = {
    { id = "FL", label = "左前轮", short = "FL", default_pressure = 36.0, default_temp = 28 },
    { id = "FR", label = "右前轮", short = "FR", default_pressure = 36.0, default_temp = 29 },
    { id = "RL", label = "左后轮", short = "RL", default_pressure = 34.5, default_temp = 27 },
    { id = "RR", label = "右后轮", short = "RR", default_pressure = 34.5, default_temp = 28 }
}

local tires_data = {}

-- 报警阈值配置
local ALERT_CONFIG = {
    pressure_low_warning = 30,
    pressure_low_critical = 28,
    pressure_high_warning = 44,
    pressure_high_critical = 48,
    temp_warning = 58,
    temp_critical = 65
}

-- 评估轮胎报警状态
local function evaluate_alert(tire)
    local pressure = tire.pressure
    local temp = tire.temp
    local alert_level = "normal" -- normal, warning, critical
    local reasons = {}
    
    if pressure < ALERT_CONFIG.pressure_low_warning then
        table.insert(reasons, "低压")
    end
    if pressure < ALERT_CONFIG.pressure_low_critical then
        table.insert(reasons, "严重低压")
    end
    if pressure > ALERT_CONFIG.pressure_high_warning then
        table.insert(reasons, "高压")
    end
    if pressure > ALERT_CONFIG.pressure_high_critical then
        table.insert(reasons, "严重高压")
    end
    
    if temp > ALERT_CONFIG.temp_warning then
        table.insert(reasons, "高温")
    end
    if temp > ALERT_CONFIG.temp_critical then
        table.insert(reasons, "严重高温")
    end
    
    if #reasons > 0 then
        for _, r in ipairs(reasons) do
            if r:find("严重") then
                alert_level = "critical"
                break
            end
            alert_level = "warning"
        end
    end
    
    local alert_msg = table.concat(reasons, ",")
    return { level = alert_level, msg = alert_msg, has_alert = alert_level ~= "normal" }
end

-- 获取颜色配置
local function get_color_config()
    return {
        normal = { text = 0x10B981, bg = 0x10B98126 },
        warning = { text = 0xF97316, bg = 0xF9731626 },
        critical = { text = 0xEF4444, bg = 0xEF444426 },
        white = 0xF0F9FF,
        dark_text = 0x1E293B,
        primary = 0x2563EB,
        warning_btn = 0xB45309,
        card_bg = 0x141C26CC,
        header_bg = 0x0C121C,
        stats_bg = 0x0A1017AA,
        container_bg = 0x1A2634
    }
end

-- 显示临时提示
local function show_toast(msg, color)
    if toast_container then
        toast_container:destroy()
        toast_container = nil
    end
    
    if toast_timer then
        sys.timerStop(toast_timer)
        toast_timer = nil
    end
    
    local colors = get_color_config()
    local border_color = color or colors.primary
    local text_color = colors.white
    local bg_color = colors.stats_bg
    
    -- 根据状态调整颜色
    if color == colors.critical.text then
        bg_color = 0xEF4444FF
        text_color = 0xFFF4E0
    elseif color == colors.warning.text or color == colors.warning_btn then
        bg_color = colors.warning_btn
        border_color = colors.warning_btn
        text_color = 0xFFF4E0
    end
    
    toast_container = airui.container({
        parent = main_container,
        x = 80,
        y = 100,
        w = 320,
        h = 45,
        color = bg_color,
        radius = 22,
        border_color = border_color,
        border_width = 2
    })
    
    airui.label({
        parent = toast_container,
        x = 15,
        y = 12,
        w = 290,
        h = 21,
        text = msg,
        font_size = 12,
        color = text_color,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    toast_timer = sys.timerStart(function()
        if toast_container then
            toast_container:destroy()
            toast_container = nil
        end
        toast_timer = nil
    end, 1800)
end

-- 更新统计数据
local function update_stats()
    if not exwin.is_active(win_id) then return end
    
    local total_pressure = 0
    local max_temp = -math.huge
    local alert_count = 0
    local has_critical = false
    
    for _, tire in ipairs(tires_data) do
        total_pressure = total_pressure + tire.pressure
        if tire.temp > max_temp then
            max_temp = tire.temp
        end
        local alert = evaluate_alert(tire)
        if alert.has_alert then
            alert_count = alert_count + 1
            if alert.level == "critical" then
                has_critical = true
            end
        end
    end
    
    local avg_pressure = total_pressure / #tires_data
    
    if avg_pressure_label then
        avg_pressure_label:set_text(string.format("%.1f", avg_pressure))
    end
    if max_temp_label then
        max_temp_label:set_text(tostring(max_temp ~= -math.huge and max_temp or "--"))
    end
    if alert_count_label then
        alert_count_label:set_text(tostring(alert_count))
    end
    
    if sys_status_label and led_indicator then
        local colors = get_color_config()
        
        -- 如果有选中的轮胎，显示选中轮胎的状态
        if selected_tire_index then
            local tire = tires_data[selected_tire_index]
            local alert = evaluate_alert(tire)
            
            if alert.has_alert then
                if alert.level == "critical" then
                    sys_status_label:set_text(tire.label .. " 严重警报")
                    sys_status_label:set_color(colors.critical.text)
                    led_indicator:set_color(colors.critical.text)
                else
                    sys_status_label:set_text(tire.label .. " 异常")
                    sys_status_label:set_color(colors.warning.text)
                    led_indicator:set_color(colors.warning.text)
                end
            else
                sys_status_label:set_text(tire.label .. " 正常")
                sys_status_label:set_color(colors.normal.text)
                led_indicator:set_color(colors.normal.text)
            end
        else
            -- 没有选中轮胎，显示全局状态
            if alert_count > 0 then
                if has_critical then
                    sys_status_label:set_text("严重警报！")
                    sys_status_label:set_color(colors.critical.text)
                    led_indicator:set_color(colors.critical.text)
                else
                    sys_status_label:set_text("胎压/温度异常")
                    sys_status_label:set_color(colors.warning.text)
                    led_indicator:set_color(colors.warning.text)
                end
            else
                sys_status_label:set_text("全轮正常  安全行驶")
                sys_status_label:set_color(colors.normal.text)
                led_indicator:set_color(colors.normal.text)
            end
        end
    end
end

-- 更新单个轮胎UI
local function update_tire_ui(index)
    if not exwin.is_active(win_id) then return end
    
    local tire = tires_data[index]
    local alert = evaluate_alert(tire)
    local colors = get_color_config()
    
    if pressure_labels[index] then
        local text_color = colors.white
        if alert.level == "warning" then
            text_color = colors.warning.text
        elseif alert.level == "critical" then
            text_color = colors.critical.text
        end
        pressure_labels[index]:set_text(string.format("%.1f", tire.pressure))
        pressure_labels[index]:set_color(text_color)
    end
    
    if temp_labels[index] then
        temp_labels[index]:set_text(string.format("%d °C", tire.temp))
    end
    
    if alert_labels[index] and alert_icons and alert_icons[index] then
        local bg_color = 0x10B98126
        local text_color = colors.normal.text
        local text = "正常"
        local icon_src = "/luadb/check_mark.png"
        
        if alert.has_alert then
            if alert.level == "critical" then
                bg_color = colors.critical.bg
                text_color = 0xFFF4E0
                text = alert.msg
                icon_src = "/luadb/warning.png"
            else
                bg_color = colors.warning.bg
                text_color = 0xFFF4E0
                text = alert.msg
                icon_src = "/luadb/warning.png"
            end
        end
        
        alert_labels[index]:set_text(text)
        alert_labels[index]:set_color(text_color)
        alert_icons[index]:set_src(icon_src)
    end
    
    if tire_cards[index] then
        -- 先确定基础背景色
        local bg_color = colors.card_bg
        if alert.level == "critical" then
            bg_color = 0xEF44441A  -- 严重警告背景色
        elseif alert.level == "warning" then
            bg_color = 0xF973161A  -- 警告背景色
        end
        
        -- 如果是选中状态，优先使用选中效果（在警告基础上叠加蓝色）
        if selected_tire_index == index then
            if alert.level == "critical" then
                bg_color = 0x2563EB33  -- 选中+严重警告
            elseif alert.level == "warning" then
                bg_color = 0x2563EB22  -- 选中+警告
            else
                bg_color = 0x2563EB40  -- 选中+正常
            end
        end
        
        tire_cards[index]:set_color(bg_color)
    end
    
    -- 更新标签容器的选中状态
    if tire_card_labels[index] then
        local label_bg = 0x2C3E4E
        if selected_tire_index == index then
            label_bg = 0x2563EB  -- 选中蓝色
        end
        tire_card_labels[index]:set_color(label_bg)
    end
end

-- 选中轮胎
local function select_tire(index)
    if index < 1 or index > #tires_data then return end
    
    -- 如果点击同一个轮胎，则取消选中
    if selected_tire_index == index then
        selected_tire_index = nil
        show_toast("已取消选中")
    else
        selected_tire_index = index
        local tire = tires_data[index]
        show_toast("已选中 " .. tire.label)
    end
    
    -- 更新所有轮胎UI（主要是选中效果）
    for i = 1, #tires_data do
        update_tire_ui(i)
    end
    
    -- 更新顶部状态显示
    update_stats()
end

-- 更新所有UI
local function update_all_ui()
    for i = 1, #tires_data do
        update_tire_ui(i)
    end
    update_stats()
end

-- 重置为标准值
local function reset_to_normal()
    local colors = get_color_config()
    
    tires_data = {}
    for _, pos in ipairs(positions) do
        table.insert(tires_data, {
            id = pos.id,
            label = pos.label,
            short = pos.short,
            pressure = pos.default_pressure,
            temp = pos.default_temp
        })
    end
    update_all_ui()
    show_toast("所有轮胎已重置为标准胎压/温度", colors.warning_btn)
end

-- 模拟真实数据刷新
local function simulate_fresh_data()
    local colors = get_color_config()
    
    for i, tire in ipairs(tires_data) do
        local pos = positions[i]
        
        local pressure_delta = (math.random() - 0.5) * 0.6
        local new_pressure = tire.pressure + pressure_delta
        new_pressure = math.max(28, math.min(48, new_pressure))
        new_pressure = math.floor(new_pressure * 10) / 10
        
        local temp_delta = (math.random() - 0.5) * 1.8
        local new_temp = tire.temp + temp_delta
        new_temp = math.max(22, math.min(72, math.floor(new_temp)))
        
        tire.pressure = new_pressure
        tire.temp = new_temp
    end
    update_all_ui()
    show_toast("📡 传感器数据刷新 (模拟正常波动)", colors.warning_btn)
end

-- 模拟选中轮胎漏气
local function simulate_leak()
    local colors = get_color_config()
    
    if not selected_tire_index then
        show_toast("请先点击选中一个轮胎!", colors.warning_btn)
        return
    end
    
    local tire = tires_data[selected_tire_index]
    tire.pressure = tire.pressure - 1.8
    if tire.pressure < 22 then tire.pressure = 22 end
    tire.pressure = math.floor(tire.pressure * 10) / 10
    tire.temp = tire.temp + 1
    if tire.temp > 72 then tire.temp = 72 end
    
    update_all_ui()
    show_toast(tire.label .. "快速漏气模拟! 胎压骤降", colors.warning_btn)
end

-- 手动调整轮胎气压
local function adjust_tire_pressure(index, delta)
    if index < 1 or index > #tires_data then return end
    
    local tire = tires_data[index]
    tire.pressure = tire.pressure + delta
    if tire.pressure < 20 then tire.pressure = 20 end
    if tire.pressure > 55 then tire.pressure = 55 end
    tire.pressure = math.floor(tire.pressure * 10) / 10
    
    if math.abs(delta) > 0.1 then
        local temp_delta = delta > 0 and 0.3 or -0.2
        tire.temp = tire.temp + temp_delta
        tire.temp = math.max(18, math.min(78, math.floor(tire.temp)))
    end
    
    update_all_ui()
    show_toast(tire.label .. " 胎压 " .. (delta > 0 and "+" or "") .. string.format("%.1f", delta) .. " PSI")
end

-- 创建轮胎卡片
local function create_tire_card(parent, x, y, index)
    local colors = get_color_config()
    local tire = tires_data[index]
    
    local card = airui.container({
        parent = parent,
        x = x,
        y = y,
        w = 210,
        h = 240,
        color = colors.card_bg,
        radius = 38,
        border_width = 1,
        border_color = 0xFFFFFF14,
        on_click = function()
            select_tire(index)
        end
    })
    
    tire_cards[index] = card
    
    -- 轮胎标签
    local label_container = airui.container({
        parent = card,
        x = 47,
        y = 20,
        w = 116,
        h = 36,
        color = 0x2C3E4E,
        radius = 18
    })
    
    tire_card_labels[index] = label_container
    
    airui.label({
        parent = label_container,
        x = 0,
        y = 8,
        w = 116,
        h = 20,
        text = tire.label,
        font_size = 16,
        color = 0xD9EAFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 胎压显示区域
    local pressure_container = airui.container({
        parent = card,
        x = 20,
        y = 60,
        w = 170,
        h = 60
    })
    
    local pressure_label = airui.label({
        parent = pressure_container,
        x = 0,
        y = 0,
        w = 120,
        h = 50,
        text = string.format("%.1f", tire.pressure),
        font_size = 42,
        color = colors.white,
        align = airui.TEXT_ALIGN_RIGHT
    })
    pressure_labels[index] = pressure_label
    
    airui.label({
        parent = pressure_container,
        x = 125,
        y = 25,
        w = 45,
        h = 20,
        text = "PSI",
        font_size = 14,
        color = 0x8AAEC0,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 温度显示
    local temp_container = airui.container({
        parent = card,
        x = 40,
        y = 125,
        w = 130,
        h = 36,
        color = 0x0F161F,
        radius = 18
    })
    
    airui.image({
        parent = temp_container,
        x = 18,
        y = 12,
        w = 12,
        h = 12,
        src = "/luadb/thermometer.png"
    })
    
    local temp_label = airui.label({
        parent = temp_container,
        x = 38,
        y = 8,
        w = 100,
        h = 20,
        text = string.format("%d °C", tire.temp),
        font_size = 15,
        color = 0xBDD4FF,
        align = airui.TEXT_ALIGN_CENTER
    })
    temp_labels[index] = temp_label
    
    -- 报警标签容器
    local alert_container = airui.container({
        parent = card,
        x = 20,
        y = 168,
        w = 170,
        h = 28
    })
    
    -- 状态图标
    local alert_icon = airui.image({
        parent = alert_container,
        x = 38,
        y = 8,
        w = 12,
        h = 12,
        src = "/luadb/check_mark.png"
    })
    alert_icons = alert_icons or {}
    alert_icons[index] = alert_icon
    
    -- 状态文本
    local alert_label = airui.label({
        parent = alert_container,
        x = 55,
        y = 4,
        w = 100,
        h = 20,
        text = "正常",
        font_size = 11,
        color = colors.normal.text,
        align = airui.TEXT_ALIGN_LEFT
    })
    alert_labels[index] = alert_label
    
    -- 调整按钮
    local btn_container = airui.container({
        parent = card,
        x = 20,
        y = 200,
        w = 170,
        h = 30
    })
    
    -- 减号按钮
    local minus_btn = airui.container({
        parent = btn_container,
        x = 35,
        y = 0,
        w = 40,
        h = 30,
        color = 0x2C3E4E,
        radius = 15,
        on_click = function()
            adjust_tire_pressure(index, -0.2)
        end
    })
    airui.label({
        parent = minus_btn,
        x = 0,
        y = 5,
        w = 40,
        h = 20,
        text = "-0.2",
        font_size = 11,
        color = 0xBBD4FF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 加号按钮
    local plus_btn = airui.container({
        parent = btn_container,
        x = 95,
        y = 0,
        w = 40,
        h = 30,
        color = 0x2C3E4E,
        radius = 15,
        on_click = function()
            adjust_tire_pressure(index, 0.2)
        end
    })
    airui.label({
        parent = plus_btn,
        x = 0,
        y = 5,
        w = 40,
        h = 20,
        text = "+0.2",
        font_size = 11,
        color = 0xBBD4FF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    return card
end

-- 创建UI
local function create_ui()
    local colors = get_color_config()
    
    -- 主容器
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = colors.container_bg,
        scrollable = false
    })
    
    -- 主卡片背景
    local dashboard = airui.container({
        parent = main_container,
        x = 15,
        y = 30,
        w = 450,
        h = 740,
        color = colors.header_bg,
        radius = 56,
        border_width = 1,
        border_color = 0xFFFFFF1F
    })
    
    -- ========== 顶部标题栏 ==========
    local header_container = airui.container({
        parent = dashboard,
        x = 25,
        y = 25,
        w = 400,
        h = 40
    })
    
    -- 标题
    airui.image({
        parent = header_container,
        x = 0,
        y = 9,
        w = 12,
        h = 12,
        src = "/luadb/fuel_pump.png"
    })
    
    airui.label({
        parent = header_container,
        x = 20,
        y = 5,
        w = 250,
        h = 30,
        text = "TPMS 灵眸胎压",
        font_size = 22,
        color = 0xEEF5FF,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 状态徽章
    local status_badge = airui.container({
        parent = header_container,
        x = 250,
        y = 5,
        w = 150,
        h = 30,
        color = 0x1E2A3A,
        radius = 15,
        border_width = 1,
        border_color = 0x508CC866
    })
    
    -- LED指示灯
    led_indicator = airui.container({
        parent = status_badge,
        x = 10,
        y = 10,
        w = 10,
        h = 10,
        color = colors.normal.text,
        radius = 5
    })
    
    sys_status_label = airui.label({
        parent = status_badge,
        x = 28,
        y = 5,
        w = 115,
        h = 20,
        text = "实时监测",
        font_size = 10,
        color = 0xB9E6FF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- ========== 轮胎网格区域 ==========
    local tires_container = airui.container({
        parent = dashboard,
        x = 10,
        y = 85,
        w = 430,
        h = 500
    })
    
    -- 创建4个轮胎卡片（2x2布局）
    create_tire_card(tires_container, 5, 5, 1)
    create_tire_card(tires_container, 225, 5, 2)
    create_tire_card(tires_container, 5, 255, 3)
    create_tire_card(tires_container, 225, 255, 4)
    
    -- ========== 统计数据栏 ==========
    local stats_container = airui.container({
        parent = dashboard,
        x = 20,
        y = 595,
        w = 410,
        h = 60,
        color = colors.stats_bg,
        radius = 30,
        border_width = 1,
        border_color = 0x2C3E50
    })
    
    -- 平均胎压
    local avg_container = airui.container({
        parent = stats_container,
        x = 0,
        y = 10,
        w = 136,
        h = 40
    })
    
    airui.label({
        parent = avg_container,
        x = 0,
        y = 0,
        w = 136,
        h = 16,
        text = "平均胎压",
        font_size = 10,
        color = 0x88A0BB,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    avg_pressure_label = airui.label({
        parent = avg_container,
        x = 0,
        y = 16,
        w = 100,
        h = 24,
        text = "--",
        font_size = 18,
        color = 0xC7E2FF,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    airui.label({
        parent = avg_container,
        x = 102,
        y = 22,
        w = 30,
        h = 14,
        text = "psi",
        font_size = 9,
        color = 0x88A0BB,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 最高温度
    local max_temp_container = airui.container({
        parent = stats_container,
        x = 137,
        y = 10,
        w = 136,
        h = 40
    })
    
    airui.label({
        parent = max_temp_container,
        x = 0,
        y = 0,
        w = 136,
        h = 16,
        text = "最高温度",
        font_size = 10,
        color = 0x88A0BB,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    max_temp_label = airui.label({
        parent = max_temp_container,
        x = 0,
        y = 16,
        w = 100,
        h = 24,
        text = "--",
        font_size = 18,
        color = 0xC7E2FF,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    airui.label({
        parent = max_temp_container,
        x = 102,
        y = 22,
        w = 30,
        h = 14,
        text = "°C",
        font_size = 9,
        color = 0x88A0BB,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 报警总数
    local alert_container = airui.container({
        parent = stats_container,
        x = 274,
        y = 10,
        w = 136,
        h = 40
    })
    
    airui.label({
        parent = alert_container,
        x = 0,
        y = 0,
        w = 136,
        h = 16,
        text = "报警总数",
        font_size = 10,
        color = 0x88A0BB,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    alert_count_label = airui.label({
        parent = alert_container,
        x = 0,
        y = 16,
        w = 136,
        h = 24,
        text = "0",
        font_size = 18,
        color = 0xC7E2FF,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- ========== 操作按钮区 ==========
    local btn_container = airui.container({
        parent = dashboard,
        x = 20,
        y = 670,
        w = 410,
        h = 50
    })
    
    -- 刷新按钮
    local refresh_btn = airui.container({
        parent = btn_container,
        x = 0,
        y = 5,
        w = 126,
        h = 40,
        color = colors.primary,
        radius = 22,
        on_click = simulate_fresh_data
    })
    
    airui.image({
        parent = refresh_btn,
        x = 18,
        y = 14,
        w = 12,
        h = 12,
        src = "/luadb/refresh.png"
    })
    
    airui.label({
        parent = refresh_btn,
        x = 38,
        y = 10,
        w = 80,
        h = 20,
        text = "模拟刷新",
        font_size = 14,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 重置按钮
    local reset_btn = airui.container({
        parent = btn_container,
        x = 142,
        y = 5,
        w = 126,
        h = 40,
        color = 0x1F2A36,
        radius = 22,
        border_width = 1,
        border_color = 0xFFFFFF1A,
        on_click = reset_to_normal
    })
    
    airui.image({
        parent = reset_btn,
        x = 18,
        y = 14,
        w = 12,
        h = 12,
        src = "/luadb/check_mark.png"
    })
    
    airui.label({
        parent = reset_btn,
        x = 38,
        y = 10,
        w = 80,
        h = 20,
        text = "重置标准",
        font_size = 14,
        color = 0xE2EFFF,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 模拟漏气按钮
    local leak_btn = airui.container({
        parent = btn_container,
        x = 284,
        y = 5,
        w = 126,
        h = 40,
        color = colors.warning_btn,
        radius = 22,
        on_click = simulate_leak
    })
    
    airui.image({
        parent = leak_btn,
        x = 18,
        y = 14,
        w = 12,
        h = 12,
        src = "/luadb/warning.png"
    })
    
    airui.label({
        parent = leak_btn,
        x = 40,
        y = 10,
        w = 80,
        h = 20,
        text = "模拟漏气",
        font_size = 14,
        color = 0xE2EFFF,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- ========== 底部说明 ==========
    airui.label({
        parent = dashboard,
        x = 0,
        y = 720,
        w = 450,
        h = 15,
        text = "点击轮胎选中 | 点击+-微调胎压 | 异常实时预警",
        font_size = 9,
        color = 0x4F6F8F,
        align = airui.TEXT_ALIGN_CENTER
    })
end

-- 窗口生命周期管理
local function on_create()
    -- 初始化轮胎数据
    reset_to_normal()
    -- 创建UI
    create_ui()
    -- 初始更新UI
    update_all_ui()
end

local function on_destroy()
    if toast_timer then
        sys.timerStop(toast_timer)
        toast_timer = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
    tire_cards = {}
    pressure_labels = {}
    temp_labels = {}
    alert_labels = {}
end

local function on_get_focus()
    if #tires_data > 0 then
        update_all_ui()
    end
end

local function on_lose_focus()
end

-- 打开窗口
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus
    })
end

sys.subscribe("OPEN_TPMS_DASHBOARD_WIN", open_handler)

return {
    reset_to_normal = reset_to_normal,
    simulate_fresh_data = simulate_fresh_data,
    simulate_leak_fl = simulate_leak_fl,
    adjust_tire_pressure = adjust_tire_pressure
}
