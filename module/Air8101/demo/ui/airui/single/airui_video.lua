--[[
@module video_page
@summary 视频组件演示
@version 1.0
@date 2026.05.12
@author 江访
@usage
本文件演示airui.video组件的用法，展示MJPG格式视频播放功能。
]]

local function ui_main()
    -- 初始化硬件

    -- 黑色背景容器
    local bg = airui.container({
        x = 0, y = 0, w = 800, h = 480,
        color = 0x000000,
    })

    -- 标题
    airui.label({
        parent = bg,
        text = "Video 视频播放演示",
        x = 0, y = 15, w = 800, h = 30,
        font_size = 24,
        color = 0xcccccc,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 创建视频组件
    local video = airui.video({
        parent = bg,
        x = 160, y = 60,
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
            parent = bg,
            text = "视频创建失败，请检查mjpg文件",
            x = 0, y = 220, w = 800, h = 30,
            font_size = 18,
            color = 0xff4444,
            align = airui.TEXT_ALIGN_CENTER,
        })
        return
    end

    -- 播放按钮
    airui.button({
        parent = bg,
        x = 200, y = 410, w = 100, h = 40,
        text = "播放",
        on_click = function()
            video:play()
            log.info("video", "播放")
        end
    })

    -- 暂停按钮
    airui.button({
        parent = bg,
        x = 350, y = 410, w = 100, h = 40,
        text = "暂停",
        on_click = function()
            video:pause()
            log.info("video", "暂停")
        end
    })

    -- 停止按钮
    airui.button({
        parent = bg,
        x = 500, y = 410, w = 100, h = 40,
        text = "停止",
        on_click = function()
            video:stop()
            log.info("video", "停止")
        end
    })

end

sys.taskInit(ui_main)
