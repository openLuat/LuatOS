--[[
@module  switch_page_demo
@summary 页面切换演示
@version 1.0.0
@date    2026.01.30
@author  江访
@usage
本文件是页面切换的演示，展示多个子页面之间的切换。
]]

local switch_page_demo = {}
local tab_buttons = {} -- 存储选项卡按钮的引用

-- 页面UI元素
local main_container = nil
local current_subpage = nil
local subpages = {}

local update_timer
local auto_update_timer

-- 创建UI
function switch_page_demo.create_ui()
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
        color = 0x673AB7,
    })

    airui.label({
        parent = title_bar,
        text = "页面切换演示",
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

    -- 选项卡容器
    local tab_container = airui.container({
        parent = main_container,
        x = 0,
        y = 70,
        w = 1024,
        h = 50,
        color = 0xEDE7F6,
    })

    -- 子页面容器
    local content_container = airui.container({
        parent = main_container,
        x = 20,
        y = 130,
        w = 984,
        h = 400,
        color = 0xFFFFFF,
        radius = 12,
    })

    -- 创建子页面
    function switch_page_demo.create_subpages()
        -- 子页面1: 欢迎页面
        local page1 = airui.container({
            parent = content_container,
            x = 0,
            y = 0,
            w = 984,
            h = 400,
            color = 0xE3F2FD,
        })

        airui.label({
            parent = page1,
            text = "欢迎页面",
            x = 400,
            y = 80,
            w = 184,
            h = 60,
            size = 24,
        })

        airui.label({
            parent = page1,
            text = "这是第一个子页面 - 欢迎使用页面切换演示",
            x = 200,
            y = 160,
            w = 584,
            h = 40,
            size = 18,
        })

        airui.label({
            parent = page1,
            text = "点击下方标签或使用导航按钮在不同页面间切换",
            x = 200,
            y = 210,
            w = 584,
            h = 30,
            size = 16,
        })

        airui.label({
            parent = page1,
            text = "页面切换是构建复杂应用的基础功能",
            x = 200,
            y = 250,
            w = 584,
            h = 30,
            size = 16,
        })

        -- 子页面2: 信息页面
        local page2 = airui.container({
            parent = content_container,
            x = 0,
            y = 0,
            w = 984,
            h = 400,
            color = 0xF1F8E9,
        })

        airui.label({
            parent = page2,
            text = "信息页面",
            x = 400,
            y = 80,
            w = 184,
            h = 60,
            size = 24,
        })

        airui.label({
            parent = page2,
            text = "系统信息:",
            x = 100,
            y = 160,
            w = 200,
            h = 40,
            size = 18,
        })

        local time_label = airui.label({
            parent = page2,
            text = "当前时间: " .. os.date("%H:%M:%S"),
            x = 100,
            y = 210,
            w = 400,
            h = 30,
            size = 16,
        })

        airui.label({
            parent = page2,
            text = "页面演示系统 v1.0",
            x = 100,
            y = 250,
            w = 400,
            h = 30,
            size = 16,
        })

        airui.label({
            parent = page2,
            text = "分辨率: 1024×600",
            x = 100,
            y = 290,
            w = 400,
            h = 30,
            size = 16,
        })

        -- 更新时间
        sys.timerLoopStart(function()
            time_label:set_text("当前时间: " .. os.date("%H:%M:%S"))
        end, 1000)

        -- 子页面3: 设置页面
        local page3 = airui.container({
            parent = content_container,
            x = 0,
            y = 0,
            w = 984,
            h = 400,
            color = 0xFFF3E0,
        })

        airui.label({
            parent = page3,
            text = "设置页面",
            x = 400,
            y = 80,
            w = 184,
            h = 60,
            size = 24,
        })

        airui.label({
            parent = page3,
            text = "系统设置选项:",
            x = 100,
            y = 160,
            w = 300,
            h = 40,
            size = 18,
        })

        local setting1 = airui.switch({
            parent = page3,
            x = 100,
            y = 210,
            w = 80,
            h = 40,
            checked = true,
            on_change = function(state)
                log.info("switch_page", "启用通知: " .. tostring(state))
            end
        })

        airui.label({
            parent = page3,
            text = "启用通知",
            x = 200,
            y = 220,
            w = 200,
            h = 20,
            size = 16,
        })

        local setting2 = airui.switch({
            parent = page3,
            x = 100,
            y = 270,
            w = 80,
            h = 40,
            checked = false,
            on_change = function(state)
                log.info("switch_page", "自动更新: " .. tostring(state))
            end
        })

        airui.label({
            parent = page3,
            text = "自动更新",
            x = 200,
            y = 280,
            w = 200,
            h = 20,
            size = 16,
        })

        local setting3 = airui.switch({
            parent = page3,
            x = 100,
            y = 330,
            w = 80,
            h = 40,
            checked = true,
            on_change = function(state)
                log.info("switch_page", "深色模式: " .. tostring(state))
            end
        })

        airui.label({
            parent = page3,
            text = "深色模式",
            x = 200,
            y = 340,
            w = 200,
            h = 20,
            size = 16,
        })

        -- 子页面4: 关于页面
        local page4 = airui.container({
            parent = content_container,
            x = 0,
            y = 0,
            w = 984,
            h = 400,
            color = 0xF3E5F5,
        })

        airui.label({
            parent = page4,
            text = "关于页面",
            x = 400,
            y = 80,
            w = 184,
            h = 60,
            size = 24,
        })

        airui.label({
            parent = page4,
            text = "页面切换演示系统",
            x = 300,
            y = 160,
            w = 384,
            h = 40,
            size = 20,
        })

        airui.label({
            parent = page4,
            text = "版本: 1.0.0",
            x = 300,
            y = 210,
            w = 384,
            h = 30,
            size = 16,
        })

        airui.label({
            parent = page4,
            text = "作者: 江访",
            x = 300,
            y = 250,
            w = 384,
            h = 30,
            size = 16,
        })

        airui.label({
            parent = page4,
            text = "日期: 2026.01.30",
            x = 300,
            y = 290,
            w = 384,
            h = 30,
            size = 16,
        })

        airui.label({
            parent = page4,
            text = "这是一个展示页面切换功能的演示",
            x = 300,
            y = 330,
            w = 384,
            h = 30,
            size = 16,
        })

        -- 存储子页面
        subpages = {
            { container = page1, name = "欢迎" },
            { container = page2, name = "信息" },
            { container = page3, name = "设置" },
            { container = page4, name = "关于" }
        }

        -- 默认显示第一个页面
        current_subpage = 1
        for i, page in ipairs(subpages) do
            if i == 1 then
                page.container:show()
            else
                page.container:hide()
            end
        end
    end

    -- 创建选项卡按钮
    function switch_page_demo.create_tabs()
        local tab_width = 150
        local tab_height = 40
        local tab_margin = 10
        local total_tabs = #subpages
        local total_width = total_tabs * tab_width + (total_tabs - 1) * tab_margin
        local start_x = (1024 - total_width) / 2

        for i, page in ipairs(subpages) do
            local tab_x = start_x + (i - 1) * (tab_width + tab_margin)
            local tab = airui.button({
                parent = tab_container,
                x = tab_x,
                y = 5,
                w = tab_width,
                h = tab_height,
                text = page.name,
                size = 16,
                on_click = function()
                    switch_page_demo.switch_to_page(i)
                end
            })

            -- 存储按钮引用到 tab_buttons 表中
            tab_buttons[i] = tab

            -- 设置当前页面的按钮样式（通过文字颜色区分）
            if i == current_subpage then
                tab:set_text("▶ " .. page.name .. " ◀")
                tab:set_color(0x673AB7)
            end
        end
    end

    -- 切换页面函数
    function switch_page_demo.switch_to_page(page_index)
        if page_index == current_subpage then
            return
        end

        -- 隐藏当前页面
        if current_subpage and subpages[current_subpage] then
            subpages[current_subpage].container:hide()
        end

        -- 显示新页面
        if subpages[page_index] then
            subpages[page_index].container:show()
            current_subpage = page_index

            -- 更新选项卡按钮文字（使用存储的按钮引用）
            for i, btn in ipairs(tab_buttons) do
                if i == page_index then
                    btn:set_text("▶ " .. subpages[i].name .. " ◀")
                    btn:set_color(0x673AB7)
                else
                    btn:set_text(subpages[i].name)
                    btn:set_color(nil) -- 恢复默认颜色
                end
            end

            log.info("switch_page", "切换到页面: " .. subpages[page_index].name)
        end
    end

    -- 创建子页面和选项卡
    switch_page_demo.create_subpages()
    switch_page_demo.create_tabs()

    -- 页面指示器
    local indicator_label = airui.label({
        parent = main_container,
        text = "当前页面: 欢迎",
        x = 20,
        y = 540,
        w = 300,
        h = 30,
        size = 16,
    })

    -- 更新指示器
    update_timer = sys.timerLoopStart(function()
        if current_subpage and subpages[current_subpage] then
            indicator_label:set_text("当前页面: " .. subpages[current_subpage].name)
        end
    end, 100)

    -- 导航控制区域
    local nav_container = airui.container({
        parent = main_container,
        x = 350,
        y = 540,
        w = 324,
        h = 50,
        color = 0xEDE7F6,
        radius = 8,
    })

    -- 手动切换按钮
    local prev_btn = airui.button({
        parent = nav_container,
        x = 10,
        y = 5,
        w = 100,
        h = 40,
        text = "◀ 上一页",
        size = 14,
        on_click = function()
            local new_index = current_subpage - 1
            if new_index < 1 then
                new_index = #subpages
            end
            switch_page_demo.switch_to_page(new_index)
        end
    })

    local next_btn = airui.button({
        parent = nav_container,
        x = 214,
        y = 5,
        w = 100,
        h = 40,
        text = "下一页 ▶",
        size = 14,
        on_click = function()
            local new_index = current_subpage + 1
            if new_index > #subpages then
                new_index = 1
            end
            switch_page_demo.switch_to_page(new_index)
        end
    })

    -- 当前页显示
    local page_info = airui.label({
        parent = nav_container,
        text = "1/" .. #subpages,
        x = 120,
        y = 10,
        w = 84,
        h = 30,
        size = 16,
    })

    -- 更新页码显示
    sys.timerLoopStart(function()
        if current_subpage then
            page_info:set_text(current_subpage .. "/" .. #subpages)
        end
    end, 100)

    -- 自动切换控制区域
    local auto_container = airui.container({
        parent = main_container,
        x = 700,
        y = 540,
        w = 304,
        h = 50,
        color = 0xE8F5E9,
        radius = 8,
    })

    -- 自动切换开关
    local auto_switch = airui.switch({
        parent = auto_container,
        x = 10,
        y = 10,
        w = 60,
        h = 30,
        checked = false,
        on_change = function(state)
            if state then
                log.info("switch_page", "启用自动切换")
            else
                log.info("switch_page", "禁用自动切换")
            end
        end
    })

    airui.label({
        parent = auto_container,
        text = "自动切换",
        x = 80,
        y = 15,
        w = 80,
        h = 20,
        size = 14,
    })

    -- 自动切换定时器
    local auto_counter = 0

    -- 更新自动切换
    auto_update_timer = sys.timerLoopStart(function()
        local state = auto_switch:get_state()
        if state then
            auto_counter = auto_counter + 1
            if auto_counter >= 5 then -- 5秒切换一次
                auto_counter = 0
                local new_index = current_subpage + 1
                if new_index > #subpages then
                    new_index = 1
                end
                switch_page_demo.switch_to_page(new_index)
            end
        else
            auto_counter = 0
        end
    end, 1000)

    -- 间隔时间显示
    local interval_label = airui.label({
        parent = auto_container,
        text = "间隔: 5秒",
        x = 170,
        y = 15,
        w = 120,
        h = 20,
        size = 14,
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 使用标签或导航按钮在不同页面间切换，支持自动切换功能",
        x = 20,
        y = 570,
        w = 600,
        h = 25,
        size = 14,
    })
end

-- 初始化页面
function switch_page_demo.init(params)
    current_subpage = 1
    subpages = {}
    tab_buttons = {}
    switch_page_demo.create_ui()
end

-- 清理页面
function switch_page_demo.cleanup()
    sys.timerStop(update_timer)
    sys.timerStop(auto_update_timer)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    current_subpage = nil
    subpages = {}
    tab_buttons = {} -- 清空按钮引用
end

return switch_page_demo