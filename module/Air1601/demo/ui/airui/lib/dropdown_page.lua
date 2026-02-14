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
        w = 1024,
        h = 600,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 1024,
        h = 60,
        color = 0x795548,
    })

    airui.label({
        parent = title_bar,
        text = "下拉框组件演示",
        x = 20,
        y = 15,
        w = 300,
        h = 30,
        size = 20,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 900,
        y = 15,
        w = 100,
        h = 35,
        text = "返回",
        size = 16,
        on_click = function()
            go_back()
        end
    })

    -- 滚动容器
    local scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 70,
        w = 1024,
        h = 480,
        color = 0xF5F5F5,
    })

    -- 使用两列布局
    local left_column_x = 20
    local right_column_x = 522
    local y_offset = 10
    local section_height = 100

    -- 示例1: 基本下拉框（左列）
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本下拉框",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    -- 显示选中项
    local selected_label1 = airui.label({
        parent = scroll_container,
        text = "当前选中: 选项1",
        x = left_column_x + 350,
        y = y_offset + 50,
        w = 150,
        h = 30,
        size = 14,
    })

    local basic_dropdown = airui.dropdown({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 45,
        w = 300,
        h = 45,
        options = {"选项1", "选项2", "选项3", "选项4", "选项5", "选项6"},
        default_index = 0,
        on_change = function(self, index)
            -- 更新标签显示选择结果
            local texts = {"选项1", "选项2", "选项3", "选项4", "选项5", "选项6"}
            selected_label1:set_text("当前选中: " .. texts[index + 1])
        end
    })

    -- 示例2: 不同大小的下拉框（右列）
    airui.label({
        parent = scroll_container,
        text = "示例2: 不同大小的下拉框",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local small_dropdown = airui.dropdown({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 45,
        w = 120,
        h = 35,
        options = {"小号选项1", "小号选项2"},
        default_index = 0,
    })

    local large_dropdown = airui.dropdown({
        parent = scroll_container,
        x = right_column_x + 170,
        y = y_offset + 45,
        w = 200,
        h = 50,
        options = {"大号下拉框选项1", "大号下拉框选项2", "大号下拉框选项3"},
        default_index = 0,
    })

    y_offset = y_offset + section_height + 20

    -- 示例3: 联动下拉框（左列）
    airui.label({
        parent = scroll_container,
        text = "示例3: 联动下拉框",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local dropdown_container = airui.container({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 460,
        h = 200,
        color = 0xEFEBE9,
        radius = 12,
    })

    -- 省份选择
    airui.label({
        parent = dropdown_container,
        text = "省份:",
        x = 30,
        y = 30,
        w = 80,
        h = 30,
        size = 16,
    })

    local province_dropdown = airui.dropdown({
        parent = dropdown_container,
        x = 120,
        y = 25,
        w = 300,
        h = 40,
        options = {"北京市", "上海市", "广东省", "江苏省", "浙江省", "四川省"},
        default_index = 0,
    })

    -- 城市选择
    airui.label({
        parent = dropdown_container,
        text = "城市:",
        x = 30,
        y = 85,
        w = 80,
        h = 30,
        size = 16,
    })

    local city_dropdown = airui.dropdown({
        parent = dropdown_container,
        x = 120,
        y = 80,
        w = 300,
        h = 40,
        options = {"请先选择省份"},
        default_index = 0,
    })

    -- 联动选择按钮
    local select_btn = airui.button({
        parent = dropdown_container,
        x = 120,
        y = 140,
        w = 300,
        h = 45,
        text = "确认选择",
        size = 16,
        on_click = function()
            local province_idx = province_dropdown:get_selected()
            local city_idx = city_dropdown:get_selected()
            local provinces = {"北京市", "上海市", "广东省", "江苏省", "浙江省", "四川省"}
            log.info("dropdown", "选择了省份: " .. provinces[province_idx + 1])
        end
    })

    -- 示例4: 获取和设置选中值（右列）
    airui.label({
        parent = scroll_container,
        text = "示例4: 获取和设置选中值",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local value_container = airui.container({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 460,
        h = 200,
        color = 0xE8EAF6,
        radius = 12,
    })

    local value_dropdown = airui.dropdown({
        parent = value_container,
        x = 30,
        y = 30,
        w = 300,
        h = 45,
        options = {"红色", "绿色", "蓝色", "黄色", "紫色", "橙色", "青色"},
        default_index = 2,
    })

    -- 获取选中值按钮
    local get_btn = airui.button({
        parent = value_container,
        x = 30,
        y = 90,
        w = 140,
        h = 45,
        text = "获取选中值",
        size = 16,
        on_click = function()
            local idx = value_dropdown:get_selected()
            local colors = {"红色", "绿色", "蓝色", "黄色", "紫色", "橙色", "青色"}
            local msg = airui.msgbox({
                text = "当前选中: " .. colors[idx + 1],
                buttons = {"确定"},
                timeout = 2000
            })
            msg:show()
        end
    })

    -- 设置选中项按钮
    local set_btn = airui.button({
        parent = value_container,
        x = 190,
        y = 90,
        w = 140,
        h = 45,
        text = "设为黄色",
        size = 16,
        on_click = function()
            value_dropdown:set_selected(3) -- 黄色是第4项，索引为3
        end
    })

    -- 重置按钮
    local reset_btn = airui.button({
        parent = value_container,
        x = 30,
        y = 145,
        w = 300,
        h = 40,
        text = "重置为默认（蓝色）",
        size = 16,
        on_click = function()
            value_dropdown:set_selected(2)
        end
    })

    y_offset = y_offset + 250

    -- 示例5: 下拉框组（左列）
    airui.label({
        parent = scroll_container,
        text = "示例5: 下拉框组",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local group_container = airui.container({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 460,
        h = 180,
        color = 0xF5F5F5,
        radius = 12,
    })

    -- 日期选择
    airui.label({
        parent = group_container,
        text = "年:",
        x = 20,
        y = 20,
        w = 50,
        h = 30,
        size = 14,
    })

    local year_dropdown = airui.dropdown({
        parent = group_container,
        x = 80,
        y = 15,
        w = 120,
        h = 35,
        options = {"2024", "2025", "2026", "2027", "2028"},
        default_index = 1,
    })

    airui.label({
        parent = group_container,
        text = "月:",
        x = 220,
        y = 20,
        w = 50,
        h = 30,
        size = 14,
    })

    local month_dropdown = airui.dropdown({
        parent = group_container,
        x = 280,
        y = 15,
        w = 120,
        h = 35,
        options = {"1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"},
        default_index = 0,
    })

    -- 时间选择
    airui.label({
        parent = group_container,
        text = "时:",
        x = 20,
        y = 70,
        w = 50,
        h = 30,
        size = 14,
    })

    local hour_dropdown = airui.dropdown({
        parent = group_container,
        x = 80,
        y = 65,
        w = 120,
        h = 35,
        options = {"00", "01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23"},
        default_index = 8,
    })

    airui.label({
        parent = group_container,
        text = "分:",
        x = 220,
        y = 70,
        w = 50,
        h = 30,
        size = 14,
    })

    local minute_dropdown = airui.dropdown({
        parent = group_container,
        x = 280,
        y = 65,
        w = 120,
        h = 35,
        options = {"00", "05", "10", "15", "20", "25", "30", "35", "40", "45", "50", "55"},
        default_index = 0,
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 下拉框支持选项选择、联动和动态控制",
        x = 20,
        y = 560,
        w = 500,
        h = 25,
        size = 14,
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