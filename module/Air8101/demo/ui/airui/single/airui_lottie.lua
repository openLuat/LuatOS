--[[
@module  lottie_page
@summary Lottie动画组件演示
@version 1.0.0
@date    2026.10.12
@author  江访
@usage
本文件演示airui.lottie组件的用法，包括内联数据动画创建、播放控制、速率、循环、
进度设置、切换动画源和销毁重建。
1、默认使用内联JSON动画数据，开箱即用；
2、切换文件源需自行准备/luadb/anim.json动画文件。
]]

-- Lottie组件对象
local lottie_widget

-- 内联Lottie动画数据（圆形水平移动，300*200画布，60帧每秒，共180帧）
local LOTTIE_DATA = '{"v":"5.5.7","fr":60,"ip":0,"op":180,"w":300,"h":200,"nm":"demo","layers":[{"ty":4,"nm":"ball","ip":0,"op":180,"st":0,"ks":{"o":{"a":0,"k":100},"r":{"a":0,"k":0},"p":{"a":1,"k":[{"i":{"x":0.5,"y":1},"o":{"x":0.5,"y":0},"t":0,"s":[50,100,0]},{"t":180,"s":[250,100,0]}]},"a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]}},"shapes":[{"ty":"el","p":{"a":0,"k":[0,0]},"s":{"a":0,"k":[60,60]}},{"ty":"fl","c":{"a":0,"k":[0.2,0.6,1,1]},"o":{"a":0,"k":100}}]}]}'

-- 创建Lottie动画组件
local function create_lottie()
    lottie_widget = airui.lottie({
        data = LOTTIE_DATA,         -- 内联Lottie动画JSON数据
        x = 250, y = 20, w = 300, h = 200,
        loop = true,                -- 循环播放
        auto_play = true,           -- 创建后自动播放
        speed = 1.0,                -- 播放速率
        on_ready = function()
            log.info("lottie", "动画加载完成")
        end,
        on_complete = function()
            log.info("lottie", "动画播放完成")
        end,
    })
    if not lottie_widget then
        log.error("lottie", "创建 Lottie 组件失败")
        return
    end
    log.info("airui", "lottie created")
end

-- 销毁Lottie动画组件
local function destroy_lottie()
    if lottie_widget then
        lottie_widget:destroy()
        lottie_widget = nil
        log.info("airui", "lottie destroyed")
    end
end

local function ui_main()
    -- ========== 创建 Lottie 动画组件（内联数据） ==========
    create_lottie()

    -- ========== 播放控制 ==========
    airui.button({
        text = "播放",
        x = 20, y = 240, w = 120, h = 45,
        size = 16,
        on_click = function()
            if lottie_widget and not lottie_widget:is_destroyed() then
                lottie_widget:play()
            end
        end
    })
    airui.button({
        text = "暂停",
        x = 155, y = 240, w = 120, h = 45,
        size = 16,
        on_click = function()
            if lottie_widget and not lottie_widget:is_destroyed() then
                lottie_widget:pause()
            end
        end
    })
    airui.button({
        text = "停止",
        x = 290, y = 240, w = 120, h = 45,
        size = 16,
        on_click = function()
            if lottie_widget and not lottie_widget:is_destroyed() then
                lottie_widget:stop()
            end
        end
    })

    -- 2倍速播放
    airui.button({
        text = "2倍速",
        x = 425, y = 240, w = 120, h = 45,
        size = 16,
        on_click = function()
            if lottie_widget and not lottie_widget:is_destroyed() then
                lottie_widget:set_speed(2.0)
                log.info("lottie", "speed 2.0")
            end
        end
    })

    -- 恢复1倍速
    airui.button({
        text = "1倍速",
        x = 560, y = 240, w = 120, h = 45,
        size = 16,
        on_click = function()
            if lottie_widget and not lottie_widget:is_destroyed() then
                lottie_widget:set_speed(1.0)
                log.info("lottie", "speed 1.0")
            end
        end
    })

    -- ========== 进度与循环 ==========
    -- 跳到一半进度
    airui.button({
        text = "进度50%",
        x = 20, y = 300, w = 120, h = 45,
        size = 16,
        on_click = function()
            if lottie_widget and not lottie_widget:is_destroyed() then
                lottie_widget:set_progress(0.5)
                log.info("lottie", "progress 0.5")
            end
        end
    })

    -- 跳到结尾进度
    airui.button({
        text = "进度100%",
        x = 155, y = 300, w = 120, h = 45,
        size = 16,
        on_click = function()
            if lottie_widget and not lottie_widget:is_destroyed() then
                lottie_widget:set_progress(1.0)
                log.info("lottie", "progress 1.0")
            end
        end
    })

    -- 切换循环播放开关
    local loop_enabled = true
    airui.button({
        text = "循环开关",
        x = 290, y = 300, w = 120, h = 45,
        size = 16,
        on_click = function()
            if lottie_widget and not lottie_widget:is_destroyed() then
                loop_enabled = not loop_enabled
                lottie_widget:set_loop(loop_enabled)
                log.info("lottie", "loop", loop_enabled)
            end
        end
    })

    -- ========== 动画源切换与生命周期 ==========
    -- 切换到文件动画源
    airui.button({
        text = "文件源",
        x = 425, y = 300, w = 120, h = 45,
        size = 16,
        on_click = function()
            if lottie_widget and not lottie_widget:is_destroyed() then
                lottie_widget:set_src("/luadb/anim.json")
                lottie_widget:play()
                log.info("lottie", "switch to file source")
            end
        end
    })

    -- 销毁Lottie组件
    airui.button({
        text = "销毁组件",
        x = 560, y = 300, w = 120, h = 45,
        size = 16,
        on_click = function()
            destroy_lottie()
        end
    })

    -- 重建Lottie组件，演示先销毁再创建的切换流程
    airui.button({
        text = "重建组件",
        x = 290, y = 360, w = 120, h = 45,
        size = 16,
        on_click = function()
            destroy_lottie()
            create_lottie()
        end
    })

    -- 底部提示
    airui.label({
        text = "提示: 默认内联动画开箱即用，文件源需准备/luadb/anim.json",
        x = 10, y = 440, w = 780, h = 25,
        size = 14,
    })
end

sys.taskInit(ui_main)
