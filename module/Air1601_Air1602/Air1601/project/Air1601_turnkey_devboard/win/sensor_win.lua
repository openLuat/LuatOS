-- sensor_win.lua - 传感器页面(Air1601版本，适配1024x600分辨率)

local win_id = nil
local main_container, content
local temp_label, hum_label, voc_label, air_quality_label

local function get_air_quality_level(voc_value)
    if not voc_value then return "--"
    elseif voc_value < 200 then return "优"
    elseif voc_value < 300 then return "良"
    elseif voc_value < 600 then return "轻度污染"
    elseif voc_value < 1000 then return "中度污染"
    elseif voc_value < 3000 then return "重度污染"
    else return "严重污染"
    end
end

local function get_air_quality_color(voc_value)
    if not voc_value then return 0x000000
    elseif voc_value < 200 then return 0x00aa00
    elseif voc_value < 300 then return 0x00cc00
    elseif voc_value < 600 then return 0xffcc00
    elseif voc_value < 1000 then return 0xff6600
    elseif voc_value < 3000 then return 0xff0000
    else return 0x990000
    end
end

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
    if air_quality_label then
        local quality = get_air_quality_level(data_voc)
        local color = get_air_quality_color(data_voc)
        air_quality_label:set_text(quality)
        air_quality_label:set_color(color)
    end
end

local function sensor_data_handler(data_t, data_h, data_voc)
    update_sensor_data(data_t, data_h, data_voc)
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 1024, h = 600, color = 0xF8F9FA, parent = airui.screen })

    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 1024, h = 60, color = 0x3F51B5 })
    local back_btn = airui.button({ parent = header, x = 924, y = 10, w = 80, h = 40, color = 0x2195F6, text = "返回", font_size = 30, text_color = 0xffffff,
        on_click = function() if win_id then exwin.close(win_id) win_id = nil end end
    })
    airui.label({ parent = header, x = 400, y = 10, w = 224, h = 40, text = "传感器", font_size = 32, color = 0xffffff, align = airui.TEXT_ALIGN_CENTER })

    content = airui.container({ parent = main_container, x = 0, y = 60, w = 1024, h = 540, color = 0xF3F4F6 })

    -- 温度
    airui.label({ parent = content, x = 200, y = 100, w = 150, h = 40, text = "温度:", font_size = 24, color = 0x000000 })
    temp_label = airui.label({ parent = content, x = 350, y = 100, w = 200, h = 40, text = "-- ℃", font_size = 24, color = 0xff0000 })

    -- 湿度
    airui.label({ parent = content, x = 200, y = 180, w = 150, h = 40, text = "湿度:", font_size = 24, color = 0x000000 })
    hum_label = airui.label({ parent = content, x = 350, y = 180, w = 200, h = 40, text = "-- %", font_size = 24, color = 0x0000ff })

    -- 空气质量
    airui.label({ parent = content, x = 200, y = 260, w = 150, h = 40, text = "TVOC:", font_size = 24, color = 0x000000 })
    voc_label = airui.label({ parent = content, x = 350, y = 260, w = 200, h = 40, text = "-- ppb", font_size = 24, color = 0x00aa00 })

    -- 空气质量描述
    airui.label({ parent = content, x = 200, y = 340, w = 150, h = 40, text = "空气质量:", font_size = 24, color = 0x000000 })
    air_quality_label = airui.label({ parent = content, x = 350, y = 340, w = 200, h = 40, text = "--", font_size = 24, color = 0x000000 })

    -- 手动上传按钮
    airui.button({
        parent = content, x = 400, y = 420, w = 150, h = 50,
        text = "上传数据",
        on_click = function()
            -- TODO: 上传当前传感器数据到云端
            log.info("sensor", "手动上传")
        end
    })

    -- 自动上传开关
    airui.switch({
        parent = content, x = 600, y = 430, w = 80, h = 40,
        checked = false,
        on_change = function(self)
            local state = self:get_state()
            -- TODO: 根据状态启动/停止自动上传定时器
            log.info("sensor", "自动上传", state)
        end
    })
    airui.label({ parent = content, x = 700, y = 430, w = 150, h = 40, text = "自动上传", font_size = 24, color = 0x000000 })
end

local function on_create()
    create_ui()
    sys.subscribe("ui_sensor_data", sensor_data_handler)
    -- 主动请求一次数据
    sys.publish("read_sensors_req")
end

local function on_destroy()
    sys.unsubscribe("ui_sensor_data", sensor_data_handler)
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

local function on_get_focus()
    -- 刷新数据
    sys.publish("read_sensors_req")
end

local function on_lose_focus()
    -- 可暂停自动上传等
end

sys.subscribe("OPEN_SENSOR_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({ 
            on_create = on_create, 
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus
        })
    end
end)
