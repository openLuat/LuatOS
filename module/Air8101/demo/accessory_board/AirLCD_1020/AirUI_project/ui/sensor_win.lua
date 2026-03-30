--[[
@module  sensor_win
@summary 传感器数据页面模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为传感器数据显示页面，实时显示温度、湿度、TVOC值，并提供手动上传和自动上传开关。
订阅"OPEN_SENSOR_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, content
local temp_label, hum_label, voc_label

local function update_sensor_data(data_t, data_h, data_voc)
    if not exwin.is_active(win_id) then return end
    if temp_label then
        temp_label:set_text(data_t and string.format("%.1f ℃", data_t) or "-- ℃")
    end
    if hum_label then
        hum_label:set_text(data_h and string.format("%.0f %%", data_h) or "-- %")
    end
    if voc_label then
        voc_label:set_text(data_voc and string.format("%d ppb", data_voc) or "-- ppb")
    end
end

local function sensor_data_handler(data_t, data_h, data_voc)
    update_sensor_data(data_t, data_h, data_voc)
end

local function create_ui()
    main_container = airui.container({ parent = airui.screen, x=0, y=0, w=800, h=480, color=0xF8F9FA })

    local header = airui.container({ parent = main_container, x=0, y=0, w=800, h=60, color=0x3F51B5 })
    local back_btn = airui.container({ parent = header, x = 700, y = 15, w = 80, h = 40, color = 0x2195F6, radius = 5,
        on_click = function() if win_id then exwin.close(win_id) end end
    })
    airui.label({ parent = back_btn, x = 10, y = 10, w = 60, h = 24, text = "返回", font_size = 20, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    airui.label({ parent = header, x = 10, y = 12, w = 500, h = 40, align = airui.TEXT_ALIGN_CENTER, text="传感器", font_size=32, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=60, w=800, h=420, color=0xF3F4F6 })

    airui.label({ parent = content, x=50, y=40, w=150, h=40, text="温度:", font_size=24, color=0x000000 })
    temp_label = airui.label({ parent = content, x=210, y=40, w=150, h=40, text="-- ℃", font_size=24, color=0xff0000 })

    airui.label({ parent = content, x=50, y=100, w=150, h=40, text="湿度:", font_size=24, color=0x000000 })
    hum_label = airui.label({ parent = content, x=210, y=100, w=150, h=40, text="-- %", font_size=24, color=0x0000ff })

    airui.label({ parent = content, x=50, y=160, w=150, h=40, text="TVOC:", font_size=24, color=0x000000 })
    voc_label = airui.label({ parent = content, x=210, y=160, w=150, h=40, text="-- ppb", font_size=24, color=0x00aa00 })

    airui.label({ parent = content, x=50, y=220, w=150, h=40, text="空气质量:", font_size=24, color=0x000000 })
    airui.label({ parent = content, x=210, y=220, w=150, h=40, text="--", font_size=24, color=0x000000 })

    airui.button({
        parent = content, x=320, y=300, w=120, h=50,
        text = "上传数据",
        font_size = 20,
        on_click = function()
            log.info("sensor", "手动上传")
        end
    })

    airui.switch({
        parent = content, x=500, y=310, w=70, h=36,
        checked = false,
        on_change = function(self)
            local state = self:get_state()
            log.info("sensor", "自动上传", state)
        end
    })
    airui.label({ parent = content, x=580, y=315, w=120, h=30, text="自动上传", font_size=20, color=0x000000 })
end

local function on_create()
    create_ui()
    sys.subscribe("SENSOR_DATA", sensor_data_handler)
    sys.publish("read_sensors_req")
end

local function on_destroy()
    sys.unsubscribe("SENSOR_DATA", sensor_data_handler)
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

local function on_get_focus()
    sys.publish("read_sensors_req")
end

local function on_lose_focus() end

local function open_handler()
   win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_SENSOR_WIN", open_handler)