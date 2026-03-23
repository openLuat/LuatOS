--[[
@module  main_menu_win
@summary 主菜单（全部应用）页面模块
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为主菜单页面，以图标网格形式显示所有功能入口。
订阅"OPEN_MAIN_MENU_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, time_label, signal_img
local full_path, current_time = "/luadb/4Gxinghao6.png", "08:00"
local StatusProvider = require "status_provider_app"

-- 创建UI
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 320, color = 0xF8F9FA, parent = airui.screen })
    -- 顶部状态栏
    local status_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 40, color = 0x3F51B5 })
    
    signal_img = airui.image({
        parent = status_bar,
        x = 430,
        y = 4,
        w = 32,
        h = 32,
        src = full_path
    })
    time_label = airui.label({ parent = status_bar, x = 188, y = 4, w = 100, h = 32, text = current_time, font_size = 30, color = 0xfefefe })

    -- 内容区域（图标网格 + 测试按钮）
    local content = airui.container({ parent = main_container, x = 0, y = 40, w = 480, h = 240, color = 0xF3F4F6 })

    -- 图标网格参数
    local col_centers = { 50, 145, 240, 335, 430 }
    local row_y_icons = { 9, 86, 163 }
    local win_map = {
        [1] = { "call", "camera", "network_select", "gps", "sensor" },
        [2] = { "iot_account", "bluetooth", "uart", "record", "tts" },
        [3] = { "apn", "ethernet", "wifi","fota" }
    }
    local icon_files = {
        [1] = { "/luadb/tonghuazhong.png", "/luadb/paizhao.png", "/luadb/Internet.png", "/luadb/dingwei.png", "/luadb/chuanganqi.png" },
        [2] = { "/luadb/denglu.png", "/luadb/lanya.png", "/luadb/chuankou.png", "/luadb/luyin.png", "/luadb/TTS.png" },
        [3] = { "/luadb/APN.png", "/luadb/yitaiwang.png", "/luadb/wifi.png", "/luadb/FOTA.png" }
    }
    local label_texts = {
        [1] = { "通话", "拍照", "多网融合", "定位", "传感器" },
        [2] = { "IoT账户", "蓝牙", "串口", "录音", "TTS" },
        [3] = { "APN配置", "以太网", "WIFI","FOTA" }
    }
    local cell_w, cell_h = 90, 70

    for row = 1, 3 do
        local cols = (row == 3) and 4 or 5
        for col = 1, cols do
            local center_x = col_centers[col]
            local cell_x = center_x - cell_w / 2
            local cell_y = row_y_icons[row] - 5
            local win_name = win_map[row][col]
            local cell = airui.container({
                parent = content,
                x = cell_x,
                y = cell_y,
                w = cell_w,
                h = cell_h,
                color = 0xF3F4F6,
                on_click = function()
                    if win_name then sys.publish("OPEN_" .. string.upper(win_name) .. "_WIN") end
                end
            })
            local icon_w, icon_h = 32, 32
            if row == 2 and col == 3 then icon_w, icon_h = 40, 40 end
            local icon_x = (cell_w - icon_w) / 2
            local icon_y = 5
            airui.image({ parent = cell, x = icon_x, y = icon_y, w = icon_w, h = icon_h, src = icon_files[row][col] })
            local label_x = (cell_w - 80) / 2
            local label_y = icon_y + icon_h + 6
            airui.label({
                parent = cell,
                x = label_x,
                y = label_y,
                w = 80,
                h = 16,
                text = label_texts[row][col],
                font_size = 16,
                color = 0x000000,
                align = airui.TEXT_ALIGN_CENTER
            })
        end
    end

    -- 底部按钮
    local bottom_bar = airui.container({ parent = main_container, x = 0, y = 280, w = 480, h = 40, color = 0xffffff })
    local btn_left = airui.container({ parent = bottom_bar, x = 0, y = 0, w = 240, h = 40, color = 0x2195F6, on_click = function()
        exwin.close(win_id) end })
    airui.image({ parent = btn_left, x = 53, y = 4, w = 32, h = 32, src = "/luadb/home.png" })
    airui.label({ parent = btn_left, x = 100, y = 10, w = 80, h = 30, text = "首页", font_size = 20, color = 0xfefefe })
    local btn_right = airui.container({ parent = bottom_bar, x = 240, y = 0, w = 240, h = 40, color = 0xFF9A27 })
    airui.image({ parent = btn_right, x = 53, y = 4, w = 32, h = 32, src = "/luadb/quanbuyingyong.png" })
    airui.label({ parent = btn_right, x = 100, y = 10, w = 100, h = 30, text = "主菜单", font_size = 20, color = 0xfefefe })
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