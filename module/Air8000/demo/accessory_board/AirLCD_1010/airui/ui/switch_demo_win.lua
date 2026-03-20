--[[
@module  switch_demo_win
@summary 窗口切换演示
@version 1.1.0
@date    2026.03.17
@author  江访
@usage
本文件是窗口切换的演示，采用exwin窗口管理扩展库。
展示多个子窗口之间的切换，通过消息机制打开和关闭。
]]

-- 窗口ID
local win_id = nil

-- 窗口UI元素
local main_container = nil
local current_subwin = nil
local subwins = {}
local tab_buttons = {}

local update_timer
local auto_update_timer

-- 创建UI
local function create_ui()
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
        color = 0x673AB7,
    })

    airui.label({
        parent = title_bar,
        text = "窗口切换演示",
        x = 10,
        y = 15,
        w = 200,
        h = 20,
        font_size = 16,
        color = 0xFFFFFF,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 250,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function(self)
            exwin.close(win_id)
        end
    })

    -- 选项卡容器
    local tab_container = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 50,
        color = 0xEDE7F6,
    })

    -- 子窗口容器
    local content_container = airui.container({
        parent = main_container,
        x = 0,
        y = 120,
        w = 320,
        h = 280,
        color = 0xFFFFFF,
    })

    -- 创建子窗口
    local function create_subwins()
        -- 子窗口1: 欢迎窗口
        local win1 = airui.container({
            parent = content_container,
            x = 0,
            y = 0,
            w = 320,
            h = 280,
            color = 0xE3F2FD,
        })

        airui.label({
            parent = win1,
            text = "欢迎窗口",
            x = 100,
            y = 50,
            w = 120,
            h = 40,
            font_size = 16,
        })

        airui.label({
            parent = win1,
            text = "这是第一个子窗口",
            x = 60,
            y = 100,
            w = 200,
            h = 30,
            font_size = 14,
        })

        airui.label({
            parent = win1,
            text = "点击下方标签切换窗口",
            x = 60,
            y = 140,
            w = 200,
            h = 30,
            font_size = 14,
        })

        -- 子窗口2: 信息窗口
        local win2 = airui.container({
            parent = content_container,
            x = 0,
            y = 0,
            w = 320,
            h = 280,
            color = 0xF1F8E9,
        })

        airui.label({
            parent = win2,
            text = "信息窗口",
            x = 100,
            y = 50,
            w = 120,
            h = 40,
            font_size = 16,
        })

        airui.label({
            parent = win2,
            text = "系统信息:",
            x = 30,
            y = 100,
            w = 120,
            h = 30,
            font_size = 14,
        })

        airui.label({
            parent = win2,
            text = "当前时间: " .. os.date("%H:%M:%S"),
            x = 30,
            y = 140,
            w = 260,
            h = 20,
            font_size = 14,
        })

        airui.label({
            parent = win2,
            text = "窗口演示系统",
            x = 30,
            y = 170,
            w = 260,
            h = 20,
            font_size = 14,
        })

        -- 子窗口3: 设置窗口
        local win3 = airui.container({
            parent = content_container,
            x = 0,
            y = 0,
            w = 320,
            h = 280,
            color = 0xFFF3E0,
        })

        airui.label({
            parent = win3,
            text = "设置窗口",
            x = 100,
            y = 50,
            w = 120,
            h = 40,
            font_size = 16,
        })

        local setting1 = airui.switch({
            parent = win3,
            x = 30,
            y = 100,
            w = 60,
            h = 30,
            checked = true,
            on_change = function(self)
                log.info("switch_win", "设置1: " .. tostring(self:get_state()))
            end
        })

        airui.label({
            parent = win3,
            text = "启用通知",
            x = 100,
            y = 105,
            w = 100,
            h = 20,
            font_size = 14,
        })

        local setting2 = airui.switch({
            parent = win3,
            x = 30,
            y = 150,
            w = 60,
            h = 30,
            checked = false,
            on_change = function(self)
                log.info("switch_win", "设置2: " .. tostring(self:get_state()))
            end
        })

        airui.label({
            parent = win3,
            text = "自动更新",
            x = 100,
            y = 155,
            w = 100,
            h = 20,
            font_size = 14,
        })

        subwins = {
            { container = win1, name = "欢迎" },
            { container = win2, name = "信息" },
            { container = win3, name = "设置" }
        }

        current_subwin = 1
        for i, win in ipairs(subwins) do
            if i == 1 then
                win.container:open()
            else
                win.container:hide()
            end
        end
    end

    -- 创建选项卡按钮
    local function create_tabs()
        local tab_width = 90
        local tab_height = 40
        local tab_margin = 10

        for i, win in ipairs(subwins) do
            local tab_x = tab_margin + (i - 1) * (tab_width + tab_margin)
            local tab = airui.button({
                parent = tab_container,
                x = tab_x,
                y = 5,
                w = tab_width,
                h = tab_height,
                text = win.name,
                on_click = function(self)
                    switch_to_win(i)
                end
            })

            tab_buttons[i] = tab

            if i == current_subwin then
                tab:set_text("- " .. win.name .. " -")
            end
        end
    end

    -- 切换窗口函数
    local function switch_to_win(win_index)
        if win_index == current_subwin then
            return
        end

        if current_subwin and subwins[current_subwin] then
            subwins[current_subwin].container:hide()
        end

        if subwins[win_index] then
            subwins[win_index].container:open()
            current_subwin = win_index

            for i, btn in ipairs(tab_buttons) do
                if i == win_index then
                    btn:set_text("- " .. subwins[i].name .. " -")
                else
                    btn:set_text(subwins[i].name)
                end
            end

            log.info("switch_win", "切换到窗口: " .. subwins[win_index].name)
        end
    end

    create_subwins()
    create_tabs()

    -- 窗口指示器
    local indicator_label = airui.label({
        parent = main_container,
        text = "当前窗口: 欢迎",
        x = 10,
        y = 410,
        w = 200,
        h = 20,
        font_size = 14,
    })

    update_timer = sys.timerLoopStart(function()
        if current_subwin and subwins[current_subwin] then
            indicator_label:set_text("当前窗口: " .. subwins[current_subwin].name)
        end
    end, 100)

    -- 手动切换按钮
    local prev_btn = airui.button({
        parent = main_container,
        x = 20,
        y = 445,
        w = 80,
        h = 35,
        text = "上一窗口",
        on_click = function(self)
            local new_index = current_subwin - 1
            if new_index < 1 then
                new_index = #subwins
            end
            switch_to_win(new_index)
        end
    })

    local next_btn = airui.button({
        parent = main_container,
        x = 120,
        y = 445,
        w = 80,
        h = 35,
        text = "下一窗口",
        on_click = function(self)
            local new_index = current_subwin + 1
            if new_index > #subwins then
                new_index = 1
            end
            switch_to_win(new_index)
        end
    })

    -- 自动切换开关
    local auto_switch = airui.switch({
        parent = main_container,
        x = 220,
        y = 445,
        w = 50,
        h = 30,
        checked = false,
        on_change = function(self)
            if self:get_state() then
                log.info("switch_win", "启用自动切换")
            else
                log.info("switch_win", "禁用自动切换")
            end
        end
    })

    airui.label({
        parent = main_container,
        text = "自动",
        x = 275,
        y = 450,
        w = 40,
        h = 20,
        font_size = 14,
    })

    auto_update_timer = sys.timerLoopStart(function()
        if auto_switch:get_state() then
            local new_index = current_subwin + 1
            if new_index > #subwins then
                new_index = 1
            end
            switch_to_win(new_index)
        end
    end, 5000) -- 5秒自动切换
end

-- 窗口创建回调
local function on_create()
    current_subwin = 1
    subwins = {}
    create_ui()
end

-- 窗口销毁回调
local function on_destroy()
    sys.timerStop(update_timer)
    sys.timerStop(auto_update_timer)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    current_subwin = nil
    subwins = {}
    tab_buttons = {}
    win_id = nil
    log.info("switch_demo_win", "窗口销毁")
end

-- 窗口获得焦点回调
local function on_get_focus()
    log.info("switch_demo_win", "窗口获得焦点")
end

-- 窗口失去焦点回调
local function on_lose_focus()
    log.info("switch_demo_win", "窗口失去焦点")
end

-- 订阅打开窗口切换演示消息
sys.subscribe("OPEN_SWITCH_DEMO_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("switch_demo_win", "窗口打开，ID:", win_id)
    end
end)