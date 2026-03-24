--[[
@module  main_menu_win
@summary 主菜单（全部应用）页面模块
@version 1.0
@date    2026.03.23
@author  江访
@usage
本模块为主菜单页面，以图标网格形式显示所有功能入口。
订阅"OPEN_MAIN_MENU_WIN"事件打开窗口。
]]

local win_id = nil
local main_container, time_label, signal_img
local full_path, current_time = "", "08:00"
local StatusProvider = require "status_provider_app"

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 800, h = 480, color = 0xF8F9FA, parent = airui.screen })

    -- 顶部状态栏
    local status_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 800, h = 60, color = 0x3F51B5 })
    signal_img = airui.image({
        parent = status_bar,
        x = 750,
        y = 14,
        w = 40,
        h = 40,
        src = full_path
    })
    time_label = airui.label({ parent = status_bar, x = 350, y = 10, w = 200, h = 48, text = current_time, font_size = 40, color = 0xfefefe })

    -- 内容区域
    local content = airui.container({ parent = main_container, x = 0, y = 60, w = 800, h = 420, color = 0xF3F4F6 })

    -- 图标网格参数（重新计算，保持3行，列数不变，但间距均匀）
    local col_centers = { 95, 240, 385, 530, 675 }   -- 原50,145,240,335,430 映射后
    local row_y_icons = { 10, 120, 230 }              -- 原9,86,163 映射后
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
    local cell_w, cell_h = 130, 100   -- 原90,70

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
            local icon_w, icon_h = 48, 48   -- 原32,32
            if row == 2 and col == 3 then icon_w, icon_h = 56, 56 end
            local icon_x = (cell_w - icon_w) / 2
            local icon_y = 10
            airui.image({ parent = cell, x = icon_x, y = icon_y, w = icon_w, h = icon_h, src = icon_files[row][col] })
            local label_x = (cell_w - 100) / 2
            local label_y = icon_y + icon_h + 10
            airui.label({
                parent = cell,
                x = label_x,
                y = label_y,
                w = 100,
                h = 20,
                text = label_texts[row][col],
                font_size = 18,
                color = 0x000000,
                align = airui.TEXT_ALIGN_CENTER
            })
        end
    end

    -- 底部按钮栏
    local bottom_bar = airui.container({ parent = main_container, x = 0, y = 420, w = 800, h = 60, color = 0xffffff })
    local btn_left = airui.container({ parent = bottom_bar, x = 0, y = 0, w = 400, h = 60, color = 0x2195F6, on_click = function() exwin.close(win_id) end })
    airui.image({ parent = btn_left, x = 133, y = 14, w = 32, h = 32, src = "/luadb/home.png" })
    airui.label({ parent = btn_left, x = 180, y = 15, w = 120, h = 40, text = "首页", font_size = 24, color = 0xfefefe })
    local btn_right = airui.container({ parent = bottom_bar, x = 400, y = 0, w = 400, h = 60, color = 0xFF9A27 })
    airui.image({ parent = btn_right, x = 133, y = 14, w = 32, h = 32, src = "/luadb/quanbuyingyong.png" })
    airui.label({ parent = btn_right, x = 180, y = 15, w = 120, h = 40, text = "主菜单", font_size = 24, color = 0xfefefe })
end

local function update_time()
    if not time_label then return end
    current_time = StatusProvider.get_time()
    time_label:set_text(current_time)
end

-- 更新WiFi信号图标
local function update_signal()
    local level = StatusProvider.get_signal_level()
    if not signal_img then return end
    local img_name = "wifixinhao" .. level .. ".png"
    local full_path = "/luadb/" .. img_name
    signal_img:set_src(full_path)
end

local function on_status_time_updated()
    update_time()
end

local function on_status_signal_updated()
    update_signal()
end

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
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end
sys.subscribe("OPEN_MAIN_MENU_WIN", open_handler)