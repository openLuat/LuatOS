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

--[[
更新传感器数据显示

@local
@function update_sensor_data
@param data_t number|nil 温度值
@param data_h number|nil 湿度值
@param data_voc number|nil TVOC值
@return nil
@usage
-- 内部调用，当收到传感器数据时更新UI
-- 仅当窗口活跃时执行
]]
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

-- 传感器数据事件处理函数
local function sensor_data_handler(data_t, data_h, data_voc)
    update_sensor_data(data_t, data_h, data_voc)
end

--[[
创建窗口UI

@local
@function create_ui
@return nil
@usage
-- 内部调用，创建全屏容器、标题栏、返回按钮、数据标签和操作控件
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

    airui.label({ parent = header, x = 10, y = 4, w = 360, h = 32, align = airui.TEXT_ALIGN_CENTER, text="传感器", font_size=24, color=0xffffff })

    content = airui.container({ parent = main_container, x=0, y=40, w=480, h=280, color=0xF3F4F6 })

    -- 温度
    airui.label({ parent = content, x=20, y=20, w=100, h=30, text="温度:", font_size=18, color=0x000000 })
    temp_label = airui.label({ parent = content, x=120, y=20, w=100, h=30, text="-- ℃", font_size=18, color=0xff0000 })

    -- 湿度
    airui.label({ parent = content, x=20, y=60, w=100, h=30, text="湿度:", font_size=18, color=0x000000 })
    hum_label = airui.label({ parent = content, x=120, y=60, w=100, h=30, text="-- %", font_size=18, color=0x0000ff })

    -- 空气质量
    airui.label({ parent = content, x=20, y=100, w=100, h=30, text="TVOC:", font_size=18, color=0x000000 })
    voc_label = airui.label({ parent = content, x=120, y=100, w=100, h=30, text="-- ppb", font_size=18, color=0x00aa00 })

    -- 空气质量描述
    airui.label({ parent = content, x=20, y=140, w=100, h=30, text="空气质量:", font_size=18, color=0x000000 })
    airui.label({ parent = content, x=120, y=140, w=100, h=30, text="--", font_size=18, color=0x000000 })

    -- 手动上传按钮
    airui.button({
        parent = content, x=190, y=200, w=100, h=40,
        text = "上传数据",
        on_click = function()
            -- TODO: 上传当前传感器数据到云端
            log.info("sensor", "手动上传")
        end
    })

    -- 自动上传开关
    airui.switch({
        parent = content, x=300, y=205, w=60, h=30,
        checked = false,
        on_change = function(self)
            local state = self:get_state()
            -- TODO: 根据状态启动/停止自动上传定时器
            log.info("sensor", "自动上传", state)
        end
    })
    airui.label({ parent = content, x=370, y=210, w=100, h=20, text="自动上传", font_size=16, color=0x000000 })
end

--[[
窗口创建回调

@local
@function on_create
@return nil
@usage
-- 窗口打开时调用，创建UI并订阅传感器数据事件
]]
local function on_create()
    create_ui()
    sys.subscribe("SENSOR_DATA", sensor_data_handler)
    -- 主动请求一次数据
    sys.publish("read_sensors_req")
end

--[[
窗口销毁回调

@local
@function on_destroy
@return nil
@usage
-- 窗口关闭时调用，取消订阅，销毁容器
]]
local function on_destroy()
    sys.unsubscribe("SENSOR_DATA", sensor_data_handler)
    if main_container then main_container:destroy(); main_container = nil end
    win_id = nil
end

-- 窗口获得焦点回调
local function on_get_focus()
    -- 刷新数据
    sys.publish("read_sensors_req")
end

-- 窗口失去焦点回调
local function on_lose_focus()
    -- 可暂停自动上传等
end

-- 订阅打开传感器页面的消息
local function open_handler()
   win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end
sys.subscribe("OPEN_SENSOR_WIN", open_handler)