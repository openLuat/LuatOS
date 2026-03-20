--[[
@module  all_component_win
@summary 所有组件演示窗口
@version 1.1.0
@date    2026.03.18
@author  江访
@usage
本文件是演示AirUI所有组件的综合窗口，采用exwin窗口管理。
]]

local win_id = nil
local main_container = nil
local scroll_container = nil
local update_timer = nil -- 用于可能的定时更新

local SCREEN_W, SCREEN_H = 320, 480
local MARGIN = 12
local COMPONENT_H = 36
local SPACING = 8

local function create_ui()
    log.info(SCREEN_W, SCREEN_H)
    main_container = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0xF5F5F5,
        color_opacity = 255,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
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

    -- 虚拟键盘（复用）
    local keyboard1 = airui.keyboard({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 220,
        mode = "text",
        auto_hide = true,
        bg_color = 0xf1f1f1,
        on_commit = function()
            log.info("keyboard", "commit")
        end,
    })

    -- 滚动容器
    scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 50,
        w = SCREEN_W,
        h = SCREEN_H - 100,
        color = 0xF5F5F5,
    })

    local y_pos = MARGIN

    -- 1. 标签组件
    airui.label({
        parent = scroll_container,
        text = "1. 标签组件 (Label)",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    local demo_label = airui.label({
        parent = scroll_container,
        text = "这是一个标签",
        x = MARGIN + 10,
        y = y_pos + 30,
        w = 120,
        h = 30,
        font_size = 14,
        on_click = function(self) self:set_text("标签被点击") end,
    })
    y_pos = y_pos + 70

    -- 2. 按钮组件
    airui.label({
        parent = scroll_container,
        text = "2. 按钮组件 (Button)",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    airui.button({
        parent = scroll_container,
        x = MARGIN + 10,
        y = y_pos + 30,
        w = 100,
        h = 40,
        text = "点击我",
        on_click = function() log.info("all_component", "按钮被点击") end,
    })
    y_pos = y_pos + 80

    -- 3. 容器组件
    airui.label({
        parent = scroll_container,
        text = "3. 容器组件 (Container)",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    local demo_container = airui.container({
        parent = scroll_container,
        x = MARGIN + 10,
        y = y_pos + 30,
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
        font_size = 14,
    })
    y_pos = y_pos + 100

    -- 4. 进度条组件
    airui.label({
        parent = scroll_container,
        text = "4. 进度条组件 (Progress Bar)",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    airui.bar({
        parent = scroll_container,
        x = MARGIN + 10,
        y = y_pos + 30,
        w = 200,
        h = 20,
        value = 65,
        indicator_color = 0x4CAF50,
        show_progress_text = true,
        progress_text_format = "%d%%",
    })
    y_pos = y_pos + 60

    -- 5. 开关组件
    airui.label({
        parent = scroll_container,
        text = "5. 开关组件 (Switch)",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    airui.switch({
        parent = scroll_container,
        x = MARGIN + 10,
        y = y_pos + 30,
        w = 60,
        h = 30,
        checked = true,
        on_change = function(self)
            log.info("all_component", "开关状态: " .. tostring(self:get_state()))
        end,
    })
    y_pos = y_pos + 70

    -- 6. 下拉框组件
    airui.label({
        parent = scroll_container,
        text = "6. 下拉框组件 (Dropdown)",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    airui.dropdown({
        parent = scroll_container,
        x = MARGIN + 10,
        y = y_pos + 30,
        w = 150,
        h = 35,
        options = { "选项1", "选项2", "选项3" },
        default_index = 0,
        on_change = function(idx)
            log.info("all_component", "选择了选项: " .. (idx + 1))
        end,
    })
    y_pos = y_pos + 75

    -- 7. 表格组件
    airui.label({
        parent = scroll_container,
        text = "7. 表格组件 (Table)",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    local demo_table = airui.table({
        parent = scroll_container,
        x = MARGIN + 10,
        y = y_pos + 30,
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
    y_pos = y_pos + 120

    -- 8. 输入框组件
    airui.label({
        parent = scroll_container,
        text = "8. 输入框组件 (Textarea)",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    airui.textarea({
        parent = scroll_container,
        x = MARGIN + 10,
        y = y_pos + 30,
        w = 150,
        h = 60,
        placeholder = "请输入文本...",
        max_len = 50,
        keyboard = keyboard1,
    })
    y_pos = y_pos + 100

    -- 9. 消息框组件（按钮演示）
    airui.label({
        parent = scroll_container,
        text = "9. 消息框组件 (Msgbox)",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    airui.button({
        parent = scroll_container,
        x = MARGIN + 10,
        y = y_pos + 30,
        w = 120,
        h = 40,
        text = "显示消息",
        on_click = function()
            local msg = airui.msgbox({
                text = "这是一个消息框",
                buttons = { "确定" },
                on_action = function(self, label)
                    if label == "确定" then self:hide() end
                end,
            })
            msg:show()
        end,
    })
    y_pos = y_pos + 80

    -- 10. 图片组件
    airui.label({
        parent = scroll_container,
        text = "10. 图片组件 (Image)",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    airui.image({
        parent = scroll_container,
        x = MARGIN + 10,
        y = y_pos + 30,
        w = 80,
        h = 80,
        src = "/luadb/logo.jpg", -- 请确保文件存在
        on_click = function() log.info("all_component", "图片被点击") end,
    })
    y_pos = y_pos + 120

    -- 11. 选项卡组件
    airui.label({
        parent = scroll_container,
        text = "11. 选项卡组件 (Tabview)",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    local demo_tabview = airui.tabview({
        parent = scroll_container,
        x = MARGIN + 10,
        y = y_pos + 30,
        w = 280,
        h = 150,
        tabs = { "标签1", "标签2" },
        active = 0,
    })
    local tab1 = demo_tabview:get_content(0)
    if tab1 then
        airui.label({
            parent = tab1,
            text = "标签1内容",
            x = 20,
            y = 20,
            w = 240,
            h = 30,
            font_size = 14,
        })
    end
    y_pos = y_pos + 190

    -- 12. 窗口组件
    airui.label({
        parent = scroll_container,
        text = "12. 窗口组件 (Window)",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    airui.button({
        parent = scroll_container,
        x = MARGIN + 10,
        y = y_pos + 30,
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
                auto_center = false,
            })
            -- 添加内容
            local label = airui.label({ text = "窗口内容演示", x = 20, y = 20, w = 160, h = 30, font_size = 14 })
            win:add_content(label)
            local btn = airui.button({
                text = "关闭",
                x = 60,
                y = 70,
                w = 80,
                h = 40,
                on_click = function() win:close() end
            })
            win:add_content(btn)
        end,
    })
    y_pos = y_pos + 80

    -- 组件总数显示
    airui.label({
        parent = scroll_container,
        text = "共展示12个AirUI组件",
        x = MARGIN,
        y = y_pos + 20,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    y_pos = y_pos + 40

    -- 交互提示
    airui.label({
        parent = scroll_container,
        text = "提示: 点击各个组件查看交互效果",
        x = MARGIN,
        y = y_pos,
        w = SCREEN_W - MARGIN * 2,
        h = 20,
        font_size = 14,
    })
    y_pos = y_pos + 30

    -- 底部信息（已在主容器底部，此处在滚动容器内不再重复）
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if update_timer then
        sys.timerStop(update_timer)
        update_timer = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
        scroll_container = nil
    end
    win_id = nil
    log.info("all_component_win", "窗口销毁")
end

local function on_get_focus()
    log.info("all_component_win", "窗口获得焦点")
end

local function on_lose_focus()
    log.info("all_component_win", "窗口失去焦点")
end

sys.subscribe("OPEN_ALL_COMPONENT_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("all_component_win", "窗口打开，ID:", win_id)
    end
end)
