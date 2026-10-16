--[[
@module video_page
@summary 视频组件演示
@version 1.1
@date    2026.10.12
@author  江访
@usage
本文件演示airui.video组件的用法，支持MJPG、MP4、HZV三种格式视频切换播放：
1、MJPG：MJPEG序列，fly_man.mjpg示例资源随工程烧录；
2、MP4：H.264视频，无音频，需自行准备/luadb/fly_man.mp4；
3、HZV：HZV/HZMP4容器，支持音视频同步播放，需自行准备/luadb/fly_man.hzv。
]]

local airui_video = {}

local main_container = nil
local video = nil
local status_label = nil

-- 支持的视频格式列表
local VIDEO_FORMATS = {
    {name = "MJPG", src = "/luadb/fly_man.mjpg", format = "mjpg"},
    {name = "MP4",  src = "/luadb/fly_man.mp4",  format = "mp4"},
    {name = "HZV",  src = "/luadb/fly_man.hzv",  format = "hzv"},
}
local current_format = 1

-- 创建视频组件
local function create_video(fmt)
    video = airui.video({
        parent = main_container,
        x = 272, y = 85,
        w = 480, h = 320,
        src = fmt.src,
        format = fmt.format,
        backend = "auto",
        decode_mode = "hw",
        interval = 33,
        loop = true,
        auto_play = false,
    })

    if not video then
        log.error("video", "创建视频组件失败", fmt.src)
        airui.label({
            parent = main_container,
            text = fmt.src .. " 资源文件未找到",
            x = 0, y = 250, w = 1024, h = 30,
            size = 18,
            color = 0xff4444,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end
end

-- 销毁视频组件
local function destroy_video()
    if video then
        video:destroy()
        video = nil
    end
end

-- 切换视频格式
local function switch_format(index)
    destroy_video()
    current_format = index
    local fmt = VIDEO_FORMATS[index]
    create_video(fmt)
    if status_label then
        status_label:set_text(fmt.name .. "视频 — " .. fmt.src .. " — 480x320居中显示")
    end
    log.info("video", "switch format", fmt.name, fmt.src)
end

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

    -- 视频组件（居中），默认播放MJPG示例
    create_video(VIDEO_FORMATS[1])

    -- 格式切换按钮
    airui.button({
        parent = main_container,
        x = 272, y = 425, w = 120, h = 40,
        text = "MJPG",
        on_click = function()
            switch_format(1)
        end
    })

    airui.button({
        parent = main_container,
        x = 412, y = 425, w = 120, h = 40,
        text = "MP4",
        on_click = function()
            switch_format(2)
        end
    })

    airui.button({
        parent = main_container,
        x = 552, y = 425, w = 120, h = 40,
        text = "HZV",
        on_click = function()
            switch_format(3)
        end
    })

    -- 播放控制按钮
    airui.button({
        parent = main_container,
        x = 272, y = 475, w = 120, h = 40,
        text = "播放",
        on_click = function()
            if video then
                video:play()
            end
        end
    })

    airui.button({
        parent = main_container,
        x = 412, y = 475, w = 120, h = 40,
        text = "暂停",
        on_click = function()
            if video then
                video:pause()
            end
        end
    })

    airui.button({
        parent = main_container,
        x = 552, y = 475, w = 120, h = 40,
        text = "停止",
        on_click = function()
            if video then
                video:stop()
            end
        end
    })

    -- 底部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0, y = 550, w = 1024, h = 50,
        color = 0x222222,
    })

    status_label = airui.label({
        parent = status_bar,
        text = "MJPG视频 — /luadb/fly_man.mjpg — 480x320居中显示",
        x = 20, y = 15, w = 900, h = 20,
        size = 14,
        color = 0x888888,
    })
end

function airui_video.init(params)
    airui_video.create_ui()
end

function airui_video.cleanup()
    destroy_video()
    status_label = nil
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return airui_video
