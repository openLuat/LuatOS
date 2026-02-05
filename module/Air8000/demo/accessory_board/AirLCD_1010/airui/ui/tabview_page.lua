--[[
@module     tabview_page
@summary    选项卡组件演示页面
@version    1.0.0
@date       2026.01.30
@author     江访
@usage      本文件是选项卡组件的演示页面，展示选项卡的各种用法。
]]

local tabview_page = {}

----------------------------------------------------------------
-- 页面UI元素
----------------------------------------------------------------
local main_container = nil

----------------------------------------------------------------
-- 创建UI
----------------------------------------------------------------
function tabview_page.create_ui()
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
        color = 0xFF5722,
    })

    airui.label({
        parent = title_bar,
        text = "选项卡组件演示",
        x = 10,
        y = 15,
        w = 200,
        h = 20,
        color = 0xFFFFFF,
        size = 16,
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

    -- 当前y坐标
    local current_y = 10

    --------------------------------------------------------------------
    -- 示例1: 基本选项卡
    --------------------------------------------------------------------
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本选项卡",
        x = 10,
        y = current_y,
        w = 300,
        h = 20,
        color = 0x333333,
        size = 14,
    })
    current_y = current_y + 25

    local basic_tabview = airui.tabview({
        parent = scroll_container,
        x = 20,
        y = current_y,
        w = 280,
        h = 180,
        tabs = { "首页", "消息", "设置" },
        active = 0,
    })
    current_y = current_y + 180 + 10

    -- 获取各个页面的内容并添加组件
    local tab1_content = basic_tabview:get_content(0)
    if tab1_content then
        airui.label({
            parent = tab1_content,
            text = "这是首页内容",
            x = 20,
            y = 20,
            w = 240,
            h = 30,
            color = 0x333333,
            size = 14,
        })

        local home_info = airui.label({
            parent = tab1_content,
            text = "欢迎使用选项卡组件",
            x = 20,
            y = 60,
            w = 240,
            h = 30,
            color = 0x666666,
            size = 12,
        })
    end

    local tab2_content = basic_tabview:get_content(1)
    if tab2_content then
        airui.label({
            parent = tab2_content,
            text = "这是消息页面",
            x = 20,
            y = 20,
            w = 240,
            h = 30,
            color = 0x333333,
            size = 14,
        })

        local msg_btn = airui.button({
            parent = tab2_content,
            x = 20,
            y = 60,
            w = 100,
            h = 40,
            text = "新消息",
            on_click = function()
                log.info("tabview", "新消息按钮被点击")
                local msg = airui.msgbox({
                    text = "收到新消息",
                    buttons = { "确定" },
                    timeout = 1500,
                    on_action = function(self, label)
                        self:hide()
                    end
                })
                msg:show()
            end
        })
    end

    local tab3_content = basic_tabview:get_content(2)
    if tab3_content then
        airui.label({
            parent = tab3_content,
            text = "这是设置页面",
            x = 20,
            y = 20,
            w = 240,
            h = 30,
            color = 0x333333,
            size = 14,
        })

        local setting_switch = airui.switch({
            parent = tab3_content,
            x = 20,
            y = 60,
            w = 60,
            h = 30,
            checked = true,
            on_change = function(state)
                log.info("tabview", "设置开关: " .. tostring(state))
                local status = state and "开启" or "关闭"
                local msg = airui.msgbox({
                    text = "通知已" .. status,
                    buttons = { "确定" },
                    timeout = 1500,
                    on_action = function(self, label)
                        self:hide()
                    end
                })
                msg:show()
            end
        })

        airui.label({
            parent = tab3_content,
            text = "启用通知",
            x = 90,
            y = 65,
            w = 100,
            h = 20,
            color = 0x333333,
            size = 12,
        })
    end

    --------------------------------------------------------------------
    -- 示例2: 嵌套选项卡
    --------------------------------------------------------------------
    airui.label({
        parent = scroll_container,
        text = "示例2: 嵌套选项卡",
        x = 10,
        y = current_y,
        w = 300,
        h = 20,
        color = 0x333333,
        size = 14,
    })
    current_y = current_y + 25

    local nested_container = airui.container({
        parent = scroll_container,
        x = 20,
        y = current_y,
        w = 280,
        h = 180,
        color = 0xFCE4EC,
        radius = 8,
    })
    current_y = current_y + 180 + 10

    airui.label({
        parent = nested_container,
        text = "主容器中的嵌套选项卡",
        x = 20,
        y = 10,
        w = 240,
        h = 20,
        color = 0x333333,
        size = 12,
    })

    -- 在容器内创建嵌套的选项卡
    local inner_tabview = airui.tabview({
        parent = nested_container,
        x = 10,
        y = 40,
        w = 260,
        h = 130,
        tabs = { "子页1", "子页2" },
        active = 0,
    })

    -- 获取子页面内容
    local inner_content1 = inner_tabview:get_content(0)
    if inner_content1 then
        airui.label({
            parent = inner_content1,
            text = "第一个子页面内容",
            x = 20,
            y = 20,
            w = 220,
            h = 30,
            color = 0x333333,
            size = 12,
        })
    end

    local inner_content2 = inner_tabview:get_content(1)
    if inner_content2 then
        airui.label({
            parent = inner_content2,
            text = "第二个子页面内容",
            x = 20,
            y = 20,
            w = 220,
            h = 30,
            color = 0x333333,
            size = 12,
        })
    end


    --------------------------------------------------------------------
    -- 示例3: 多选项卡演示
    --------------------------------------------------------------------
    airui.label({
        parent = scroll_container,
        text = "示例3: 多选项卡演示",
        x = 10,
        y = current_y,
        w = 300,
        h = 20,
        color = 0x333333,
        size = 14,
    })
    current_y = current_y + 25

    local multi_tabview = airui.tabview({
        parent = scroll_container,
        x = 20,
        y = current_y,
        w = 280,
        h = 150,
        tabs = { "标签A", "标签B", "标签C", "标签D" },
        active = 0,
    })
    current_y = current_y + 150 + 10

    -- 为每个标签页添加内容
    for i = 0, 3 do
        local tab_content = multi_tabview:get_content(i)
        if tab_content then
            airui.label({
                parent = tab_content,
                text = "这是标签" .. string.char(65 + i) .. "的内容",
                x = 20,
                y = 20,
                w = 240,
                h = 30,
                color = 0x333333,
                size = 12,
            })
        end
    end
end

----------------------------------------------------------------
-- 初始化页面
----------------------------------------------------------------
function tabview_page.init(params)
    tabview_page.create_ui()
end

----------------------------------------------------------------
-- 清理页面
----------------------------------------------------------------
function tabview_page.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return tabview_page