--[[
@module spinner_page
@summary 加载指示器组件演示
@version 1.0
@date 2026.05.12
@author 江访
@usage
本文件演示airui.spinner组件的用法，展示旋转加载动画。
]]

local airui_spinner = {}

local main_container = nil

function airui_spinner.create_ui()
    main_container = airui.container({
        x = 0, y = 0, w = 1024, h = 600,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0, w = 1024, h = 60,
        color = 0x4CAF50,
    })

    airui.label({
        parent = title_bar,
        text = "加载指示器组件演示",
        x = 20, y = 15, w = 300, h = 30,
        size = 20,
    })

    -- 返回按钮
    airui.button({
        parent = title_bar,
        x = 900, y = 15, w = 100, h = 35,
        text = "返回",
        size = 16,
        on_click = function()
            go_back()
        end
    })

    -- 蓝色 spinner
    local spinner1 = airui.spinner({
        parent = main_container,
        x = 120, y = 120, w = 50, h = 50,
        duration = 1000, arc_angle = 200,
        style = { color = 0x00b4ff, track_color = 0xd0d0d0, line_width = 5, opa = 255 }
    })

    -- 橙色大号 spinner
    local spinner2 = airui.spinner({
        parent = main_container,
        x = 340, y = 100, w = 90, h = 90,
        duration = 800, arc_angle = 260,
        style = { color = 0xff7a00, track_color = 0x33261a, line_width = 7, opa = 255 }
    })

    -- 绿色 spinner
    local spinner3 = airui.spinner({
        parent = main_container,
        x = 560, y = 120, w = 50, h = 50,
        duration = 1500, arc_angle = 160,
        style = { color = 0x22c55e, track_color = 0x1a3522, line_width = 5, opa = 255 }
    })

    -- 紫色半透明 spinner
    local spinner4 = airui.spinner({
        parent = main_container,
        x = 780, y = 110, w = 70, h = 70,
        duration = 1200, arc_angle = 220,
        style = { color = 0xa855f7, track_color = 0x2a1a35, line_width = 5, opa = 180 }
    })

    -- 标签说明
    airui.label({
        parent = main_container,
        text = "蓝色默认  |  橙色大号  |  绿色慢速  |  紫色半透明",
        x = 0, y = 220, w = 1024, h = 30,
        size = 16,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 切换按钮
    airui.button({
        parent = main_container,
        x = 312, y = 340, w = 400, h = 45,
        text = "切换所有 Spinner 配色",
        on_click = function()
            spinner1:set_style({ color = 0xff3b30, track_color = 0x2a1515, line_width = 5, opa = 255 })
            spinner2:set_style({ color = 0x00b4ff, track_color = 0x1a2a35, line_width = 6, opa = 200 })
            spinner3:set_style({ color = 0xfbbf24, track_color = 0x2a2010, line_width = 5, opa = 255 })
            spinner4:set_style({ color = 0x22c55e, track_color = 0x1a3522, line_width = 5, opa = 200 })
            log.info("spinner", "配色已切换")
        end
    })

    -- 底部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0, y = 550, w = 1024, h = 50,
        color = 0xCFCFCF,
    })

    airui.label({
        parent = status_bar,
        text = "Spinner 加载指示器 — 点击按钮切换配色",
        x = 20, y = 15, w = 600, h = 20,
        size = 14,
    })
end

function airui_spinner.init(params)
    airui_spinner.create_ui()
end

function airui_spinner.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return airui_spinner
