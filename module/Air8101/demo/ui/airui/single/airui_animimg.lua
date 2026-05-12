--[[
@module animimg_page
@summary 动画图像组件演示
@version 1.0
@date 2026.05.12
@author 江访
@usage
本文件演示airui.animimg组件的用法，展示多帧动画图像播放功能。
]]

local function ui_main()
    -- 初始化硬件

    -- 创建动画帧列表
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

    -- 标题
    airui.label({
        text = "动画图像演示",
        x = 0, y = 10, w = 800, h = 30,
        font_size = 24,
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 创建动画图像组件（居中显示）
    local anim = airui.animimg({
        x = 225,
        y = 55,
        w = 350,
        h = 350,
        frames = frames,
        duration = 1600,      -- 8帧，每帧约200ms
        loop = true,           -- 循环播放
        auto_play = true,      -- 自动播放
        on_complete = function()
            log.info("animimg", "一轮播放完成")
        end
    })

    -- 播放按钮
    airui.button({
        x = 220, y = 430, w = 100, h = 40,
        text = "播放",
        on_click = function()
            anim:play()
        end
    })

    -- 暂停按钮
    airui.button({
        x = 350, y = 430, w = 100, h = 40,
        text = "暂停",
        on_click = function()
            anim:pause()
        end
    })

    -- 停止按钮
    airui.button({
        x = 480, y = 430, w = 100, h = 40,
        text = "停止",
        on_click = function()
            anim:stop()
        end
    })

end

sys.taskInit(ui_main)
