--[[
@module  button_page
@summary 按钮组件演示页面
@version 1.0.0
@date    2026.01.30
@author  江访
@usage
本文件是按钮组件的演示页面，展示按钮的各种用法。
]]

local button_page = {}

-- 页面UI元素
local main_container = nil
local click_count = 0

-- 创建UI
function button_page.create_ui()
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
        color = 0xF44336,
    })

    airui.label({
        parent = title_bar,
        text = "按钮组件演示",
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

    -- 使用两列网格布局
    local left_column_x = 20
    local right_column_x = 522
    local y_offset = 10
    local card_width = 480
    local card_height = 200
    local card_gap_y = 20

    -- 示例1: 基本按钮（左列）
    local card1 = airui.container({
        parent = scroll_container,
        x = left_column_x,
        y = y_offset,
        w = card_width,
        h = card_height,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card1,
        text = "示例1: 基本按钮",
        x = 15,
        y = 10,
        w = 450,
        h = 30,
        size = 16,
    })

    airui.label({
        parent = card1,
        text = "点击按钮触发事件，支持不同大小",
        x = 15,
        y = 45,
        w = 450,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local basic_btn = airui.button({
        parent = card1,
        x = 50,
        y = 85,
        w = 180,
        h = 55,
        text = "点击我",
        size = 18,
        on_click = function()
            log.info("button", "基本按钮被点击")
            click_count = click_count + 1
            local msg = airui.msgbox({
                text = "按钮被点击 " .. click_count .. " 次",
                buttons = { "确定" },
                timeout = 1500
            })
            msg:show()
        end
    })

    local small_btn = airui.button({
        parent = card1,
        x = 250,
        y = 85,
        w = 120,
        h = 40,
        text = "小按钮",
        size = 14,
        on_click = function()
            log.info("button", "小按钮被点击")
        end
    })

    local large_btn = airui.button({
        parent = card1,
        x = 380,
        y = 85,
        w = 80,
        h = 80,
        text = "大",
        size = 20,
        on_click = function()
            log.info("button", "大按钮被点击")
        end
    })

    -- 示例2: 不同样式的按钮（右列）
    local card2 = airui.container({
        parent = scroll_container,
        x = right_column_x,
        y = y_offset,
        w = card_width,
        h = card_height,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card2,
        text = "示例2: 不同样式的按钮",
        x = 15,
        y = 10,
        w = 450,
        h = 30,
        size = 16,
    })

    airui.label({
        parent = card2,
        text = "支持圆角、直角和不同颜色的按钮",
        x = 15,
        y = 45,
        w = 450,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local round_btn = airui.button({
        parent = card2,
        x = 50,
        y = 85,
        w = 150,
        h = 55,
        text = "圆角按钮",
        size = 16,
        radius = 30,
        on_click = function()
            log.info("button", "圆角按钮被点击")
        end
    })

    local square_btn = airui.button({
        parent = card2,
        x = 220,
        y = 85,
        w = 150,
        h = 55,
        text = "直角按钮",
        size = 16,
        radius = 0,
        on_click = function()
            log.info("button", "直角按钮被点击")
        end
    })

    local colorful_btn = airui.button({
        parent = card2,
        x = 390,
        y = 85,
        w = 150,
        h = 55,
        text = "彩色按钮",
        size = 16,
        color = 0x2196F3,
        on_click = function()
            log.info("button", "彩色按钮被点击")
        end
    })

    y_offset = y_offset + card_height + card_gap_y

    -- 示例3: 动态更新文本（左列）
    local card3 = airui.container({
        parent = scroll_container,
        x = left_column_x,
        y = y_offset,
        w = card_width,
        h = card_height,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card3,
        text = "示例3: 动态更新文本",
        x = 15,
        y = 10,
        w = 450,
        h = 30,
        size = 16,
    })

    airui.label({
        parent = card3,
        text = "按钮文本可以动态更新，显示点击次数",
        x = 15,
        y = 45,
        w = 450,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local dynamic_count = 0
    local dynamic_label = airui.label({
        parent = card3,
        text = "点击次数: 0",
        x = 300,
        y = 105,
        w = 160,
        h = 30,
        size = 16,
    })

    local dynamic_btn = airui.button({
        parent = card3,
        x = 50,
        y = 85,
        w = 200,
        h = 55,
        text = "点击计数",
        size = 18,
        on_click = function()
            dynamic_count = dynamic_count + 1
            dynamic_label:set_text("点击次数: " .. dynamic_count)
            log.info("button", "点击计数: " .. dynamic_count)
        end
    })

    local update_text_btn = airui.button({
        parent = card3,
        x = 50,
        y = 155,
        w = 200,
        h = 45,
        text = "更新文本",
        size = 16,
        on_click = function(self)
            local texts = {"新文本1", "新文本2", "新文本3", "恢复原文本"}
            local random_text = texts[math.random(1, #texts)]
            self:set_text(random_text)
            log.info("button", "按钮文本更新为: " .. random_text)
        end
    })

    math.randomseed(os.time())

    -- 示例4: 按钮组（右列）
    local card4 = airui.container({
        parent = scroll_container,
        x = right_column_x,
        y = y_offset,
        w = card_width,
        h = card_height,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card4,
        text = "示例4: 按钮组",
        x = 15,
        y = 10,
        w = 450,
        h = 30,
        size = 16,
    })

    airui.label({
        parent = card4,
        text = "多个按钮组合使用，形成功能组",
        x = 15,
        y = 45,
        w = 450,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local btn_group_container = airui.container({
        parent = card4,
        x = 50,
        y = 85,
        w = 380,
        h = 100,
        color = 0xE0E0E0,
        radius = 10,
    })

    local btn1 = airui.button({
        parent = btn_group_container,
        x = 20,
        y = 20,
        w = 100,
        h = 45,
        text = "选项1",
        size = 14,
        on_click = function()
            log.info("button", "选项1被选中")
        end
    })

    local btn2 = airui.button({
        parent = btn_group_container,
        x = 140,
        y = 20,
        w = 100,
        h = 45,
        text = "选项2",
        size = 14,
        on_click = function()
            log.info("button", "选项2被选中")
        end
    })

    local btn3 = airui.button({
        parent = btn_group_container,
        x = 260,
        y = 20,
        w = 100,
        h = 45,
        text = "选项3",
        size = 14,
        on_click = function()
            log.info("button", "选项3被选中")
        end
    })

    y_offset = y_offset + card_height + card_gap_y

    -- 示例5: 图标按钮（左列）
    local card5 = airui.container({
        parent = scroll_container,
        x = left_column_x,
        y = y_offset,
        w = card_width,
        h = card_height,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card5,
        text = "示例5: 图标按钮",
        x = 15,
        y = 10,
        w = 450,
        h = 30,
        size = 16,
    })

    airui.label({
        parent = card5,
        text = "按钮可以包含图标和文本",
        x = 15,
        y = 45,
        w = 450,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local icon_btn1 = airui.button({
        parent = card5,
        x = 50,
        y = 85,
        w = 200,
        h = 60,
        symbol = airui.SYMBOL_SETTINGS,
        text = " 设置",
        size = 16,
        on_click = function()
            log.info("button", "设置按钮被点击")
        end
    })

    local icon_btn2 = airui.button({
        parent = card5,
        x = 280,
        y = 85,
        w = 200,
        h = 60,
        symbol = airui.SYMBOL_REFRESH,
        text = " 刷新",
        size = 16,
        on_click = function()
            log.info("button", "刷新按钮被点击")
        end
    })

    local icon_btn3 = airui.button({
        parent = card5,
        x = 50,
        y = 160,
        w = 200,
        h = 60,
        symbol = airui.SYMBOL_DOWNLOAD,
        text = " 下载",
        size = 16,
        on_click = function()
            log.info("button", "下载按钮被点击")
        end
    })

    local icon_btn4 = airui.button({
        parent = card5,
        x = 280,
        y = 160,
        w = 200,
        h = 60,
        symbol = airui.SYMBOL_UPLOAD,
        text = " 上传",
        size = 16,
        on_click = function()
            log.info("button", "上传按钮被点击")
        end
    })

    -- 示例6: 按钮控制（右列）
    local card6 = airui.container({
        parent = scroll_container,
        x = right_column_x,
        y = y_offset,
        w = card_width,
        h = card_height,
        color = 0xFFFFFF,
        radius = 12,
    })

    airui.label({
        parent = card6,
        text = "示例6: 按钮控制",
        x = 15,
        y = 10,
        w = 450,
        h = 30,
        size = 16,
    })

    airui.label({
        parent = card6,
        text = "动态控制按钮的启用、禁用和销毁",
        x = 15,
        y = 45,
        w = 450,
        h = 25,
        color = 0x666666,
        size = 14,
    })

    local control_btn = airui.button({
        parent = card6,
        x = 50,
        y = 85,
        w = 180,
        h = 55,
        text = "可控制按钮",
        size = 18,
        on_click = function(self)
            log.info("button", "控制按钮被点击")
        end
    })

    local disable_btn = airui.button({
        parent = card6,
        x = 250,
        y = 85,
        w = 180,
        h = 55,
        text = "禁用按钮",
        size = 16,
        on_click = function()
            -- 这里需要根据AirUI的API来实现禁用功能
            log.info("button", "禁用控制按钮")
            local msg = airui.msgbox({
                text = "禁用按钮功能需要API支持",
                buttons = { "确定" },
                timeout = 1500
            })
            msg:show()
        end
    })

    local destroy_btn = airui.button({
        parent = card6,
        x = 50,
        y = 155,
        w = 180,
        h = 55,
        text = "销毁按钮",
        size = 16,
        on_click = function()
            control_btn:destroy()
            log.info("button", "已销毁控制按钮")
            local msg = airui.msgbox({
                text = "控制按钮已被销毁",
                buttons = { "确定" },
                timeout = 1500
            })
            msg:show()
        end
    })

    local create_btn = airui.button({
        parent = card6,
        x = 250,
        y = 155,
        w = 180,
        h = 55,
        text = "创建新按钮",
        size = 16,
        on_click = function()
            log.info("button", "创建新按钮")
            local new_btn = airui.button({
                parent = card6,
                x = 50,
                y = 85,
                w = 180,
                h = 55,
                text = "新按钮",
                size = 18,
                on_click = function()
                    log.info("button", "新按钮被点击")
                end
            })
            control_btn = new_btn
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 按钮支持点击事件、动态更新、多种样式和图标显示",
        x = 20,
        y = 560,
        w = 600,
        h = 25,
        size = 14,
    })
end

-- 初始化页面
function button_page.init(params)
    click_count = 0
    button_page.create_ui()
end

-- 清理页面
function button_page.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return button_page