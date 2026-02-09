--[[
@module  dropdown_page
@summary 下拉框组件演示页面
@version 1.0.0
@date    2026.01.30
@author  江访
@usage
本文件是下拉框组件的演示页面，展示下拉框的各种用法。
]]

local dropdown_page = {}

-- 页面UI元素
local main_container = nil

-- 创建UI
function dropdown_page.create_ui()
    -- 创建主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 320,
        h = 480,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 320,
        h = 50,
        color = 0x795548,
    })

    airui.label({
        parent = title_bar,
        text = "下拉框组件演示",
        x = 10,
        y = 15,
        w = 200,
        h = 20,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 250,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function()
            go_back()
        end
    })

    -- 滚动容器
    local scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 370,
        color = 0xF5F5F5,
    })

    -- 示例1: 基本下拉框
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本下拉框",
        x = 10,
        y = 10,
        w = 300,
        h = 20,
    })

        -- 显示选中项
    local selected_label1 = airui.label({
        parent = scroll_container,
        text = "当前选中: 选项1",
        x = 230,
        y = 45,
        w = 80,
        h = 50,
    })

    local basic_dropdown = airui.dropdown({
        parent = scroll_container,
        x = 20,
        y = 40,
        w = 200,
        h = 40,
        options = {"选项1", "选项2", "选项3", "选项4", "选项5"},
        default_index = 0,
        on_change = function(self, index)
            -- 更新标签显示选择结果
            local texts = {"选项1", "选项2", "选项3", "选项4", "选项5"}
            selected_label1:set_text("当前选中: " .. texts[index + 1])
        end
    })



    -- 示例2: 下拉框组
    airui.label({
        parent = scroll_container,
        text = "示例2: 下拉框组",
        x = 10,
        y = 110,
        w = 300,
        h = 20,
    })

    local dropdown_container = airui.container({
        parent = scroll_container,
        x = 20,
        y = 140,
        w = 280,
        h = 150,
        color = 0xEFEBE9,
        radius = 8,
    })

    -- 城市选择
    airui.label({
        parent = dropdown_container,
        text = "城市:",
        x = 10,
        y = 20,
        w = 60,
        h = 20,
    })

    local city_dropdown = airui.dropdown({
        parent = dropdown_container,
        x = 80,
        y = 15,
        w = 180,
        h = 30,
        options = {"北京", "上海", "广州", "深圳", "杭州", "南京", "成都"},
        default_index = 0,
    })

    -- 区县选择
    airui.label({
        parent = dropdown_container,
        text = "区县:",
        x = 10,
        y = 60,
        w = 60,
        h = 20,
    })

    local district_dropdown = airui.dropdown({
        parent = dropdown_container,
        x = 80,
        y = 55,
        w = 180,
        h = 30,
        options = {"请先选择城市"},
        default_index = 0,
    })

    -- 联动选择按钮
    local select_btn = airui.button({
        parent = dropdown_container,
        x = 80,
        y = 100,
        w = 180,
        h = 35,
        text = "确认选择",
        on_click = function()
            local city_idx = city_dropdown:get_selected()
            local district_idx = district_dropdown:get_selected()
            local cities = {"北京", "上海", "广州", "深圳", "杭州", "南京", "成都"}
            log.info("dropdown", "选择了城市: " .. cities[city_idx + 1])
        end
    })

    -- 示例3: 获取选中值
    airui.label({
        parent = scroll_container,
        text = "示例3: 获取选中值",
        x = 10,
        y = 310,
        w = 300,
        h = 20,
    })

    local value_dropdown = airui.dropdown({
        parent = scroll_container,
        x = 20,
        y = 340,
        w = 180,
        h = 40,
        options = {"红色", "绿色", "蓝色", "黄色", "紫色"},
        default_index = 2,
    })

    local get_btn = airui.button({
        parent = scroll_container,
        x = 210,
        y = 340,
        w = 80,
        h = 40,
        text = "获取",
        on_click = function()
            local idx = value_dropdown:get_selected()
            local colors = {"红色", "绿色", "蓝色", "黄色", "紫色"}
            local msg = airui.msgbox({
                text = "当前选中: " .. colors[idx + 1],
                buttons = {"确定"},
                timeout = 2000
            })
            msg:show()
        end
    })

    -- 设置选中项
    local set_btn = airui.button({
        parent = scroll_container,
        x = 20,
        y = 390,
        w = 180,
        h = 40,
        text = "设置为黄色",
        on_click = function()
            value_dropdown:set_selected(3) -- 黄色是第4项，索引为3
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 下拉框支持选项选择和联动",
        x = 10,
        y = 440,
        w = 300,
        h = 20,
    })
end

-- 初始化页面
function dropdown_page.init(params)
    dropdown_page.create_ui()
end

-- 清理页面
function dropdown_page.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return dropdown_page