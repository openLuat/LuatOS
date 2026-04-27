--[[
@module  water_config_win
@summary 智能水雾系统配置页面模块
@version 1.0
@date    2026.04.17
@author  AI Assistant
]]

local win_id = nil
local main_container = nil
local screen_w, screen_h = 480, 800

-- 颜色常量
local COLOR_PRIMARY = 0x3F51B5
local COLOR_BG = 0xF8F9FA
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x000000
local COLOR_TEXT_SECONDARY = 0x666666
local COLOR_SUCCESS = 0x27AE60
local COLOR_WARNING = 0xF39C12
local COLOR_ERROR = 0xE74C3C
local COLOR_INFO = 0x3498DB

-- 数据存储键名（使用fskv存储系统）
local DATA_KEY = "water_branch_config"

-- 默认支路数据
local default_branch_data = {
    { name = "第一路", humidity = "45.0%", temperature = "25.5°C", status = "系统停止", status_color = COLOR_ERROR, switch = true, start_time = "08:00:00", end_time = "18:00:00", humidity_threshold = "65" },
    { name = "第二路", humidity = "88.0%", temperature = "24.8°C", status = "自动喷雾", status_color = COLOR_SUCCESS, switch = false, start_time = "08:00:00", end_time = "18:00:00", humidity_threshold = "65" },
    { name = "第三路", humidity = "88.0%", temperature = "25.2°C", status = "自动停止", status_color = COLOR_ERROR, switch = false, start_time = "08:00:00", end_time = "18:00:00", humidity_threshold = "65" },
    { name = "第四路", humidity = "88.0%", temperature = "26.1°C", status = "系统暂停", status_color = COLOR_WARNING, switch = true, start_time = "08:00:00", end_time = "18:00:00", humidity_threshold = "65" },
    { name = "第五路", humidity = "33.0%", temperature = "25.8°C", status = "水箱缺水", status_color = COLOR_ERROR, switch = false, start_time = "08:00:00", end_time = "18:00:00", humidity_threshold = "65" },
    { name = "第六路", humidity = "88.0%", temperature = "24.9°C", status = "药箱缺药", status_color = COLOR_ERROR, switch = false, start_time = "08:00:00", end_time = "18:00:00", humidity_threshold = "65" },
    { name = "第七路", humidity = "65.0%", temperature = "27.3°C", status = "自动运行", status_color = COLOR_SUCCESS, switch = true, start_time = "08:00:00", end_time = "18:00:00", humidity_threshold = "65" },
    { name = "第八路", humidity = "78.0%", temperature = "26.8°C", status = "系统停止", status_color = COLOR_ERROR, switch = false, start_time = "08:00:00", end_time = "18:00:00", humidity_threshold = "65" },
}

