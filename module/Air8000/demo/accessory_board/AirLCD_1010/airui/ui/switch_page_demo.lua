--[[
@module  switch_page_demo
@summary 页面切换演示
@version 1.0
@date    2026.02.05
@author  江访
@usage
本文件是页面切换的演示，展示多个子页面之间的切换。
]]

local switch_page_demo = {}
local tab_buttons = {}

-- 页面UI元素
local main_container = nil
local current_subpage = nil
local subpages = {}

local update_timer
local auto_update_timer

-- 创建UI
function switch_page_demo.create_ui()
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
        text = "页面切换演示",
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
            go_back()
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

    -- 子页面容器
    local content_container = airui.container({
        parent = main_container,
        x = 0,
        y = 120,
        w = 320,
        h = 280,
        color = 0xFFFFFF,
    })

    -- 创建子页面
    function switch_page_demo.create_subpages()
        -- 子页面1: 欢迎页面
        local page1 = airui.container({
            parent = content_container,
            x = 0,
            y = 0,
            w = 320,
            h = 280,
            color = 0xE3F2FD,
        })

        airui.label({
            parent = page1,
            text = "欢迎页面",
            x = 100,
            y = 50,
            w = 120,
            h = 40,
            font_size = 16,
        })

        airui.label({
            parent = page1,
            text = "这是第一个子页面",
            x = 60,
            y = 100,
            w = 200,
            h = 30,
            font_size = 14,
        })

        airui.label({
            parent = page1,
            text = "点击下方标签切换页面",
            x = 60,
            y = 140,
            w = 200,
            h = 30,
            font_size = 14,
        })

        -- 子页面2: 信息页面
        local page2 = airui.container({
            parent = content_container,
            x = 0,
            y = 0,
            w = 320,
            h = 280,
            color = 0xF1F8E9,
        })

        airui.label({
            parent = page2,
            text = "信息页面",
            x = 100,
            y = 50,
            w = 120,
            h = 40,
            font_size = 16,
        })

        airui.label({
            parent = page2,
            text = "系统信息:",
            x = 30,
            y = 100,
            w = 120,
            h = 30,
            font_size = 14,
        })

        airui.label({
            parent = page2,
            text = "当前时间: " .. os.date("%H:%M:%S"),
            x = 30,
            y = 140,
            w = 260,
            h = 20,
            font_size = 14,
        })

        airui.label({
            parent = page2,
            text = "页面演示系统",
            x = 30,
            y = 170,
            w = 260,
            h = 20,
            font_size = 14,
        })

        -- 子页面3: 设置页面
        local page3 = airui.container({
            parent = content_container,
            x = 0,
            y = 0,
            w = 320,
            h = 280,
            color = 0xFFF3E0,
        })

        airui.label({
            parent = page3,
            text = "设置页面",
            x = 100,
            y = 50,
            w = 120,
            h = 40,
            font_size = 16,
        })

        local setting1 = airui.switch({
            parent = page3,
            x = 30,
            y = 100,
            w = 60,
            h = 30,
            checked = true,
            on_change = function(self)
                log.info("switch_page", "设置1: " .. tostring(self:get_state()))
            end
        })

        airui.label({
            parent = page3,
            text = "启用通知",
            x = 100,
            y = 105,
            w = 100,
            h = 20,
            font_size = 14,
        })

        local setting2 = airui.switch({
            parent = page3,
            x = 30,
            y = 150,
            w = 60,
            h = 30,
            checked = false,
            on_change = function(self)
                log.info("switch_page", "设置2: " .. tostring(self:get_state()))
            end
        })

        airui.label({
            parent = page3,
            text = "自动更新",
            x = 100,
            y = 155,
            w = 100,
            h = 20,
            font_size = 14,
        })

        subpages = {
            { container = page1, name = "欢迎" },
            { container = page2, name = "信息" },
            { container = page3, name = "设置" }
        }

        current_subpage = 1
        for i, page in ipairs(subpages) do
            if i == 1 then
                page.container:open()
            else
                page.container:hide()
            end
        end
    end

    -- 创建选项卡按钮
    function switch_page_demo.create_tabs()
        local tab_width = 90
        local tab_height = 40
        local tab_margin = 10

        for i, page in ipairs(subpages) do
            local tab_x = tab_margin + (i - 1) * (tab_width + tab_margin)
            local tab = airui.button({
                parent = tab_container,
                x = tab_x,
                y = 5,
                w = tab_width,
                h = tab_height,
                text = page.name,
                on_click = function(self)
                    switch_page_demo.switch_to_page(i)
                end
            })

            tab_buttons[i] = tab

            if i == current_subpage then
                tab:set_text("- " .. page.name .. " -")
            end
        end
    end

    -- 切换页面函数
    function switch_page_demo.switch_to_page(page_index)
        if page_index == current_subpage then
            return
        end

        if current_subpage and subpages[current_subpage] then
            subpages[current_subpage].container:hide()
        end

        if subpages[page_index] then
            subpages[page_index].container:open()
            current_subpage = page_index

            for i, btn in ipairs(tab_buttons) do
                if i == page_index then
                    btn:set_text("- " .. subpages[i].name .. " -")
                else
                    btn:set_text(subpages[i].name)
                end
            end

            log.info("switch_page", "切换到页面: " .. subpages[page_index].name)
        end
    end

    switch_page_demo.create_subpages()
    switch_page_demo.create_tabs()

    -- 页面指示器
    local indicator_label = airui.label({
        parent = main_container,
        text = "当前页面: 欢迎",
        x = 10,
        y = 410,
        w = 200,
        h = 20,
        font_size = 14,
    })

    update_timer = sys.timerLoopStart(function()
        if current_subpage and subpages[current_subpage] then
            indicator_label:set_text("当前页面: " .. subpages[current_subpage].name)
        end
    end, 100)

    -- 手动切换按钮
    local prev_btn = airui.button({
        parent = main_container,
        x = 20,
        y = 445,
        w = 80,
        h = 35,
        text = "上一页",
        on_click = function(self)
            local new_index = current_subpage - 1
            if new_index < 1 then
                new_index = #subpages
            end
            switch_page_demo.switch_to_page(new_index)
        end
    })

    local next_btn = airui.button({
        parent = main_container,
        x = 120,
        y = 445,
        w = 80,
        h = 35,
        text = "下一页",
        on_click = function(self)
            local new_index = current_subpage + 1
            if new_index > #subpages then
                new_index = 1
            end
            switch_page_demo.switch_to_page(new_index)
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
                log.info("switch_page", "启用自动切换")
            else
                log.info("switch_page", "禁用自动切换")
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
            local new_index = current_subpage + 1
            if new_index > #subpages then
                new_index = 1
            end
            switch_page_demo.switch_to_page(new_index)
        end
    end, 5000) -- 5秒自动切换
end

-- 初始化页面
function switch_page_demo.init(params)
    current_subpage = 1
    subpages = {}
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
    tab_buttons = {}
end

return switch_page_demo