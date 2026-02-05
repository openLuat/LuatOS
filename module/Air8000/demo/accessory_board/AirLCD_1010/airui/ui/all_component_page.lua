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
        color = 0x007AFF,
    })

    airui.label({
        parent = title_bar,
        text = "所有组件演示",
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

    -- 组件展示区域
    local y_offset = 10

    -- 1. 标签组件
    airui.label({
        parent = scroll_container,
        text = "1. 标签组件 (Label)",
        x = 10,
        y = y_offset,
        w = 300,
        h = 20,
    })

    local demo_label = airui.label({
        parent = scroll_container,
        text = "这是一个标签",
        x = 20,
        y = y_offset + 30,
        w = 120,
        h = 30,
        on_click = function()
            demo_label:set_text("标签被点击")
        end
    })

    y_offset = y_offset + 70

    -- 2. 按钮组件
    airui.label({
        parent = scroll_container,
        text = "2. 按钮组件 (Button)",
        x = 10,
        y = y_offset,
        w = 300,
        h = 20,
    })

    local demo_button = airui.button({
        parent = scroll_container,
        x = 20,
        y = y_offset + 30,
        w = 100,
        h = 40,
        text = "点击我",
        on_click = function()
            log.info("all_component", "按钮被点击")
        end
    })

    y_offset = y_offset + 80

    -- 3. 容器组件
    airui.label({
        parent = scroll_container,
        text = "3. 容器组件 (Container)",
        x = 10,
        y = y_offset,
        w = 300,
        h = 20,
    })

    local demo_container = airui.container({
        parent = scroll_container,
        x = 20,
        y = y_offset + 30,
        w = 280,
        h = 60,
        color = 0xE3F2FD,
        radius = 8,
    })

    airui.label({
        parent = demo_container,
        text = "容器内的标签",
        x = 10,
        y = 20,
        w = 120,
        h = 20,
    })

    y_offset = y_offset + 100

    -- 4. 进度条组件
    airui.label({
        parent = scroll_container,
        text = "4. 进度条组件 (Progress Bar)",
        x = 10,
        y = y_offset,
        w = 300,
        h = 20,
    })

    local demo_bar = airui.bar({
        parent = scroll_container,
        x = 20,
        y = y_offset + 30,
        w = 200,
        h = 20,
        value = 65,
        indicator_color = 0x4CAF50,
    })

    y_offset = y_offset + 60

    -- 5. 开关组件
    airui.label({
        parent = scroll_container,
        text = "5. 开关组件 (Switch)",
        x = 10,
        y = y_offset,
        w = 300,
        h = 20,
    })

    local demo_switch = airui.switch({
        parent = scroll_container,
        x = 20,
        y = y_offset + 30,
        w = 60,
        h = 30,
        checked = true,
        on_change = function(state)
            log.info("all_component", "开关状态: " .. tostring(state))
        end
    })

    y_offset = y_offset + 70

    -- 6. 下拉框组件
    airui.label({
        parent = scroll_container,
        text = "6. 下拉框组件 (Dropdown)",
        x = 10,
        y = y_offset,
        w = 300,
        h = 20,
    })

    local demo_dropdown = airui.dropdown({
        parent = scroll_container,
        x = 20,
        y = y_offset + 30,
        w = 150,
        h = 35,
        options = { "选项1", "选项2", "选项3" },
        default_index = 0,
        on_change = function(idx)
            log.info("all_component", "选择了选项: " .. (idx + 1))
        end
    })

    y_offset = y_offset + 75

    -- 7. 表格组件
    airui.label({
        parent = scroll_container,
        text = "7. 表格组件 (Table)",
        x = 10,
        y = y_offset,
        w = 300,
        h = 20,
    })

    local demo_table = airui.table({
        parent = scroll_container,
        x = 20,
        y = y_offset + 30,
        w = 280,
        h = 80,
        rows = 3,
        cols = 3,
        col_width = { 80, 80, 80 },
        border_color = 0x607D8B,
    })

    demo_table:set_cell_text(0, 0, "姓名")
    demo_table:set_cell_text(0, 1, "年龄")
    demo_table:set_cell_text(0, 2, "城市")
    demo_table:set_cell_text(1, 0, "张三")
    demo_table:set_cell_text(1, 1, "25")
    demo_table:set_cell_text(1, 2, "北京")

    y_offset = y_offset + 120

    -- 8. 输入框组件
    airui.label({
        parent = scroll_container,
        text = "8. 输入框组件 (Textarea)",
        x = 10,
        y = y_offset,
        w = 300,
        h = 20,
    })

    local demo_textarea = airui.textarea({
        parent = scroll_container,
        x = 20,
        y = y_offset + 30,
        w = 150,
        h = 60,
        placeholder = "请输入文本...",
        max_len = 50,
    })

    -- 创建键盘
        local keyboard1 = airui.keyboard({
        x = 0,
        y = -10,
        w = 320,
        h = 200,
        mode = "text",
        target = demo_textarea,
        auto_hide = true,
    })

    y_offset = y_offset + 100

    -- 9. 消息框组件（按钮演示）
    airui.label({
        parent = scroll_container,
        text = "9. 消息框组件 (Msgbox)",
        x = 10,
        y = y_offset,
        w = 300,
        h = 20,
    })

    local demo_msgbox_btn = airui.button({
        parent = scroll_container,
        x = 20,
        y = y_offset + 30,
        w = 120,
        h = 40,
        text = "显示消息",
        on_click = function()
            local msg = airui.msgbox({
                text = "这是一个消息框",
                buttons = { "确定" },
                on_action = function(self, label)
                    if label == "确定" then
                        self:hide()
                    end
                end

            })
            msg:show()
        end
    })

    y_offset = y_offset + 80

    -- 10. 图片组件（需要图片文件）
    airui.label({
        parent = scroll_container,
        text = "10. 图片组件 (Image)",
        x = 10,
        y = y_offset,
        w = 300,
        h = 20,
    })

    -- 假设有图片文件
    local demo_image = airui.image({
        parent = scroll_container,
        x = 20,
        y = y_offset + 30,
        w = 80,
        h = 80,
        src = "/luadb/logo.jpg",
        on_click = function()
            log.info("all_component", "图片被点击")
        end
    })

    y_offset = y_offset + 120

    -- 11. 选项卡组件
    airui.label({
        parent = scroll_container,
        text = "11. 选项卡组件 (Tabview)",
        x = 10,
        y = y_offset,
        w = 300,
        h = 20,
    })

    local demo_tabview = airui.tabview({
        parent = scroll_container,
        x = 20,
        y = y_offset + 30,
        w = 280,
        h = 150,
        tabs = { "标签1", "标签2" },
        active = 0,
    })

    -- 获取页面内容并添加标签
    local tab1_content = demo_tabview:get_content(0)
    if tab1_content then
        airui.label({
            parent = tab1_content,
            text = "标签1内容",
            x = 20,
            y = 20,
            w = 240,
            h = 30,
        })
    end

    y_offset = y_offset + 190

    -- 12. 窗口组件
    airui.label({
        parent = scroll_container,
        text = "12. 窗口组件 (Window)",
        x = 10,
        y = y_offset,
        w = 300,
        h = 20,
    })

    local demo_window_btn = airui.button({
        parent = scroll_container,
        x = 20,
        y = y_offset + 30,
        w = 120,
        h = 40,
        text = "打开窗口",
        on_click = function()
            local win = airui.win({
                parent = airui.screen,
                title = "演示窗口",
                x = 60,
                y = 120,
                w = 200,
                h = 250,
                close_btn = true,
                on_close = function(self)
                    log.info("all_component", "窗口关闭")
                end
            })

            win:add_content(airui.label({
                text = "窗口内容演示",
                x = 20,
                y = 20,
                w = 160,
                h = 30,
            }))

            win:add_content(airui.button({
                text = "关闭",
                x = 60,
                y = 70,
                w = 80,
                h = 40,
                on_click = function()
                    win:close()
                end
            }))
        end
    })

    y_offset = y_offset + 80

    -- 组件总数显示
    airui.label({
        parent = scroll_container,
        text = "共展示12个AirUI组件",
        x = 10,
        y = y_offset + 20,
        w = 300,
        h = 20,
    })

    -- 交互提示
    local interact_label = airui.label({
        parent = scroll_container,
        text = "提示: 点击各个组件查看交互效果",
        x = 10,
        y = y_offset + 50,
        w = 300,
        h = 20,
    })

    -- 组件计数
    local component_count = 12
    local count_label = airui.label({
        parent = scroll_container,
        text = "组件总数: " .. component_count,
        x = 10,
        y = y_offset + 80,
        w = 300,
        h = 20,
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "AirUI组件综合演示",
        x = 10,
        y = 440,
        w = 300,
        h = 20,
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
