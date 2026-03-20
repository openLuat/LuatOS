--[[
@module     tabview_win
@summary    选项卡组件演示页面（exwin窗口管理版本）
@version    1.1.0
@date       2026.03.18
@author     江访
@usage      本文件是选项卡组件的演示页面，采用exwin窗口管理，
            展示选项卡的各种用法，包括基本选项卡、嵌套和多选项卡。
]]

local win_id = nil
local main_container = nil
local scroll_container = nil

-- 屏幕尺寸
local SCREEN_W, SCREEN_H = 320, 480

-- 创建UI
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
        color = 0xFF5722,
    })

    airui.label({
        parent = title_bar,
        text = "选项卡组件演示",
        x = 10,
        y = 15,
        w = 200,
        h = 20,
        font_size = 16,
        color = 0xFFFFFF,
    })

    -- 返回按钮
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
    scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = SCREEN_W,
        h = SCREEN_H - 100,
        color = 0xF5F5F5,
    })

    local current_y = 10

    ----
    -- 示例1: 基本选项卡
    ----
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本选项卡",
        x = 10,
        y = current_y,
        w = SCREEN_W - 20,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25

    local basic_tabview = airui.tabview({
        parent = scroll_container,
        x = 20,
        y = current_y,
        w = SCREEN_W - 40,
        h = 180,
        tabs = { "首窗口", "消息", "设置" },
        active = 0,
    })
    current_y = current_y + 180 + 10

    -- 标签页1：首窗口
    local tab1 = basic_tabview:get_content(0)
    if tab1 then
        airui.label({
            parent = tab1,
            text = "这是首窗口内容",
            x = 20,
            y = 20,
            w = 240,
            h = 30,
            font_size = 14,
        })
        airui.label({
            parent = tab1,
            text = "欢迎使用选项卡组件",
            x = 20,
            y = 60,
            w = 240,
            h = 30,
            font_size = 12,
            color = 0x666666,
        })
    end

    -- 标签页2：消息
    local tab2 = basic_tabview:get_content(1)
    if tab2 then
        airui.label({
            parent = tab2,
            text = "这是消息窗口",
            x = 20,
            y = 20,
            w = 240,
            h = 30,
            font_size = 14,
        })
        airui.button({
            parent = tab2,
            x = 20,
            y = 60,
            w = 100,
            h = 40,
            text = "新消息",
            on_click = function()
                log.info("tabview_win", "新消息按钮被点击")
                local msg = airui.msgbox({
                    text = "收到新消息",
                    buttons = { "确定" },
                    timeout = 1500,
                    on_action = function(self, label) self:hide() end
                })
                msg:show()
            end
        })
    end

    -- 标签页3：设置
    local tab3 = basic_tabview:get_content(2)
    if tab3 then
        airui.label({
            parent = tab3,
            text = "这是设置窗口",
            x = 20,
            y = 20,
            w = 240,
            h = 30,
            font_size = 14,
        })
        local setting_switch = airui.switch({
            parent = tab3,
            x = 20,
            y = 60,
            w = 60,
            h = 30,
            checked = true,
            on_change = function(self)
                log.info("tabview_win", "设置开关: " .. tostring(self:get_state()))
                local status = self:get_state() and "开启" or "关闭"
                local msg = airui.msgbox({
                    text = "通知已" .. status,
                    buttons = { "确定" },
                    timeout = 1500,
                    on_action = function(self, label) self:hide() end
                })
                msg:show()
            end
        })
        airui.label({
            parent = tab3,
            text = "启用通知",
            x = 90,
            y = 65,
            w = 100,
            h = 20,
            font_size = 12,
        })
    end

    ----
    -- 示例2: 嵌套选项卡
    ----
    airui.label({
        parent = scroll_container,
        text = "示例2: 嵌套选项卡",
        x = 10,
        y = current_y,
        w = SCREEN_W - 20,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25

    local nested_container = airui.container({
        parent = scroll_container,
        x = 20,
        y = current_y,
        w = SCREEN_W - 40,
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
        font_size = 12,
    })

    local inner_tabview = airui.tabview({
        parent = nested_container,
        x = 10,
        y = 40,
        w = 260,
        h = 130,
        tabs = { "子窗口1", "子窗口2" },
        active = 0,
    })

    local inner1 = inner_tabview:get_content(0)
    if inner1 then
        airui.label({
            parent = inner1,
            text = "第一个子窗口内容",
            x = 20,
            y = 20,
            w = 220,
            h = 30,
            font_size = 12,
        })
    end

    local inner2 = inner_tabview:get_content(1)
    if inner2 then
        airui.label({
            parent = inner2,
            text = "第二个子窗口内容",
            x = 20,
            y = 20,
            w = 220,
            h = 30,
            font_size = 12,
        })
    end

    ----
    -- 示例3: 多选项卡演示
    ----
    airui.label({
        parent = scroll_container,
        text = "示例3: 多选项卡演示",
        x = 10,
        y = current_y,
        w = SCREEN_W - 20,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25

    local multi_tabview = airui.tabview({
        parent = scroll_container,
        x = 20,
        y = current_y,
        w = SCREEN_W - 40,
        h = 150,
        tabs = { "标签A", "标签B", "标签C", "标签D" },
        active = 0,
    })
    current_y = current_y + 150 + 10

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
                font_size = 12,
            })
        end
    end

    -- 底部提示（放在主容器底部，固定显示）
    airui.label({
        parent = main_container,
        text = "提示: 点击选项卡切换不同内容页面",
        x = 10,
        y = SCREEN_H - 30,
        w = SCREEN_W - 20,
        h = 20,
        color = 0x666666,
        font_size = 12,
    })
end

-- 窗口创建回调
local function on_create()
    create_ui()
end

-- 窗口销毁回调
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
        scroll_container = nil
    end
    win_id = nil
    log.info("tabview_win", "窗口销毁")
end

-- 窗口获得焦点回调
local function on_get_focus()
    log.info("tabview_win", "窗口获得焦点")
end

-- 窗口失去焦点回调
local function on_lose_focus()
    log.info("tabview_win", "窗口失去焦点")
end

-- 订阅打开选项卡页面消息（与 home_win 中保持一致）
sys.subscribe("OPEN_TABVIEW_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("tabview_win", "窗口打开，ID:", win_id)
    end
end)