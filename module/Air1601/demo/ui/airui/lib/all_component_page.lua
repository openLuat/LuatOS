--[[
@module  all_component_page
@summary 所有组件演示页面
@version 1.0.0
@date    2026.01.30
@author  江访
@usage
本文件是所有组件的综合演示页面，展示AirUI所有组件的用法。
]]

local all_component_page = {}

-- 页面UI元素
local main_container = nil

-- 创建UI
function all_component_page.create_ui()
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
        color = 0x007AFF,
    })

    airui.label({
        parent = title_bar,
        text = "所有组件演示",
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

    -- 组件展示区域 - 使用两列布局
    local left_column_x = 20
    local right_column_x = 522  -- 1024/2 + 10
    local y_offset = 10
    local section_height = 100
    local column_width = 480

    -- 1. 标签组件（左列）
    airui.label({
        parent = scroll_container,
        text = "1. 标签组件 (Label)",
        x = left_column_x,
        y = y_offset,
        w = column_width,
        h = 25,
        size = 16,
    })

    local demo_label = airui.label({
        parent = scroll_container,
        text = "这是一个标签 - 点击我",
        x = left_column_x + 10,
        y = y_offset + 35,
        w = 200,
        h = 40,
        size = 16,
        on_click = function()
            demo_label:set_text("标签被点击")
        end
    })

    -- 2. 按钮组件（右列）
    airui.label({
        parent = scroll_container,
        text = "2. 按钮组件 (Button)",
        x = right_column_x,
        y = y_offset,
        w = column_width,
        h = 25,
        size = 16,
    })

    local demo_button = airui.button({
        parent = scroll_container,
        x = right_column_x + 10,
        y = y_offset + 35,
        w = 150,
        h = 45,
        text = "点击我",
        size = 16,
        on_click = function()
            log.info("all_component", "按钮被点击")
        end
    })

    y_offset = y_offset + section_height

    -- 3. 容器组件（左列）
    airui.label({
        parent = scroll_container,
        text = "3. 容器组件 (Container)",
        x = left_column_x,
        y = y_offset,
        w = column_width,
        h = 25,
        size = 16,
    })

    local demo_container = airui.container({
        parent = scroll_container,
        x = left_column_x + 10,
        y = y_offset + 35,
        w = 450,
        h = 80,
        color = 0xE3F2FD,
        radius = 10,
    })

    airui.label({
        parent = demo_container,
        text = "容器内的标签",
        x = 20,
        y = 25,
        w = 200,
        h = 30,
        size = 16,
    })

    -- 4. 进度条组件（右列）
    airui.label({
        parent = scroll_container,
        text = "4. 进度条组件 (Progress Bar)",
        x = right_column_x,
        y = y_offset,
        w = column_width,
        h = 25,
        size = 16,
    })

    local demo_bar = airui.bar({
        parent = scroll_container,
        x = right_column_x + 10,
        y = y_offset + 35,
        w = 300,
        h = 30,
        value = 65,
        radius = 15,
        indicator_color = 0x4CAF50,
    })

    y_offset = y_offset + section_height + 50

    -- 5. 开关组件（左列）
    airui.label({
        parent = scroll_container,
        text = "5. 开关组件 (Switch)",
        x = left_column_x,
        y = y_offset,
        w = column_width,
        h = 25,
        size = 16,
    })

    local demo_switch = airui.switch({
        parent = scroll_container,
        x = left_column_x + 10,
        y = y_offset + 35,
        w = 80,
        h = 40,
        checked = true,
        on_change = function(state)
            log.info("all_component", "开关状态: " .. tostring(state))
        end
    })

    -- 6. 下拉框组件（右列）
    airui.label({
        parent = scroll_container,
        text = "6. 下拉框组件 (Dropdown)",
        x = right_column_x,
        y = y_offset,
        w = column_width,
        h = 25,
        size = 16,
    })

    local demo_dropdown = airui.dropdown({
        parent = scroll_container,
        x = right_column_x + 10,
        y = y_offset + 35,
        w = 250,
        h = 45,
        options = { "选项1", "选项2", "选项3", "选项4" },
        default_index = 0,
        on_change = function(idx)
            log.info("all_component", "选择了选项: " .. (idx + 1))
        end
    })

    y_offset = y_offset + section_height

    -- 7. 表格组件（左列）
    airui.label({
        parent = scroll_container,
        text = "7. 表格组件 (Table)",
        x = left_column_x,
        y = y_offset,
        w = column_width,
        h = 25,
        size = 16,
    })

    local demo_table = airui.table({
        parent = scroll_container,
        x = left_column_x + 10,
        y = y_offset + 35,
        w = 450,
        h = 120,
        rows = 4,
        cols = 4,
        col_width = { 100, 100, 100, 100 },
        border_color = 0x607D8B,
    })

    demo_table:set_cell_text(0, 0, "姓名")
    demo_table:set_cell_text(0, 1, "年龄")
    demo_table:set_cell_text(0, 2, "城市")
    demo_table:set_cell_text(0, 3, "职业")
    demo_table:set_cell_text(1, 0, "张三")
    demo_table:set_cell_text(1, 1, "25")
    demo_table:set_cell_text(1, 2, "北京")
    demo_table:set_cell_text(1, 3, "工程师")

    -- 8. 输入框组件（右列）
    airui.label({
        parent = scroll_container,
        text = "8. 输入框组件 (Textarea)",
        x = right_column_x,
        y = y_offset,
        w = column_width,
        h = 25,
        size = 16,
    })

    local demo_textarea = airui.textarea({
        parent = scroll_container,
        x = right_column_x + 10,
        y = y_offset + 35,
        w = 300,
        h = 80,
        placeholder = "请输入文本...",
        max_len = 100,
        size = 16,
    })

    -- 创建键盘
    local keyboard1 = airui.keyboard({
        x = 200,
        y = 400,
        w = 600,
        h = 200,
        mode = "text",
        target = demo_textarea,
        auto_hide = true,
    })

    y_offset = y_offset + 200

    -- 9. 消息框组件（左列）
    airui.label({
        parent = scroll_container,
        text = "9. 消息框组件 (Msgbox)",
        x = left_column_x,
        y = y_offset,
        w = column_width,
        h = 25,
        size = 16,
    })

    local demo_msgbox_btn = airui.button({
        parent = scroll_container,
        x = left_column_x + 10,
        y = y_offset + 35,
        w = 180,
        h = 50,
        text = "显示消息框",
        size = 16,
        on_click = function()
            local msg = airui.msgbox({
                text = "这是一个消息框演示",
                buttons = { "确定", "取消" },
                on_action = function(self, label)
                    if label == "确定" then
                        self:hide()
                    else
                        self:hide()
                    end
                end
            })
            msg:show()
        end
    })

    -- 10. 图片组件（右列）
    airui.label({
        parent = scroll_container,
        text = "10. 图片组件 (Image)",
        x = right_column_x,
        y = y_offset,
        w = column_width,
        h = 25,
        size = 16,
    })

    local demo_image = airui.image({
        parent = scroll_container,
        x = right_column_x + 10,
        y = y_offset + 35,
        w = 120,
        h = 120,
        src = "/luadb/logo.jpg",
        on_click = function()
            log.info("all_component", "图片被点击")
        end
    })

    y_offset = y_offset + 180

    -- 11. 选项卡组件（左列）
    airui.label({
        parent = scroll_container,
        text = "11. 选项卡组件 (Tabview)",
        x = left_column_x,
        y = y_offset,
        w = column_width,
        h = 25,
        size = 16,
    })

    local demo_tabview = airui.tabview({
        parent = scroll_container,
        x = left_column_x + 10,
        y = y_offset + 35,
        w = 450,
        h = 200,
        tabs = { "标签页1", "标签页2", "标签页3" },
        active = 0,
    })

    -- 获取页面内容并添加标签
    local tab1_content = demo_tabview:get_content(0)
    if tab1_content then
        airui.label({
            parent = tab1_content,
            text = "标签页1的内容区域",
            x = 30,
            y = 30,
            w = 390,
            h = 40,
            size = 16,
        })
    end

    -- 12. 窗口组件（右列）
    airui.label({
        parent = scroll_container,
        text = "12. 窗口组件 (Window)",
        x = right_column_x,
        y = y_offset,
        w = column_width,
        h = 25,
        size = 16,
    })

    local demo_window_btn = airui.button({
        parent = scroll_container,
        x = right_column_x + 10,
        y = y_offset + 35,
        w = 180,
        h = 50,
        text = "打开窗口",
        size = 16,
        on_click = function()
            local win = airui.win({
                parent = airui.screen,
                title = "演示窗口",
                x = 300,
                y = 150,
                w = 400,
                h = 300,
                close_btn = true,
                on_close = function(self)
                    log.info("all_component", "窗口关闭")
                end
            })

            win:add_content(airui.label({
                text = "这是一个窗口内容演示",
                x = 30,
                y = 30,
                w = 340,
                h = 40,
                size = 16,
            }))

            win:add_content(airui.button({
                text = "关闭窗口",
                x = 130,
                y = 100,
                w = 140,
                h = 50,
                size = 16,
                on_click = function()
                    win:close()
                end
            }))
        end
    })



    -- 底部信息
    airui.label({
        parent = main_container,
        text = "AirUI组件综合演示 - 1024x600分辨率  共展示12个AirUI组件",
        x = 20,
        y = 570,
        w = 500,
        h = 25,
        size = 14,
    })
end

-- 初始化页面
function all_component_page.init(params)
    all_component_page.create_ui()
end

-- 清理页面
function all_component_page.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return all_component_page