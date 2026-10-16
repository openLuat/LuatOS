--[[
@module animimg_page
@summary 动画图像组件演示
@version 1.0
@date 2026.05.12
@author 江访
@usage
本文件演示airui.animimg组件的用法，展示多帧动画图像播放功能。
]]

local airui_animimg = {}

local main_container = nil

function airui_animimg.create_ui()
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
        text = "动画图像组件演示",
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

    -- 动画帧列表
    local frames = {
        "/luadb/fly_man_01.png",
        "/luadb/fly_man_02.png",
        "/luadb/fly_man_03.png",
        "/luadb/fly_man_04.png",
        "/luadb/fly_man_05.png",
        "/luadb/fly_man_06.png",
        "/luadb/fly_man_07.png",
        "/luadb/fly_man_08.png",
    }

    -- 动画图像（居中，350x350）
    local anim = airui.animimg({
        parent = main_container,
        x = 337, y = 85,
        w = 350, h = 350,
        frames = frames,
        duration = 1600,
        loop = true,
        auto_play = true,
        on_complete = function()
            log.info("animimg", "一轮播放完成")
        end
    })

    -- 控制按钮
    airui.button({
        parent = main_container,
        x = 260, y = 460, w = 120, h = 40,
        text = "播放",
        on_click = function()
            anim:play()
        end
    })

    airui.button({
        parent = main_container,
        x = 452, y = 460, w = 120, h = 40,
        text = "暂停",
        on_click = function()
            anim:pause()
        end
    })

    airui.button({
        parent = main_container,
        x = 644, y = 460, w = 120, h = 40,
        text = "停止",
        on_click = function()
            anim:stop()
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
        text = "fly_man_01~08.png 350x350 8帧循环",
        x = 20, y = 15, w = 600, h = 20,
        size = 14,
    })
end

function airui_animimg.init(params)
    airui_animimg.create_ui()
end

function airui_animimg.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return airui_animimg
