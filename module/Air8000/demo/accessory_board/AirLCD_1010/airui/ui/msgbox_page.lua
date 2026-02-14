--[[
@module     msgbox_page
@summary    消息框组件演示页面
@version    1.0.0
@date       2026.01.30
@author     江访
@usage      本文件是消息框组件的演示页面，展示消息框的各种用法。
]]

local msgbox_page = {}

----------------------------------------------------------------
-- 页面UI元素
----------------------------------------------------------------
local main_container = nil

----------------------------------------------------------------
-- 辅助函数：创建带标题的容器
----------------------------------------------------------------
local function create_demo_container(parent, title, x, y, width, height)
    local container = airui.container({
        parent = parent,
        x = x,
        y = y,
        w = width,
        h = height,
        color = 0xFFFFFF,
        radius = 8,
    })

    airui.label({
        parent = container,
        text = title,
        x = 10,
        y = 5,
        w = width - 20,
        h = 25,
        color = 0x333333,
        size = 14,
    })

    return container
end

----------------------------------------------------------------
-- 创建UI
----------------------------------------------------------------
function msgbox_page.create_ui()
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
        color = 0xE91E63,
    })

    airui.label({
        parent = title_bar,
        text = "消息框组件演示",
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
    -- 示例1: 基本消息框
    --------------------------------------------------------------------
    local demo1_container = create_demo_container(scroll_container, "示例1: 基本消息框", 10, current_y, 300, 100)
    current_y = current_y + 100 + 10

    airui.label({
        parent = demo1_container,
        text = "显示基本消息框",
        x = 10,
        y = 30,
        w = 280,
        h = 20,
        color = 0x666666,
        size = 12,
    })

    local basic_msg_btn = airui.button({
        parent = demo1_container,
        x = 80,
        y = 60,
        w = 140,
        h = 40,
        text = "显示消息",
        on_click = function()
            local msg = airui.msgbox({
                text = "这是一个基本消息框",
                buttons = { "确定" },
                on_action = function(self, label)
                    log.info("msgbox", "点击了: " .. label)
                    self:hide()  -- 点击按钮后关闭消息框
                end
            })
            msg:show()
        end
    })

    --------------------------------------------------------------------
    -- 示例2: 带标题的消息框
    --------------------------------------------------------------------
    local demo2_container = create_demo_container(scroll_container, "示例2: 带标题消息框", 10, current_y, 300, 100)
    current_y = current_y + 100 + 10

    airui.label({
        parent = demo2_container,
        text = "显示带标题的消息框",
        x = 10,
        y = 30,
        w = 280,
        h = 20,
        color = 0x666666,
        size = 12,
    })

    local title_msg_btn = airui.button({
        parent = demo2_container,
        x = 80,
        y = 60,
        w = 140,
        h = 40,
        text = "带标题消息",
        on_click = function()
            local msg = airui.msgbox({
                title = "系统提示",
                text = "操作成功完成!",
                buttons = { "确定" },
                on_action = function(self, label)
                    log.info("msgbox", "点击了: " .. label)
                    self:hide()  -- 点击按钮后关闭消息框
                end
            })
            msg:show()
        end
    })

    --------------------------------------------------------------------
    -- 示例3: 多个按钮的消息框
    --------------------------------------------------------------------
    local demo3_container = create_demo_container(scroll_container, "示例3: 多个按钮消息框", 10, current_y, 300, 120)
    current_y = current_y + 120 + 10

    airui.label({
        parent = demo3_container,
        text = "显示带有确认和取消按钮的消息框",
        x = 10,
        y = 30,
        w = 280,
        h = 20,
        color = 0x666666,
        size = 12,
    })

    local multi_msg_btn = airui.button({
        parent = demo3_container,
        x = 80,
        y = 60,
        w = 140,
        h = 40,
        text = "确认对话框",
        on_click = function()
            local msg = airui.msgbox({
                title = "确认操作",
                text = "确定要删除这个文件吗？",
                buttons = { "取消", "确定" },
                on_action = function(self, label)
                    log.info("msgbox", "点击了: " .. label)
                    
                    if label == "确定" then
                        log.info("msgbox", "执行删除操作")
                        local confirm_msg = airui.msgbox({
                            text = "文件已删除",
                            buttons = { "确定" },
                            timeout = 1500,
                            on_action = function(self, label)
                                self:hide()
                            end
                        })
                        confirm_msg:show()
                    else
                        log.info("msgbox", "操作已取消")
                    end
                    
                    self:hide()  -- 点击按钮后关闭当前消息框
                end
            })
            msg:show()
        end
    })

    --------------------------------------------------------------------
    -- 示例4: 自动关闭的消息框
    --------------------------------------------------------------------
    local demo4_container = create_demo_container(scroll_container, "示例4: 自动关闭消息框", 10, current_y, 300, 100)
    current_y = current_y + 100 + 10

    airui.label({
        parent = demo4_container,
        text = "显示3秒后自动关闭的消息框",
        x = 10,
        y = 30,
        w = 280,
        h = 20,
        color = 0x666666,
        size = 12,
    })

    local auto_msg_btn = airui.button({
        parent = demo4_container,
        x = 80,
        y = 60,
        w = 140,
        h = 40,
        text = "显示3秒",
        on_click = function()
            local msg = airui.msgbox({
                text = "这条消息将在3秒后自动关闭",
                buttons = { "确定" },
                timeout = 3000,
                on_action = function(self, label)
                    log.info("msgbox", "消息框被点击: " .. label)
                    self:hide()
                end
            })
            msg:show()
        end
    })

    --------------------------------------------------------------------
    -- 示例5: 自定义按钮的消息框
    --------------------------------------------------------------------
    local demo5_container = create_demo_container(scroll_container, "示例5: 自定义按钮", 10, current_y, 300, 120)
    current_y = current_y + 120 + 10

    airui.label({
        parent = demo5_container,
        text = "显示带有自定义按钮的消息框",
        x = 10,
        y = 30,
        w = 280,
        h = 20,
        color = 0x666666,
        size = 12,
    })

    local custom_msg_btn = airui.button({
        parent = demo5_container,
        x = 80,
        y = 60,
        w = 140,
        h = 40,
        text = "自定义按钮",
        on_click = function()
            local msg = airui.msgbox({
                title = "选择操作",
                text = "请选择一个操作:",
                buttons = { "保存", "另存为", "取消" },
                on_action = function(self, label)
                    local action_msg = airui.msgbox({
                        text = "选择了: " .. label,
                        buttons = { "确定" },
                        timeout = 1500,
                        on_action = function(self, label)
                            self:hide()
                        end
                    })
                    action_msg:show()
                    log.info("msgbox", "选择了操作: " .. label)
                    self:hide()
                end
            })
            msg:show()
        end
    })

    --------------------------------------------------------------------
    -- 示例6: 多行文本消息框
    --------------------------------------------------------------------
    local demo6_container = create_demo_container(scroll_container, "示例6: 多行文本消息", 10, current_y, 300, 120)
    current_y = current_y + 120 + 10

    airui.label({
        parent = demo6_container,
        text = "显示多行文本消息框",
        x = 10,
        y = 30,
        w = 280,
        h = 20,
        color = 0x666666,
        size = 12,
    })

    local multiline_msg_btn = airui.button({
        parent = demo6_container,
        x = 80,
        y = 60,
        w = 140,
        h = 40,
        text = "多行消息",
        on_click = function()
            local msg = airui.msgbox({
                title = "详细信息",
                text = "这是第一行文本\n这是第二行文本\n这是第三行文本\n消息框支持多行显示",
                buttons = { "确定" },
                on_action = function(self, label)
                    log.info("msgbox", "多行消息被确认")
                    self:hide()
                end
            })
            msg:show()
        end
    })

    --------------------------------------------------------------------
    -- 示例7: 消息框链式调用
    --------------------------------------------------------------------
    local demo7_container = create_demo_container(scroll_container, "示例7: 链式调用", 10, current_y, 300, 140)
    current_y = current_y + 140 + 10

    airui.label({
        parent = demo7_container,
        text = "显示链式调用的消息框",
        x = 10,
        y = 30,
        w = 280,
        h = 20,
        color = 0x666666,
        size = 12,
    })

    local chain_msg_btn = airui.button({
        parent = demo7_container,
        x = 80,
        y = 60,
        w = 140,
        h = 40,
        text = "链式消息",
        on_click = function()
            local msg1 = airui.msgbox({
                title = "第一步",
                text = "这是第一步操作",
                buttons = { "下一步" },
                on_action = function(self, label)
                    self:hide()
                    local msg2 = airui.msgbox({
                        title = "第二步",
                        text = "这是第二步操作",
                        buttons = { "下一步" },
                        on_action = function(self, label)
                            self:hide()
                            local msg3 = airui.msgbox({
                                title = "完成",
                                text = "所有步骤已完成",
                                buttons = { "确定" },
                                timeout = 2000,
                                on_action = function(self, label)
                                    self:hide()
                                end
                            })
                            msg3:show()
                        end
                    })
                    msg2:show()
                end
            })
            msg1:show()
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 点击按钮显示不同类型的消息框",
        x = 10,
        y = 440,
        w = 300,
        h = 20,
        color = 0x666666,
        size = 12,
    })
end

----------------------------------------------------------------
-- 初始化页面
----------------------------------------------------------------
function msgbox_page.init(params)
    msgbox_page.create_ui()
end

----------------------------------------------------------------
-- 清理页面
----------------------------------------------------------------
function msgbox_page.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return msgbox_page