-- tts_win.lua - TTS语音页面(Air1601版本，适配1024x600分辨率)

local win_id = nil
local main_container, content
local text_input, speak_btn

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 1024, h = 600, color = 0xF8F9FA, parent = airui.screen })

    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 1024, h = 60, color = 0x3F51B5 })
    local back_btn = airui.button({ parent = header, x = 924, y = 10, w = 80, h = 40, color = 0x2195F6, text = "返回", font_size = 30, text_color = 0xffffff,
        on_click = function() if win_id then exwin.close(win_id) win_id = nil end end
    })
    airui.label({ parent = header, x = 400, y = 10, w = 224, h = 40, text = "TTS语音", font_size = 32, color = 0xffffff, align = airui.TEXT_ALIGN_CENTER })

    content = airui.container({ parent = main_container, x = 0, y = 60, w = 1024, h = 540, color = 0xF3F4F6 })

    -- 文本输入
    text_input = airui.textarea({
        parent = content, x = 100, y = 100, w = 824, h = 200,
        placeholder = "请输入要朗读的文字"
    })

    -- 朗读按钮
    speak_btn = airui.button({
        parent = content, x = 450, y = 350, w = 150, h = 60,
        text = "朗读",
        on_click = function()
            local text = text_input:get_text()
            -- TODO: 调用TTS引擎朗读
            log.info("tts", "朗读", text)
        end
    })
end

local function on_create()
    win_id = create_ui()
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

sys.subscribe("OPEN_TTS_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({ 
            on_create = on_create, 
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus
        })
    end
end)
