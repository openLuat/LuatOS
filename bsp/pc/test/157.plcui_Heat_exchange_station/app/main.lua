PROJECT = "plcui_heat_station"
VERSION = "0.1.0"

local sys = require("sys")
local xml
local running = false
local tracking = false
local target = 30.0
local tick = 0
local parameter_values = {55.8, 0.52, 0.52, 50.8, 0.52, 55.4, 0.51, 22.9, 0.51, 0.51, 546}
local dates = {start = "2026-11-01", finish = "2026-11-04"}
local columns = {
    {"flow_primary", "一网瞬时流量", true}, {"heat_primary", "一网瞬时热量", true},
    {"volume_primary", "一网累积流量"}, {"total_primary", "一网累积热量"},
    {"flow_secondary", "二网瞬时流量", true}, {"heat_secondary", "二网瞬时热量", true},
    {"volume_secondary", "二网累积流量"}, {"total_secondary", "二网累积热量"},
    {"distribution_frequency", "分布泵频率"}, {"distribution_current", "分布泵电流"},
    {"pump_frequency", "循环泵频率"}, {"pump_current", "循环泵电流"},
    {"makeup_frequency", "补水泵频率"}, {"makeup_current", "补水泵电流"}, {"energy_daily", "一天能耗"}
}
local curve_visible = {
    trends = {target=true, primary=true, secondary=true},
    pressure = {primary=true, return_primary=true, secondary=true, difference=true}
}
local curve_ids = {
    trends = {"target", "primary", "return_primary", "secondary", "return_secondary", "mean", "outdoor"},
    pressure = {"primary", "primary2", "return_primary", "secondary", "return_secondary", "return_secondary2", "difference"}
}

local function update_pump()
    xml:find("main", "pump_control"):set_checked(running)
    xml:find("main", "pump_current"):set_text(running and "3.8 A" or "0.0 A")
    xml:find("main", "pump_frequency"):set_text(running and "42.0 Hz" or "0.0 Hz")
end

local function update_columns(queried)
    local data = xml:find("records", "energy_table")
    local selected = {}
    for _, column in ipairs(columns) do
        xml:find("records", "column_" .. column[1]):set_checked(column[3] == true)
        if column[3] and #selected < 4 then selected[#selected + 1] = column end
    end
    for column = 1, 4 do
        data:set_cell(1, column + 1, selected[column] and selected[column][2] or "")
        for row = 2, 22 do
            data:set_cell(row, column + 1, selected[column] and (queried and string.format("%.2f", 13.65 + (column - 1) * 0.21) or "0") or "")
        end
    end
end

local function update_curves(page)
    local chart = xml:find(page, "history_chart")
    for _, id in ipairs(curve_ids[page]) do
        local visible = curve_visible[page][id] == true
        chart:set_series_hidden(id, not visible)
        xml:find(page, "curve_" .. id):set_checked(visible)
        xml:find(page, "legend_" .. id):set_hidden(not visible)
    end
end

local function save_field(event)
    local page = plcui.status().page
    if page == "parameters" then
        local row = event.id:match("^upper_(%d+)$") or event.id:match("^lower_(%d+)$")
        if row then
            local upper = tonumber(xml:find(page, "upper_" .. row):get_text())
            local lower = tonumber(xml:find(page, "lower_" .. row):get_text())
            local value = parameter_values[tonumber(row) + 1]
            local alarm = "参数设置错误"
            if upper and lower and upper > lower then
                alarm = value > upper and "超上限报警" or value < lower and "超下限报警" or "正常"
            end
            xml:find(page, "alarm_" .. row):set_text(alarm)
            xml:find(page, "alarm_" .. row):set_hidden(alarm == "正常" or alarm == "参数设置错误")
            xml:find(page, "alarm_normal_" .. row):set_hidden(alarm ~= "正常")
            xml:find(page, "alarm_error_" .. row):set_hidden(alarm ~= "参数设置错误")
        end
    elseif page == "main" then
        local value = tonumber(event.text)
        if value and value >= 0 and value <= 70 then target = value end
        xml:find(page, "setpoint"):set_text(string.format("%.1f", target))
        xml:find(page, "setpoint_feedback"):set_text(string.format("输出结果:%.1f℃", target))
    else
        dates[event.id == "date_start" and "start" or "finish"] = event.text
    end
end

local function update_page()
    local page = plcui.status().page
    xml:find(page, "navigation"):set_hidden(true)
    if page == "main" or page == "parameters" then
        xml:find(page, "clock"):set_text(os.date("%Y/%m/%d %H:%M:%S"))
    else
        xml:find(page, "date_start"):set_text(dates.start)
        xml:find(page, "date_end"):set_text(dates.finish)
    end
    if page == "main" then
        update_pump()
        xml:find(page, "tracking_switch"):set_checked(tracking)
        xml:find(page, "setpoint"):set_text(string.format("%.1f", target))
    elseif page == "records" then
        update_columns(false)
    elseif page == "trends" or page == "pressure" then
        update_curves(page)
    end
end

local function show_page(page)
    xml:show(page)
    -- 回调中的切页延后执行，下一轮再查找新页面组件。
    sys.timerStart(update_page, 30)
end

sys.taskInit(function()
    plcui.init({width = 1024, height = 600})
    xml = plcui.load("/luadb/main.xml", {handlers = {
        toggle_menu = function()
            local menu = xml:find(plcui.status().page, "navigation")
            menu:set_hidden(not menu:state().hidden)
        end,
        show_main = function() show_page("main") end,
        show_parameters = function() show_page("parameters") end,
        show_records = function() show_page("records") end,
        show_trends = function() show_page("trends") end,
        show_pressure = function() show_page("pressure") end,
        toggle_pump = function() running = not running update_pump() end,
        toggle_tracking = function()
            tracking = not tracking
            xml:find("main", "tracking_switch"):set_checked(tracking)
        end,
        setpoint_submit = save_field,
        field_submit = save_field,
        date_submit = save_field,
        field_cancel = function() end,
        query_data = function()
            local page = plcui.status().page
            dates.start = xml:find(page, "date_start"):get_text()
            dates.finish = xml:find(page, "date_end"):get_text()
            xml:find(page, "result_count"):set_text("共 267 条")
            if page == "records" then update_columns(true) end
        end,
        toggle_column = function(event)
            local key = event.id:sub(8)
            local chosen
            local count = 0
            for _, column in ipairs(columns) do
                if column[1] == key then chosen = column end
                if column[3] then count = count + 1 end
            end
            if not chosen[3] and count >= 4 then
                for _, column in ipairs(columns) do if column[3] then column[3] = false break end end
            end
            chosen[3] = not chosen[3]
            update_columns(false)
        end,
        toggle_curve = function(event)
            local page = plcui.status().page
            local id = event.id:gsub("^curve_", ""):gsub("^legend_", "")
            curve_visible[page][id] = not curve_visible[page][id]
            update_curves(page)
        end
    }})
    update_page()

    -- 模拟寄存器读数每秒更新，历史曲线保留参考图形状，不自动滚动。
    sys.timerLoopStart(function()
        tick = tick + 1
        local page = plcui.status().page
        if page == "main" or page == "parameters" then
            xml:find(page, "clock"):set_text(os.date("%Y/%m/%d %H:%M:%S"))
        end
        if page == "main" then
            xml:find(page, "primary_supply"):set_text(string.format("一网供温:%.1f℃", 55.8 + math.sin(tick * 0.15) * 0.1))
        end
    end, 1000)
end)

sys.run()
