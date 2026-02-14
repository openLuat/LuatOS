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
-- 辅助函数：创建演示卡片
----------------------------------------------------------------
local function create_demo_card(parent, title, x, y, width, height)
    local card = airui.container({
        parent = parent,
        x = x,
        y = y,
        w = width,
        h = height,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card,
        text = title,
        x = 15,
        y = 10,
        w = width - 30,
        h = 30,
        color = 0x333333,
        size = 16,
    })

    return card
end

----------------------------------------------------------------
-- 创建UI
----------------------------------------------------------------
function tabview_page.create_ui()
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
        color = 0xFF5722,
    })

    airui.label({
        parent = title_bar,
        text = "选项卡组件演示",
        x = 20,
        y = 15,
        w = 300,
        h = 30,
        color = 0xFFFFFF,
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

    -- 使用两列网格布局
    local left_column_x = 20
    local right_column_x = 522
    local current_y = 10
    local card_width = 480
    local card_height = 250
    local card_gap_y = 20

    --------------------------------------------------------------------
    -- 示例1: 基本选项卡（左列）
    --------------------------------------------------------------------
    local card1 = create_demo_card(scroll_container, "示例1: 基本选项卡", left_column_x, current_y, card_width, card_height)

    airui.label({
        parent = card1,
        text = "包含首页、消息、设置三个标签页",
        x = 20,
        y = 45,
        w = card_width - 40,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local basic_tabview = airui.tabview({
        parent = card1,
        x = 20,
        y = 80,
        w = card_width - 40,
        h = 150,
        tabs = { "首页", "消息", "设置" },
        active = 0,
    })

    -- 获取各个页面的内容并添加组件
    local tab1_content = basic_tabview:get_content(0)
    if tab1_content then
        airui.label({
            parent = tab1_content,
            text = "这是首页内容区域",
            x = 20,
            y = 20,
            w = 420,
            h = 30,
            color = 0x333333,
            size = 14,
        })

        airui.label({
            parent = tab1_content,
            text = "欢迎使用选项卡组件",
            x = 20,
            y = 60,
            w = 420,
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
            w = 420,
            h = 30,
            color = 0x333333,
            size = 14,
        })

        local msg_btn = airui.button({
            parent = tab2_content,
            x = 20,
            y = 60,
            w = 120,
            h = 40,
            text = "新消息",
            size = 14,
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
            w = 420,
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

    -- 示例2: 嵌套选项卡（右列）
    local card2 = create_demo_card(scroll_container, "示例2: 嵌套选项卡", right_column_x, current_y, card_width, card_height)

    airui.label({
        parent = card2,
        text = "在主容器中嵌套选项卡",
        x = 20,
        y = 45,
        w = card_width - 40,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local nested_container = airui.container({
        parent = card2,
        x = 20,
        y = 80,
        w = card_width - 40,
        h = 150,
        color = 0xFCE4EC,
        radius = 8,
    })

    airui.label({
        parent = nested_container,
        text = "主容器中的嵌套选项卡",
        x = 20,
        y = 10,
        w = 440,
        h = 20,
        color = 0x333333,
        size = 12,
    })

    -- 在容器内创建嵌套的选项卡
    local inner_tabview = airui.tabview({
        parent = nested_container,
        x = 10,
        y = 40,
        w = 440,
        h = 100,
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
            w = 400,
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
            w = 400,
            h = 30,
            color = 0x333333,
            size = 12,
        })
    end

    current_y = current_y + card_height + card_gap_y

    --------------------------------------------------------------------
    -- 示例3: 多选项卡演示（左列）
    --------------------------------------------------------------------
    local card3 = create_demo_card(scroll_container, "示例3: 多选项卡演示", left_column_x, current_y, card_width, card_height)

    airui.label({
        parent = card3,
        text = "包含多个标签页的选项卡",
        x = 20,
        y = 45,
        w = card_width - 40,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local multi_tabview = airui.tabview({
        parent = card3,
        x = 20,
        y = 80,
        w = card_width - 40,
        h = 150,
        tabs = { "标签A", "标签B", "标签C", "标签D", "标签E" },
        active = 0,
    })

    -- 为每个标签页添加内容
    for i = 0, 4 do
        local tab_content = multi_tabview:get_content(i)
        if tab_content then
            airui.label({
                parent = tab_content,
                text = "这是标签" .. string.char(65 + i) .. "的内容区域",
                x = 20,
                y = 20,
                w = 420,
                h = 30,
                color = 0x333333,
                size = 12,
            })
            
            airui.label({
                parent = tab_content,
                text = "第" .. (i + 1) .. "个标签页的详细信息",
                x = 20,
                y = 60,
                w = 420,
                h = 30,
                color = 0x666666,
                size = 12,
            })
        end
    end

    -- 示例4: 选项卡控制（右列）
    local card4 = create_demo_card(scroll_container, "示例4: 选项卡控制", right_column_x, current_y, card_width, card_height)

    airui.label({
        parent = card4,
        text = "动态控制选项卡的显示和切换",
        x = 20,
        y = 45,
        w = card_width - 40,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local control_tabview = airui.tabview({
        parent = card4,
        x = 20,
        y = 80,
        w = card_width - 40,
        h = 120,
        tabs = { "控制页1", "控制页2", "控制页3" },
        active = 0,
    })

    -- 控制按钮
    local switch_to_btn = airui.button({
        parent = card4,
        x = 20,
        y = 210,
        w = 140,
        h = 45,
        text = "切换到第2页",
        size = 14,
        on_click = function()
            control_tabview:set_active(1)
            log.info("tabview", "切换到第2个标签页")
        end
    })

    local get_active_btn = airui.button({
        parent = card4,
        x = 180,
        y = 210,
        w = 140,
        h = 45,
        text = "获取当前页",
        size = 14,
        on_click = function()
            local active_index = control_tabview:get_active()
            local msg = airui.msgbox({
                text = "当前活动标签页: " .. (active_index + 1),
                buttons = { "确定" },
                timeout = 1500,
                on_action = function(self, label)
                    self:hide()
                end
            })
            msg:show()
        end
    })

    local add_tab_btn = airui.button({
        parent = card4,
        x = 340,
        y = 210,
        w = 140,
        h = 45,
        text = "添加标签页",
        size = 14,
        on_click = function()
            log.info("tabview", "添加标签页功能")
            local msg = airui.msgbox({
                text = "添加标签页功能需要扩展API支持",
                buttons = { "确定" },
                timeout = 1500,
                on_action = function(self, label)
                    self:hide()
                end
            })
            msg:show()
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 选项卡支持多页面切换、嵌套和动态控制",
        x = 20,
        y = 560,
        w = 500,
        h = 25,
        color = 0x666666,
        size = 14,
    })
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