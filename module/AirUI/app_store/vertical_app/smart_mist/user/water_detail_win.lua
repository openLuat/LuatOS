--[[
@module  water_detail_win
@summary 智能水雾系统详细状态页面模块
@version 1.0
@date    2026.04.17
@author  AI Assistant
]]

local win_id = nil
local main_container = nil
local screen_w, screen_h = 480, 800

-- 页面状态
local current_page = "detail"

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
        for i, branch in ipairs(loaded_config) do
            log.info("load_config", string.format("支路%d: %s", i, branch.name))
        end
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

-------------------------------------------------------------------------------
-- 创建详细状态页面 UI
-------------------------------------------------------------------------------
function create_detail_page(parent)
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

    -- 顶部栏
    local header = airui.container({
        parent = parent,
        x = 0,
        y = 0,
        w = screen_w,
        h = 60,
        color = COLOR_PRIMARY
    })
    airui.button({
        parent = header,
        x = 10,
        y = 10,
        w = 60,
        h = 40,
        text = "返回",
        font_size = 18,
        color = 0xFFFFFF,
        bg_color = 0x808080,
        radius = 8,
        on_click = function()
            log.info("WATER_DETAIL_WIN", "Return button clicked, win_id:", win_id)
            if win_id then 
                local close_result = exwin.close(win_id)
                log.info("WATER_DETAIL_WIN", "exwin.close result:", close_result)
                -- 确保窗口ID被重置
                win_id = nil
            else
                log.warn("WATER_DETAIL_WIN", "Return button clicked but win_id is nil")
            end 
        end
    })
    airui.label({
        parent = header,
        x = (screen_w - 150) / 2,
        y = 15,
        w = 150,
        h = 30,
        text = "详细状态",
        font_size = 24,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.button({
        parent = header,
        x = screen_w - 80,
        y = 10,
        w = 60,
        h = 40,
        text = "新增",
        font_size = 18,
        color = 0xFFFFFF,
        bg_color = 0x27AE60,
        radius = 8,
        on_click = function()
            -- 新增支路
            local new_index = #branch_data + 1
            table.insert(branch_data, {
                name = "第" .. number_to_chinese(new_index) .. "路",
                humidity = "50.0%",
                temperature = "25.0°C",
                status = "系统停止",
                status_color = COLOR_ERROR,
                switch = false,
                start_time = "08:00:00",
                end_time = "18:00:00",
                humidity_threshold = "65"
            })
            save_config()  -- 保存数据
            current_page = "detail"
            main_container = create_detail_page(main_container)
        end
    })


    -- 表格区域
    local table_container = airui.container({
        parent = parent,
        x = 10,
        y = 70,
        w = screen_w - 20,
        h = screen_h - 80,
        color = COLOR_CARD,
        radius = 8
    })

    -- 表头
    airui.container({
        parent = table_container,
        x = 0,
        y = 0,
        w = screen_w - 20,
        h = 40,
        color = 0x34495E,
        radius = 4
    })
    airui.label({
        parent = table_container,
        x = 15,
        y = 10,
        w = 70,
        h = 20,
        text = "模式",
        font_size = 14,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = table_container,
        x = 90,
        y = 10,
        w = 60,
        h = 20,
        text = "湿度",
        font_size = 14,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = table_container,
        x = 160,
        y = 10,
        w = 60,
        h = 20,
        text = "温度",
        font_size = 14,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = table_container,
        x = 230,
        y = 10,
        w = 100,
        h = 20,
        text = "状态",
        font_size = 14,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = table_container,
        x = 340,
        y = 10,
        w = 40,
        h = 20,
        text = "开关",
        font_size = 14,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = table_container,
        x = 390,
        y = 10,
        w = 40,
        h = 20,
        text = "设置",
        font_size = 14,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 支路列表
    local branch_y = 50
    for i, branch in ipairs(branch_data) do
        local row_container = airui.container({
            parent = table_container,
            x = 0,
            y = branch_y,
            w = screen_w - 20,
            h = 75,
            color = (i % 2 == 0) and 0xE9ECEF or 0xF8F9FA,
            radius = 4
        })

        -- 支路名称
        airui.label({
            parent = row_container,
            x = 15,
            y = 25,
            w = 70,
            h = 30,
            text = branch.name,
            font_size = 16,
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_CENTER
        })

        -- 湿度值
        airui.label({
            parent = row_container,
            x = 90,
            y = 25,
            w = 60,
            h = 30,
            text = branch.humidity,
            font_size = 16,
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_CENTER
        })

        -- 温度值
        airui.label({
            parent = row_container,
            x = 160,
            y = 25,
            w = 60,
            h = 30,
            text = branch.temperature,
            font_size = 16,
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_CENTER
        })

        -- 状态标签
        airui.container({
            parent = row_container,
            x = 230,
            y = 25,
            w = 100,
            h = 30,
            color = branch.status_color,
            radius = 4
        })
        airui.label({
            parent = row_container,
            x = 235,
            y = 25,
            w = 90,
            h = 30,
            text = branch.status,
            font_size = 13,
            color = 0xFFFFFF,
            align = airui.TEXT_ALIGN_CENTER
        })

        -- 开关按钮
        local switch = airui.switch({
            parent = row_container,
            x = 340,
            y = 25,
            w = 40,
            h = 30,
            checked = branch.switch,
            on_change = function(self, checked)
                branch.switch = checked
                save_config()  -- 保存配置到文件系统
            end
        })

        -- 设置按钮（文字按钮）
        airui.button({
            parent = row_container,
            x = 390,
            y = 25,
            w = 40,
            h = 30,
            text = "设置",
            font_size = 14,
            color = 0xFFFFFF,
            bg_color = COLOR_INFO,
            radius = 4,
            on_click = function()
                -- 打开设置页面
                log.info("WATER_DETAIL_WIN", "Open config page for branch " .. i)
                -- 发布事件，打开新的配置窗口
                sys.publish("OPEN_WATER_CONFIG_WIN", i)
            end
        })

        branch_y = branch_y + 80
    end
    return main_container
end

-------------------------------------------------------------------------------
-- 创建配置页面 UI
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- 窗口生命周期
-------------------------------------------------------------------------------
local function on_create()
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = 0xFFFFFF
    })
    main_container = create_detail_page(main_container)
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

sys.subscribe("OPEN_WATER_DETAIL_WIN", open_handler)
-- 监听页面刷新事件
sys.subscribe("REFRESH_WATER_DETAIL_PAGE", function()
    log.info("WATER_DETAIL_WIN", "Received REFRESH_WATER_DETAIL_PAGE event")
    -- 重新加载配置数据
    branch_data = load_config()
    log.info("WATER_DETAIL_WIN", "Reloaded branch data, count:", #branch_data)
    -- 刷新页面显示
    main_container = create_detail_page(main_container)
end)
