--[[
@module  container_win
@summary 容器组件演示窗口
@version 1.1.0
@date    2026.03.18
@author  江访
@usage
本文件是容器组件的演示窗口，采用exwin窗口管理扩展库。
展示容器的各种用法，支持透明度、点击回调等。
]]


local win_id = nil
local main_container = nil

local SCREEN_W, SCREEN_H = 320, 480
local MARGIN = 12
local COMPONENT_H = 36
local SPACING = 8

local function create_ui()
    main_container = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 50,
        color = 0xFF9800,
    })
    airui.label({
        parent = title_bar,
        text = "容器组件演示",
        x = 10,
        y = 15,
        w = 200,
        h = 20,
        font_size = 16,
        color = 0xFFFFFF,
    })
    airui.button({
        parent = title_bar,
        x = SCREEN_W - 70,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function() exwin.close(win_id) end,
    })

    -- 滚动容器
    local scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 50,
        w = SCREEN_W,
        h = SCREEN_H - 100,
        color = 0xF5F5F5,
    })

    local current_y = MARGIN

    -- 示例1: 基本容器
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本容器",
        x = MARGIN,
        y = current_y,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25

    local basic_container = airui.container({
        parent = scroll_container,
        x = MARGIN + 8,
        y = current_y,
        w = SCREEN_W - MARGIN * 2 - 16,
        h = 80,
        color = 0xE3F2FD,
        on_click = function()
            log.info("container", "基本容器被点击")
            local msg = airui.msgbox({
                text = "基本容器被点击\n颜色: 0xE3F2FD",
                buttons = { "确定" },
                timeout = 1500,
                on_action = function(self, label) self:hide() end,
            })
            msg:show()
        end,
    })
    airui.label({
        parent = basic_container,
        text = "这是一个容器 (可点击)",
        x = 10,
        y = 10,
        w = 240,
        h = 20,
        font_size = 14,
    })
    airui.label({
        parent = basic_container,
        text = "点击容器查看交互效果",
        x = 10,
        y = 40,
        w = 240,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 90

    -- 示例2: 圆角容器
    airui.label({
        parent = scroll_container,
        text = "示例2: 圆角容器",
        x = MARGIN,
        y = current_y,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25
    local rounded_container = airui.container({
        parent = scroll_container,
        x = MARGIN + 8,
        y = current_y,
        w = SCREEN_W - MARGIN * 2 - 16,
        h = 80,
        color = 0xFFEBEE,
        radius = 20,
        on_click = function()
            log.info("container", "圆角容器被点击")
            local msg = airui.msgbox({
                text = "圆角容器被点击\n半径: 20, 颜色: 0xFFEBEE",
                buttons = { "确定" },
                timeout = 1500,
                on_action = function(self, label) self:hide() end,
            })
            msg:show()
        end,
    })
    airui.label({
        parent = rounded_container,
        text = "圆角半径: 20 (可点击)",
        x = 10,
        y = 30,
        w = 240,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 90

    -- 示例3: 嵌套容器
    airui.label({
        parent = scroll_container,
        text = "示例3: 嵌套容器",
        x = MARGIN,
        y = current_y,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25
    local parent_container = airui.container({
        parent = scroll_container,
        x = MARGIN + 8,
        y = current_y,
        w = SCREEN_W - MARGIN * 2 - 16,
        h = 120,
        color = 0xE8F5E8,
        radius = 10,
        on_click = function()
            log.info("container", "父容器被点击")
            local msg = airui.msgbox({
                text = "父容器被点击\n包含2个子容器",
                buttons = { "确定" },
                timeout = 1500,
                on_action = function(self, label) self:hide() end,
            })
            msg:show()
        end,
    })
    local child1 = airui.container({
        parent = parent_container,
        x = 10,
        y = 10,
        w = 120,
        h = 50,
        color = 0xC8E6C9,
        radius = 5,
        on_click = function()
            log.info("container", "子容器1被点击")
            local msg = airui.msgbox({
                text = "子容器1被点击\n颜色: 0xC8E6C9",
                buttons = { "确定" },
                timeout = 1500,
                on_action = function(self, label) self:hide() end,
            })
            msg:show()
        end,
    })
    airui.label({
        parent = child1,
        text = "子容器1 (可点击)",
        x = 10,
        y = 15,
        w = 100,
        h = 20,
        font_size = 14,
    })
    local child2 = airui.container({
        parent = parent_container,
        x = 150,
        y = 10,
        w = 120,
        h = 50,
        color = 0xA5D6A7,
        radius = 5,
        on_click = function()
            log.info("container", "子容器2被点击")
            local msg = airui.msgbox({
                text = "子容器2被点击\n颜色: 0xA5D6A7",
                buttons = { "确定" },
                timeout = 1500,
                on_action = function(self, label) self:hide() end,
            })
            msg:show()
        end,
    })
    airui.label({
        parent = child2,
        text = "子容器2",
        x = 10,
        y = 15,
        w = 100,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 130

    -- 示例4: 动态显示/隐藏
    airui.label({
        parent = scroll_container,
        text = "示例4: 显示/隐藏容器",
        x = MARGIN,
        y = current_y,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25
    local toggle_container = airui.container({
        parent = scroll_container,
        x = MARGIN + 8,
        y = current_y,
        w = 160,
        h = 60,
        color = 0xE1BEE7,
        radius = 8,
    })
    airui.label({
        parent = toggle_container,
        text = "可隐藏的容器",
        x = 10,
        y = 20,
        w = 140,
        h = 20,
        font_size = 14,
    })
    airui.button({
        parent = scroll_container,
        x = 180,
        y = current_y + 10,
        w = 100,
        h = 40,
        text = "隐藏",
        on_click = function()
            if toggle_container then toggle_container:hide() end
        end,
    })
    current_y = current_y + 70

    -- 示例5: 动态改变颜色
    airui.label({
        parent = scroll_container,
        text = "示例5: 动态改变颜色",
        x = MARGIN,
        y = current_y,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25
    local color_container = airui.container({
        parent = scroll_container,
        x = MARGIN + 8,
        y = current_y,
        w = SCREEN_W - MARGIN * 2 - 16,
        h = 80,
        color = 0x2196F3,
        radius = 8,
    })
    airui.label({
        parent = color_container,
        text = "点击按钮改变颜色",
        x = 10,
        y = 30,
        w = 240,
        h = 20,
        font_size = 14,
    })
    local color_btn = airui.button({
        parent = scroll_container,
        x = MARGIN + 8,
        y = current_y + 90,
        w = 120,
        h = 35,
        text = "随机颜色",
        on_click = function()
            local colors = { 0xFF5722, 0x4CAF50, 0x9C27B0, 0xFF9800, 0x00BCD4 }
            local random_color = colors[math.random(1, #colors)]
            color_container:set_color(random_color)
        end,
    })
    airui.button({
        parent = scroll_container,
        x = MARGIN + 140,
        y = current_y + 90,
        w = 120,
        h = 35,
        text = "重置颜色",
        on_click = function()
            color_container:set_color(0x2196F3)
        end,
    })
    current_y = current_y + 140

    -- 示例6: 透明度和点击回调
    airui.label({
        parent = scroll_container,
        text = "示例6: 透明度和点击回调",
        x = MARGIN,
        y = current_y,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25
    local alpha_container = airui.container({
        parent = scroll_container,
        x = MARGIN + 8,
        y = current_y,
        w = SCREEN_W - MARGIN * 2 - 16,
        h = 100,
        color = 0xFF5722,
        color_opacity = 128,
        radius = 8,
        on_click = function() log.info("container", "容器被点击") end,
    })
    airui.label({
        parent = alpha_container,
        text = "点击我触发打印日志",
        x = 40,
        y = 40,
        w = 200,
        h = 20,
        color = 0xFFFFFF,
        font_size = 14,
    })

    -- 底部提示（由主容器底部显示，此处不再重复）
end

local function on_create()
    math.randomseed(os.time())
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
    log.info("container_win", "窗口销毁")
end

local function on_get_focus()
    log.info("container_win", "窗口获得焦点")
end

local function on_lose_focus()
    log.info("container_win", "窗口失去焦点")
end

sys.subscribe("OPEN_CONTAINER_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("container_win", "窗口打开，ID:", win_id)
    end
end)