--[[
@module video_page
@summary 视频组件演示
@version 1.0
@date 2026.05.12
@author 江访
@usage
本文件演示airui.video组件的用法，展示MJPG格式视频播放功能。
]]

local airui_video = {}

local main_container = nil

function airui_video.create_ui()
    main_container = airui.container({
        x = 0, y = 0, w = 1024, h = 600,
        color = 0x000000,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0, w = 1024, h = 60,
        color = 0x333333,
    })

    airui.label({
        parent = title_bar,
        text = "视频组件演示",
        x = 20, y = 15, w = 300, h = 30,
        size = 20,
        color = 0xcccccc,
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

    -- 视频组件（居中）
    local video = airui.video({
        parent = main_container,
        x = 272, y = 85,
        w = 480, h = 320,
        src = "/luadb/fly_man.mjpg",
        format = "auto",
        backend = "auto",
        decode_mode = "hw",
        interval = 33,
        loop = true,
        auto_play = false,
    })

    if not video then
        log.error("video", "创建视频组件失败")
        airui.label({
            parent = main_container,
            text = "fly_man.mjpg 资源文件未找到",
            x = 0, y = 250, w = 1024, h = 30,
            size = 18,
            color = 0xff4444,
            align = airui.TEXT_ALIGN_CENTER,
        })
        return
    end

    -- 控制按钮
    airui.button({
        parent = main_container,
        x = 312, y = 430, w = 120, h = 40,
        text = "播放",
        on_click = function()
            video:play()
        end
    })

    airui.button({
        parent = main_container,
        x = 452, y = 430, w = 120, h = 40,
        text = "暂停",
        on_click = function()
            video:pause()
        end
    })

    airui.button({
        parent = main_container,
        x = 592, y = 430, w = 120, h = 40,
        text = "停止",
        on_click = function()
            video:stop()
        end
    })

    -- 底部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0, y = 550, w = 1024, h = 50,
        color = 0x222222,
    })

    airui.label({
        parent = status_bar,
        text = "fly_man.mjpg MJPG视频 — 480x320居中显示",
        x = 20, y = 15, w = 600, h = 20,
        size = 14,
        color = 0x888888,
    })
end

function airui_video.init(params)
    airui_video.create_ui()
end

function airui_video.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return airui_video
