--[[
@module video_page
@summary 视频组件演示
@version 1.0
@date 2026.05.12
@author 江访
@usage
本文件演示airui.video组件的用法，展示MJPG格式视频播放功能。
适用于320x480竖屏。
]]

local function ui_main()
    -- 初始化硬件

    -- 黑色背景容器
    local bg = airui.container({
        x = 0, y = 0, w = 320, h = 480,
        color = 0x000000,
    })

    -- 标题
    airui.label({
        parent = bg,
        text = "Video 视频播放",
        x = 0, y = 10, w = 320, h = 24,
        font_size = 18,
        color = 0xcccccc,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 创建视频组件
    local video = airui.video({
        parent = bg,
        x = 10, y = 45,
        w = 300, h = 225,
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
            text = "需要fly_man.mjpg资源文件",
            x = 0, y = 200, w = 320, h = 20,
            font_size = 14,
            color = 0xff4444,
            align = airui.TEXT_ALIGN_CENTER,
        })
        return
    end

    -- 提示
    airui.label({
        parent = bg,
        text = "需要fly_man.mjpg资源文件",
        x = 0, y = 285, w = 320, h = 15,
        font_size = 11,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 播放按钮
    airui.button({
        parent = bg,
        x = 15, y = 320, w = 85, h = 36,
        text = "播放",
        on_click = function()
            video:play()
        end
    })

    -- 暂停按钮
    airui.button({
        parent = bg,
        x = 117, y = 320, w = 85, h = 36,
        text = "暂停",
        on_click = function()
            video:pause()
        end
    })

    -- 停止按钮
    airui.button({
        parent = bg,
        x = 220, y = 320, w = 85, h = 36,
        text = "停止",
        on_click = function()
            video:stop()
        end
    })

end

sys.taskInit(ui_main)