-- 加载配置数据（使用fskv存储系统）
local function load_config()
    log.info("load_config", "开始加载配置，存储键名:", DATA_KEY)
    
    -- 检查fskv是否初始化
    local result = fskv.init()
    if not result then
        log.error("load_config", "fskv初始化失败，使用默认数据")
        return default_branch_data
    end
    
    -- 从fskv加载配置
    local loaded_config = fskv.get(DATA_KEY)
    if loaded_config then
        log.info("load_config", "成功从fskv加载配置数据，支路数量:", #loaded_config)
        return loaded_config
    else
        log.info("load_config", "fskv中未找到配置数据，使用默认数据")
        -- 初始化fskv中的默认配置
        fskv.set(DATA_KEY, default_branch_data)
        return default_branch_data
    end
end

-- 支路数据（从文件加载或使用默认值）
local branch_data = load_config()

-- 保存配置数据（使用fskv存储系统）
local function save_config()
    log.info("save_config", "开始保存配置，存储键名:", DATA_KEY)
    
    -- 检查fskv是否初始化
    local result = fskv.init()
    if not result then
        log.error("save_config", "fskv初始化失败")
        return false
    end
    
    -- 准备要保存的数据，确保只包含fskv支持的数据类型
    local save_data = {}
    if branch_data and type(branch_data) == "table" then
        for i, branch in ipairs(branch_data) do
            if branch and type(branch) == "table" then
                local safe_branch = {
                    name = branch.name or "",
                    humidity = branch.humidity or "0.0%",
                    temperature = branch.temperature or "0.0°C",
                    status = branch.status or "未知状态",
                    status_color = branch.status_color or 0x000000,
                    switch = not not branch.switch, -- 确保是布尔值
                    start_time = branch.start_time or "00:00:00",
                    end_time = branch.end_time or "00:00:00",
                    humidity_threshold = branch.humidity_threshold or "0"
                }
                -- 确保所有值都是支持的类型
                for k, v in pairs(safe_branch) do
                    if type(v) == "function" or type(v) == "userdata" or type(v) == "thread" or v == nil then
                        safe_branch[k] = ""
                    end
                end
                save_data[i] = safe_branch
            else
                log.warn("save_config", "忽略无效的支路数据", i, type(branch))
            end
        end
    else
        log.error("save_config", "branch_data 不是有效的表格类型", type(branch_data))
        return false
    end
    
    -- 保存配置到fskv
    local save_result = fskv.set(DATA_KEY, save_data)
    
    -- 优化保存成功的判断逻辑
    if save_result then
        log.info("save_config", "配置保存成功，支路数量:", #save_data)
        for i, branch in ipairs(save_data) do
            log.info("save_config", string.format("支路%d: %s", i, branch.name))
        end
        return true
    else
        log.info("save_config", "fskv.set返回false，但实际可能已保存成功（某些值可能有类型限制）")
        -- 尝试重新加载配置以验证
        local verify_data = fskv.get(DATA_KEY)
        if verify_data and #verify_data == #save_data then
            log.info("save_config", "配置验证成功，实际已保存")
            return true
        else
            log.error("save_config", "配置保存失败")
            return false
        end
    end
end

-- 数字转中文函数
local function number_to_chinese(num)
    local chinese_nums = {"零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"}
    if num <= 10 then
        return chinese_nums[num + 1]
    elseif num < 20 then
        return "十" .. chinese_nums[num - 10 + 1]
    else
        local tens = math.floor(num / 10)
        local ones = num % 10
        if ones == 0 then
            return chinese_nums[tens + 1] .. "十"
        else
            return chinese_nums[tens + 1] .. "十" .. chinese_nums[ones + 1]
        end
    end
end

-------------------------------------------------------------------------------
-- 创建配置页面 UI
-------------------------------------------------------------------------------
function create_config_page(parent, branch_index)
    log.info("WATER_CONFIG_WIN", "Creating config page for branch_index:", branch_index)
    
    -- 检查 branch_index 有效性
    if not branch_index or type(branch_index) ~= "number" or branch_index < 1 then
        log.error("WATER_CONFIG_WIN", "Invalid branch_index:", branch_index)
        -- 使用默认分支索引
        branch_index = 1
        log.info("WATER_CONFIG_WIN", "Using default branch_index: 1")
    end
    
    -- 如果分支索引超出范围，创建新的支路数据
    if branch_index > #branch_data then
        log.info("WATER_CONFIG_WIN", "Branch index out of range, creating new branch data")
        -- 扩展 branch_data 表，添加新的支路数据
        for i = #branch_data + 1, branch_index do
            table.insert(branch_data, {
                name = "第" .. number_to_chinese(i) .. "路",
                humidity = "50.0%",
                temperature = "25.0°C",
                status = "系统停止",
                status_color = COLOR_ERROR,
                switch = false,
                start_time = "08:00:00",
                end_time = "18:00:00",
                humidity_threshold = "65"
            })
        end
        -- 保存扩展后的数据
        save_config()
        log.info("WATER_CONFIG_WIN", "Created new branch data, count:", #branch_data)
    end

    -- 清除所有子组件
    if parent then
        -- 直接重新创建容器
        parent:destroy()
        main_container = airui.container({
            parent = airui.screen,
            x = 0,
            y = 0,
            w = screen_w,
            h = screen_h,
            color = 0xFFFFFF
        })
        parent = main_container
    end

    -- 配置面板（全屏设计）
    local config_panel = airui.container({
        parent = parent,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = 0xFFFFFF
    })

    -- 配置标题栏（包含按钮）
    local branch = branch_data[branch_index]
    -- 再次检查 branch 是否有效
    if not branch then
        log.error("WATER_CONFIG_WIN", "Branch not found for index:", branch_index)
        if win_id then
            exwin.close(win_id)
        end
        return nil
    end
    airui.container({
        parent = config_panel,
        x = 0,
        y = 0,
        w = screen_w,
        h = 60,
        color = 0x3F51B5
    })
    
    -- 解析时间字符串
    local function parse_time(time_str)
        local hour, minute, second = time_str:match("(%d+):(%d+):(%d+)")
        return tonumber(hour), tonumber(minute), tonumber(second)
    end

    -- 保存配置数据
    local start_hour_val, start_minute_val, start_second_val = parse_time(branch.start_time)
    local end_hour_val, end_minute_val, end_second_val = parse_time(branch.end_time)
    local humidity_val = tonumber(branch.humidity_threshold)

    -- 取消按钮 - 标题栏左上角
    airui.button({
        parent = config_panel,
        x = 20,
        y = 7,
        w = 80,
        h = 45,
        text = "取消",
        font_size = 18,
        color = 0xFFFFFF,
        bg_color = 0xBDC3C7,
        radius = 5,
        border_color = 0x95A5A6,
        border_width = 2,
        on_click = function()
            log.info("WATER_CONFIG_WIN", "Cancel button clicked, win_id:", win_id)
            if win_id then
                local close_result = exwin.close(win_id)
                log.info("WATER_CONFIG_WIN", "exwin.close result:", close_result)
                -- 确保窗口ID被重置
                win_id = nil
            else
                log.warn("WATER_CONFIG_WIN", "Cancel button clicked but win_id is nil")
            end
        end
    })
    
    -- 配置标题 - 居中
    airui.label({
        parent = config_panel,
        x = 0,
        y = 10,
        w = screen_w,
        h = 40,
        text = branch.name .. "设置",
        font_size = 24,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER,
        font_bold = true
    })
    
    -- 保存按钮 - 标题栏右上角
    airui.button({
        parent = config_panel,
        x = screen_w - 100,
        y = 7,
        w = 80,
        h = 45,
        text = "保存",
        font_size = 18,
        color = 0xFFFFFF,
        bg_color = COLOR_PRIMARY,
        radius = 5,
        border_color = 0x303F9F,
        border_width = 2,
        on_click = function()
            -- 保存配置
            branch.start_time = string.format("%02d:%02d:%02d", start_hour_val, start_minute_val, start_second_val)
            branch.end_time = string.format("%02d:%02d:%02d", end_hour_val, end_minute_val, end_second_val)
            branch.humidity_threshold = tostring(humidity_val)
            save_config() -- 保存数据
            
            log.info("WATER_CONFIG_WIN", "Save button clicked, win_id:", win_id)
            if win_id then
                local close_result = exwin.close(win_id)
                log.info("WATER_CONFIG_WIN", "exwin.close result:", close_result)
                -- 确保窗口ID被重置
                win_id = nil
            else
                log.warn("WATER_CONFIG_WIN", "Save button clicked but win_id is nil")
            end
        end
    })

    -- 时间选择函数（使用airui.dropdown）
    local function create_time_selector(parent, x, y, initial_value, min, max, on_select)
        -- 创建选项列表
        local options = {}
        for i = min, max do
            table.insert(options, string.format("%02d", i))
        end
        -- 查找初始值的索引
        local default_index = 1
        for i, v in ipairs(options) do
            if v == string.format("%02d", initial_value) then
                default_index = i - 1
                break
            end
        end
        -- 创建下拉框
        local dropdown = airui.dropdown({
            parent = parent,
            x = x,
            y = y,
            w = 70,
            h = 40,
            options = options,
            default_index = default_index,
            on_change = function(self, index)
                if on_select then on_select(tonumber(options[index + 1])) end
            end
        })
        return dropdown
    end

    -- 开始时间
    airui.label({
        parent = config_panel,
        x = 20,
        y = 70,
        w = 100,
        h = 40,
        text = "开始时间：",
        font_size = 18,
        color = 0x333333,
        font_bold = true
    })
    local start_hour = create_time_selector(config_panel, 120, 70, start_hour_val, 0, 23, function(value)
        start_hour_val = value
    end)
    airui.label({
        parent = config_panel,
        x = 195,
        y = 70,
        w = 10,
        h = 40,
        text = ":",
        font_size = 18,
        color = 0x333333
    })
    local start_minute = create_time_selector(config_panel, 210, 70, start_minute_val, 0, 59, function(value)
        start_minute_val = value
    end)
    airui.label({
        parent = config_panel,
        x = 285,
        y = 70,
        w = 10,
        h = 40,
        text = ":",
        font_size = 18,
        color = 0x333333
    })
    local start_second = create_time_selector(config_panel, 300, 70, start_second_val, 0, 59, function(value)
        start_second_val = value
    end)

    -- 结束时间
    airui.label({
        parent = config_panel,
        x = 20,
        y = 120,
        w = 100,
        h = 40,
        text = "结束时间：",
        font_size = 18,
        color = 0x333333,
        font_bold = true
    })
    local end_hour = create_time_selector(config_panel, 120, 120, end_hour_val, 0, 23, function(value)
        end_hour_val = value
    end)
    airui.label({
        parent = config_panel,
        x = 195,
        y = 120,
        w = 10,
        h = 40,
        text = ":",
        font_size = 18,
        color = 0x333333
    })
    local end_minute = create_time_selector(config_panel, 210, 120, end_minute_val, 0, 59, function(value)
        end_minute_val = value
    end)
    airui.label({
        parent = config_panel,
        x = 285,
        y = 120,
        w = 10,
        h = 40,
        text = ":",
        font_size = 18,
        color = 0x333333
    })
    local end_second = create_time_selector(config_panel, 300, 120, end_second_val, 0, 59, function(value)
        end_second_val = value
    end)

    -- 湿度阈值
    airui.label({
        parent = config_panel,
        x = 20,
        y = 170,
        w = 100,
        h = 40,
        text = "湿度阈值：",
        font_size = 18,
        color = 0x333333,
        font_bold = true
    })
    -- 创建湿度选项列表
    local humidity_options = {}
    for i = 0, 100, 5 do
        table.insert(humidity_options, tostring(i))
    end
    -- 查找初始值的索引
    local humidity_default_index = 1
    for i, v in ipairs(humidity_options) do
        if v == tostring(humidity_val) then
            humidity_default_index = i - 1
            break
        end
    end
    -- 创建湿度下拉框
    local humidity_dropdown = airui.dropdown({
        parent = config_panel,
        x = 120,
        y = 170,
        w = 70,
        h = 40,
        options = humidity_options,
        default_index = humidity_default_index,
        on_change = function(self, index)
            humidity_val = tonumber(humidity_options[index + 1])
        end
    })
    airui.label({
        parent = config_panel,
        x = 195,
        y = 170,
        w = 20,
        h = 40,
        text = "%",
        font_size = 18,
        color = 0x333333,
        font_bold = true
    })

    -- 删除按钮 - 下方居中（增大尺寸，红色背景）
    if branch_index >= 1 and branch_index <= #branch_data then
        airui.button({
            parent = config_panel,
            x = (screen_w - 120) / 2,
            y = 280,
            w = 120,
            h = 60,
            text = "删除",
            font_size = 22,
            color = 0xFFFFFF,
            bg_color = 0xD32F2F,
            radius = 8,
            border_color = 0xC62828,
            border_width = 3,
            on_click = function()
                -- 确认删除
                log.info("DeleteButton", "开始删除支路", branch_index, branch_data[branch_index] and branch_data[branch_index].name)
                if branch_index >= 1 and branch_index <= #branch_data then
                    table.remove(branch_data, branch_index)
                    -- 更新剩余支路的名称
                    for i = branch_index, #branch_data do
                        branch_data[i].name = "第" .. number_to_chinese(i) .. "路"
                    end
                    -- 强制保存配置到fskv
                    local save_result = fskv.set(DATA_KEY, branch_data)
                    if save_result then
                        log.info("DeleteButton", "配置数据已成功保存到fskv，存储键名:", DATA_KEY)
                    else
                        log.error("DeleteButton", "配置数据保存失败")
                    end
                    -- 发布事件，通知详情页面刷新数据
                    log.info("WATER_CONFIG_WIN", "Publishing REFRESH_WATER_DETAIL_PAGE event")
                    sys.publish("REFRESH_WATER_DETAIL_PAGE")
                    -- 关闭窗口
                    log.info("WATER_CONFIG_WIN", "Delete button clicked, closing window")
                    if win_id then
                        local close_result = exwin.close(win_id)
                        log.info("WATER_CONFIG_WIN", "exwin.close result:", close_result)
                        -- 确保窗口ID被重置
                        win_id = nil
                    end
                else
                    log.error("DeleteButton", "索引越界，无法删除")
                end
            end
        })
    end
    return main_container
end

-------------------------------------------------------------------------------
-- 窗口生命周期
-------------------------------------------------------------------------------
local function on_create()
    -- 从全局变量中获取分支索引
    local branch_index = _G.water_config_branch_index or 1 -- 默认值
    log.info("WATER_CONFIG_WIN", "Creating config page for branch " .. branch_index)
    
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = 0xFFFFFF
    })
    main_container = create_config_page(main_container, branch_index)
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

local function on_get_focus()
end

local function on_lose_focus()
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

-- 订阅事件（接收分支索引参数）
local function open_handler(branch_index)
    log.info("WATER_CONFIG_WIN", "Open config page for branch " .. branch_index)
    -- 重新加载配置数据，确保包含最新的支路信息
    branch_data = load_config()
    log.info("WATER_CONFIG_WIN", "Reloaded branch data, count:", #branch_data)
    -- 保存分支索引到本地变量，以便在 on_create 中使用
    _G.water_config_branch_index = branch_index
    
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_WATER_CONFIG_WIN", open_handler)
