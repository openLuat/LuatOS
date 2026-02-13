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
function msgbox_page.create_ui()
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
        color = 0xE91E63,
    })

    airui.label({
        parent = title_bar,
        text = "消息框组件演示",
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

    -- 当前y坐标，使用两列网格布局
    local current_y = 10
    local card_width = 480
    local card_height = 140
    local card_gap_x = 30
    local card_gap_y = 20

    --------------------------------------------------------------------
    -- 第一行：基本消息框
    --------------------------------------------------------------------
    -- 卡片1: 基本消息框
    local card1 = create_demo_card(scroll_container, "示例1: 基本消息框", 20, current_y, card_width, card_height)

    airui.label({
        parent = card1,
        text = "显示一个简单的消息框",
        x = 15,
        y = 45,
        w = card_width - 30,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local basic_msg_btn = airui.button({
        parent = card1,
        x = 150,
        y = 75,
        w = 180,
        h = 45,
        text = "显示基本消息",
        size = 16,
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

    -- 卡片2: 带标题的消息框
    local card2 = create_demo_card(scroll_container, "示例2: 带标题消息框", 530, current_y, card_width, card_height)

    airui.label({
        parent = card2,
        text = "显示带标题的消息框",
        x = 15,
        y = 45,
        w = card_width - 30,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local title_msg_btn = airui.button({
        parent = card2,
        x = 150,
        y = 75,
        w = 180,
        h = 45,
        text = "带标题消息",
        size = 16,
        on_click = function()
            local msg = airui.msgbox({
                title = "系统提示",
                text = "操作成功完成!",
                buttons = { "确定" },
                on_action = function(self, label)
                    log.info("msgbox", "点击了: " .. label)
                    self:hide()
                end
            })
            msg:show()
        end
    })

    current_y = current_y + card_height + card_gap_y

    --------------------------------------------------------------------
    -- 第二行：多个按钮的消息框
    --------------------------------------------------------------------
    -- 卡片3: 多个按钮的消息框
    local card3 = create_demo_card(scroll_container, "示例3: 多个按钮消息框", 20, current_y, card_width, 140)

    airui.label({
        parent = card3,
        text = "显示带有确认和取消按钮的消息框",
        x = 15,
        y = 45,
        w = card_width - 30,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local multi_msg_btn = airui.button({
        parent = card3,
        x = 150,
        y = 80,
        w = 180,
        h = 45,
        text = "确认对话框",
        size = 16,
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
                    
                    self:hide()
                end
            })
            msg:show()
        end
    })

    -- 卡片4: 三个按钮的消息框
    local card4 = create_demo_card(scroll_container, "示例4: 三个按钮消息框", 530, current_y, card_width, 140)

    airui.label({
        parent = card4,
        text = "显示带有三个按钮的消息框",
        x = 15,
        y = 45,
        w = card_width - 30,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local three_btn_msg = airui.button({
        parent = card4,
        x = 150,
        y = 80,
        w = 180,
        h = 45,
        text = "三个按钮",
        size = 16,
        on_click = function()
            local msg = airui.msgbox({
                title = "选择操作",
                text = "请选择要执行的操作:",
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

    current_y = current_y + 150

    --------------------------------------------------------------------
    -- 第三行：自动关闭的消息框
    --------------------------------------------------------------------
    -- 卡片5: 自动关闭的消息框
    local card5 = create_demo_card(scroll_container, "示例5: 自动关闭消息框", 20, current_y, card_width, 130)

    airui.label({
        parent = card5,
        text = "显示3秒后自动关闭的消息框",
        x = 15,
        y = 45,
        w = card_width - 30,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local auto_msg_btn = airui.button({
        parent = card5,
        x = 150,
        y = 75,
        w = 180,
        h = 45,
        text = "显示3秒",
        size = 16,
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

    -- 卡片6: 长消息自动关闭
    local card6 = create_demo_card(scroll_container, "示例6: 长消息自动关闭", 530, current_y, card_width, 130)

    airui.label({
        parent = card6,
        text = "显示5秒后自动关闭的长消息",
        x = 15,
        y = 45,
        w = card_width - 30,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local long_auto_msg = airui.button({
        parent = card6,
        x = 150,
        y = 75,
        w = 180,
        h = 45,
        text = "显示5秒",
        size = 16,
        on_click = function()
            local msg = airui.msgbox({
                title = "通知",
                text = "这是一条较长的消息内容，将在5秒后自动关闭。您也可以点击按钮立即关闭。",
                buttons = { "立即关闭" },
                timeout = 5000,
                on_action = function(self, label)
                    log.info("msgbox", "点击了立即关闭")
                    self:hide()
                end
            })
            msg:show()
        end
    })

    current_y = current_y + 140

    --------------------------------------------------------------------
    -- 第四行：自定义按钮的消息框
    --------------------------------------------------------------------
     -- 卡片7: 消息框链式调用
    local card9 = create_demo_card(scroll_container, "示例7: 链式调用", 20, current_y, card_width, 150)

    airui.label({
        parent = card9,
        text = "显示链式调用的消息框",
        x = 15,
        y = 45,
        w = card_width - 30,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local chain_msg_btn = airui.button({
        parent = card9,
        x = 150,
        y = 85,
        w = 180,
        h = 45,
        text = "链式消息",
        size = 16,
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

    -- 卡片8: 多行文本消息框
    local card8 = create_demo_card(scroll_container, "示例8: 多行文本消息", 530, current_y, card_width, 140)

    airui.label({
        parent = card8,
        text = "显示多行文本消息框",
        x = 15,
        y = 45,
        w = card_width - 30,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local multiline_msg_btn = airui.button({
        parent = card8,
        x = 150,
        y = 80,
        w = 180,
        h = 45,
        text = "多行消息",
        size = 16,
        on_click = function()
            local msg = airui.msgbox({
                title = "详细信息",
                text = "这是第一行文本\n这是第二行文本\n这是第三行文本\n消息框支持多行显示\n可以显示更多内容",
                buttons = { "确定" },
                on_action = function(self, label)
                    log.info("msgbox", "多行消息被确认")
                    self:hide()
                end
            })
            msg:show()
        end
    })


    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 点击按钮显示不同类型的消息框",
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