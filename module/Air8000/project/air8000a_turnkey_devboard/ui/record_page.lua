-- 录音页面
local record_page = {}

local main_container, content
local record_btn, play_btn

function record_page.create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn =  airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5,text = "返回",
        on_click = function() _G.go_back() end
    })
  
    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="录音", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

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

function record_page.init()
    record_page.create_ui()
end

function record_page.cleanup()
    if main_container then main_container:destroy(); main_container = nil end
end

return record_page