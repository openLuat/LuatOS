-- lua - 全部应用页面（使用 exwin.is_active 判断活跃）

local win_id = nil
local main_container, time_label, signal_img
local full_path, current_time = "/luadb/4Gxinghao6.png", "08:00"
local StatusProvider = require "status_provider_app"

-- 创建UI
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 1024, h = 600, color = 0xF8F9FA, parent = airui.screen })
    -- 顶部状态栏
    local status_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 1024, h = 60, color = 0x3F51B5 })
    
    signal_img = airui.image({
        parent = status_bar,
        x = 920,
        y = 10,
        w = 40,
        h = 40,
        src = full_path
    })
    time_label = airui.label({ parent = status_bar, x = 400, y = 10, w = 200, h = 40, text = current_time, font_size = 36, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    -- 内容区域（图标网格 + 测试按钮）
    local content = airui.container({ parent = main_container, x = 0, y = 60, w = 1024, h = 480, color = 0xF3F4F6 })

    -- 图标网格参数
    local col_centers = { 160, 512, 864 }
    local row_y_icons = { 30, 180, 330 }
    local win_map = {
        [1] = { "camera", "network_select", "gps" },
        [2] = { "sensor", "iot_account", "bluetooth" },
        [3] = { "uart", "tts", "wifi" }
    }
    local icon_files = {
        [1] = { "/luadb/paizhao.png", "/luadb/Internet.png", "/luadb/dingwei.png" },
        [2] = { "/luadb/chuanganqi.png", "/luadb/denglu.png", "/luadb/lanya.png" },
        [3] = { "/luadb/chuankou.png", "/luadb/TTS.png", "/luadb/wifi.png" }
    }
    local label_texts = {
        [1] = { "摄像头", "多网融合", "定位" },
        [2] = { "传感器", "IoT账户", "蓝牙" },
        [3] = { "串口", "TTS", "WIFI" }
    }
    local cell_w, cell_h = 260, 130

    for row = 1, 3 do
        local cols = 3
        for col = 1, cols do
            local center_x = col_centers[col]
            local cell_x = center_x - cell_w / 2
            local cell_y = row_y_icons[row]
            local win_name = win_map[row][col]
            local cell = airui.container({
                parent = content,
                x = cell_x,
                y = cell_y,
                w = cell_w,
                h = cell_h,
                color = 0xffffff,
                radius = 10,
                on_click = function()
                    if win_name then sys.publish("OPEN_" .. string.upper(win_name) .. "_WIN") end
                end
            })
            local icon_w, icon_h = 60, 60
            if row == 2 and col == 3 then icon_w, icon_h = 60, 60 end
            local icon_x = (cell_w - icon_w) / 2
            local icon_y = 15
            airui.image({ parent = cell, x = icon_x, y = icon_y, w = icon_w, h = icon_h, src = icon_files[row][col] })
            local label_y = icon_y + icon_h + 10
            airui.label({
                parent = cell,
                x = 0,
                y = label_y,
                w = cell_w,
                h = 25,
                text = label_texts[row][col],
                font_size = 20,
                color = 0x000000,
                align = airui.TEXT_ALIGN_CENTER
            })
        end
    end

    -- 底部按钮
    local btn_left = airui.container({ parent = main_container, x = 0, y = 540, w = 512, h = 60, color = 0x2195F6, on_click = function()
        exwin.close(win_id) end })
    airui.image({ parent = btn_left, x = 200, y = 10, w = 40, h = 40, src = "/luadb/home.png" })
    airui.label({ parent = btn_left, x = 260, y = 15, w = 100, h = 30, text = "首页", font_size = 24, color = 0xfefefe })
    local btn_right = airui.container({ parent = main_container, x = 512, y = 540, w = 512, h = 60, color = 0xFF9A27 })
    airui.image({ parent = btn_right, x = 200, y = 10, w = 40, h = 40, src = "/luadb/quanbuyingyong.png" })
    airui.label({ parent = btn_right, x = 260, y = 15, w = 150, h = 30, text = "全部应用", font_size = 24, color = 0xfefefe })
end

-- 更新时间
local function update_time()
    if not time_label then return end
    -- exwin.is_active 在页面刚打开时可能还是false，放宽判断，只检查控件是否存在
    -- 即使不活跃，更新控件也不会出问题，而且当获得焦点时on_get_focus会再次刷新
    current_time = StatusProvider.get_time()
    time_label:set_text(current_time)
end

-- 更新信号图标
local function update_signal()
    local csq_level = StatusProvider.get_signal_level()
    if not signal_img then return end
    local signal_img_name = "4Gxinghao6.png" -- 默认无信号
    if csq_level > 0 and csq_level <= 5 then
        signal_img_name = "4Gxinghao" .. csq_level .. ".png"
    elseif csq_level >= 6 then
        signal_img_name = "4Gxinghao6.png"
    end
    full_path = "/luadb/" .. signal_img_name
    signal_img:set_src(full_path)
end

-- 处理StatusProvider的时间更新事件
local function on_status_time_updated()
    update_time()
end

-- 处理StatusProvider的信号更新事件
local function on_status_signal_updated()
    update_signal()
end


-- 创建UI界面
local function on_create()
    create_ui()
    update_time()
    update_signal()
    sys.timerLoopStart(update_time, 1000)
    sys.subscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    sys.subscribe("STATUS_SIGNAL_UPDATED", on_status_signal_updated)
end

local function on_destroy()
    sys.timerStop(update_time)
    sys.unsubscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    sys.unsubscribe("STATUS_SIGNAL_UPDATED", on_status_signal_updated)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    time_label, signal_img = nil, nil
end

local function on_get_focus()
    update_time()
    update_signal()
end

local function on_lose_focus()
    -- 无需操作
end

-- 订阅打开全部应用页面的消息
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end
sys.subscribe("OPEN_MAIN_MENU_WIN", open_handler)