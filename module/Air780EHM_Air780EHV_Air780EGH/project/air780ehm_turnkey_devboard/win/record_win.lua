--[[
@module  record_win
@summary 录音页面模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为录音功能页面，提供开始/停止录音和播放录音的按钮。
订阅"OPEN_RECORD_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, content
local record_btn, play_btn

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建全屏容器、标题栏、返回按钮、录音按钮和播放按钮
]]
local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=40, color=0x3F51B5 })
    -- 返回按钮使用容器样式，与历史页面保持一致
    local back_btn = airui.container({ parent = header, x = 400, y = 5, w = 70, h = 30, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 5, w = 50, h = 20, text = "返回", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 4, w = 360, h = 32, align = airui.TEXT_ALIGN_CENTER, text="录音", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=40, w=480, h=280, color=0xF3F4F6 })

    -- 录音按钮
    record_btn = airui.button({
        parent = content, x=190, y=80, w=100, h=50,
        text = "开始录音",
        on_click = function(self)
            if self:get_text() == "开始录音" then
                self:set_text("停止录音")
                -- TODO: 开始录音
                log.info("record", "开始")
            else
                self:set_text("开始录音")
                -- TODO: 停止录音并保存
                log.info("record", "停止")
            end
        end
    })

    -- 播放按钮
    play_btn = airui.button({
        parent = content, x=190, y=150, w=100, h=40,
        text = "播放",
        on_click = function()
            -- TODO: 播放最后录制的音频
            log.info("record", "播放")
        end
    })
end

--[[
窗口创建回调

@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI
]]
local function on_create()
    
    create_ui()
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
@usage
-- 窗口关闭时调用，销毁容器，停止录音/播放
]]
local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
    -- 停止录音、播放等
end

-- 窗口获得焦点回调（空实现）
local function on_get_focus()
    -- 刷新
end

-- 窗口失去焦点回调（空实现）
local function on_lose_focus()
    -- 如果正在录音，可考虑停止或暂停
end

-- 订阅打开录音页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_RECORD_WIN", open_handler)