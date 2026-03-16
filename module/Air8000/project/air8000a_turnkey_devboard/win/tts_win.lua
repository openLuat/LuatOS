-- TTS页面

local win_id = nil
local main_container, content
local text_input, speak_btn

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=40, color=0x3F51B5 })
    -- 返回按钮使用容器样式，与历史页面保持一致
    local back_btn = airui.container({ parent = header, x = 400, y = 5, w = 70, h = 30, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 5, w = 50, h = 20, text = "返回", font_size = 16, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 4, w = 360, h = 32, align = airui.TEXT_ALIGN_CENTER, text="TTS", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=40, w=480, h=280, color=0xF3F4F6 })

    -- 文本输入
    text_input = airui.textarea({
        parent = content, x=40, y=50, w=400, h=100,
        placeholder = "请输入要朗读的文字"
    })

    -- 朗读按钮
    speak_btn = airui.button({
        parent = content, x=190, y=170, w=100, h=40,
        text = "朗读",
        on_click = function()
            local text = text_input:get_text()
            -- TODO: 调用TTS引擎朗读
            log.info("tts", "朗读", text)
        end
    })
end

local function on_create()
    
    create_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
    -- 停止播放等
end

local function on_get_focus()
    -- 刷新
end

local function on_lose_focus()
    -- 如果正在朗读，可暂停
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_TTS_WIN", open_handler)