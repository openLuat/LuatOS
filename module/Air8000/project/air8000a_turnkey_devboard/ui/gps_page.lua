-- GPS页面
local gps_page = {}

local main_container, content
local coord_label, update_interval_input

function gps_page.create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=480, h=320, color=0xF8F9FA })

    -- 顶部返回栏
    local header = airui.container({ parent = main_container, x=0, y=0, w=480, h=50, color=0x3F51B5 })
    local back_btn =  airui.button({ parent = header, x=10, y=5, w=50, h=40, color=0x3F51B5,text = "返回",
        on_click = function() _G.go_back() end
    })
  
    airui.label({ parent = header, x=60, y=10, w=360, h=30, align = airui.TEXT_ALIGN_CENTER, text="GPS", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=50, w=480, h=270, color=0xF3F4F6 })

    -- 坐标显示
    airui.label({ parent = content, x=20, y=20, w=150, h=30, text="当前经纬度:", font_size=18, color=0x000000 })
    coord_label = airui.label({ parent = content, x=180, y=20, w=250, h=30, text="等待定位...", font_size=18, color=0x000000 })

    -- 更新频率设置
    airui.label({ parent = content, x=20, y=70, w=150, h=30, text="更新频率(秒):", font_size=18, color=0x000000 })
    update_interval_input = airui.textarea({
        parent = content, x=180, y=70, w=80, h=30,
        placeholder = "1",
        keyboard = { mode = "numeric" }
    })

    -- 运动传感器状态（示例）
    airui.label({ parent = content, x=20, y=120, w=150, h=30, text="运动传感器:", font_size=18, color=0x000000 })
    airui.label({ parent = content, x=180, y=120, w=100, h=30, text="静止", font_size=18, color=0x000000 })
end

function gps_page.init()
    gps_page.create_ui()
    -- TODO: 启动GPS定时读取
    -- 例如：sys.timerLoopStart(read_gps, tonumber(update_interval_input:get_text()) or 1)
end

function gps_page.cleanup()
    if main_container then main_container:destroy(); main_container = nil end
    -- 停止GPS读取
end

return gps_page