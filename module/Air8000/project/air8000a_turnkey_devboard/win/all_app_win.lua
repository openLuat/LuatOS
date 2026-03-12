-- all_app_win_lua - 全部应用页面（使用 exwin.is_active 判断活跃）

local win_id = nil
local main_container, time_label, signal_img
local time_timer, signal_timer

-- 更新时间
local function update_time()
    if not exwin.is_active(win_id) then return end
    local t = os.time()
    if t then
        local dt = os.date("*t", t)
        local time_str = string.format("%02d:%02d", dt.hour, dt.min)
        if time_label then time_label:set_text(time_str) end
    end
end

-- 更新信号图标
local function update_signal()
    if not exwin.is_active(win_id) or not signal_img then return end
    local img_name
    if not sim_present then
        img_name = "4Gxinghao6.png"
    else
        local csq = mobile.csq()
        if csq == 99 or csq <= 5 then img_name = "4Gxinghao5.png"
        elseif csq <= 10 then img_name = "4Gxinghao1.png"
        elseif csq <= 15 then img_name = "4Gxinghao2.png"
        elseif csq <= 20 then img_name = "4Gxinghao3.png"
        else img_name = "4Gxinghao4.png" end
    end
    if img_name then signal_img:set_src("/luadb/" .. img_name) end
end

-- 处理SIM卡状态
local function handle_sim_ind(status, value)
    if status == "RDY" then sim_present = true
    elseif status == "NORDY" then sim_present = false end
    update_signal()
end

-- 创建UI
local function create_ui()
    main_container = airui.container({ x=0, y=0, w=480, h=320, color=0xF8F9FA, parent = airui.screen })
    -- 顶部状态栏
    local status_bar = airui.container({ parent = main_container, x=0, y=0, w=480, h=40, color=0x3F51B5 })
    signal_img = airui.image({ parent = status_bar, x=430, y=4, w=32, h=32, src = lte_csq or "/luadb/4Gxinghao6.png" })
    time_label = airui.label({ parent = status_bar, x=188, y=4, w=100, h=32, text= show_time or "--:--", font_size=30, color=0xfefefe })

    -- 内容区域（图标网格 + 测试按钮）
    local content = airui.container({ parent = main_container, x=0, y=40, w=480, h=240, color=0xF3F4F6 })

    -- 图标网格参数
    local col_centers = { 50, 145, 240, 335, 430 }
    local row_y_icons = { 9, 86, 163 }
    local win_map = {
        [1] = { "call", "camera", "network_select", "gps", "sensor" },
        [2] = { "iot_account", "bluetooth", "uart", "record", "tts" },
        [3] = { "apn", "ethernet", "wifi" }
    }
    local icon_files = {
        [1] = { "/luadb/tonghuazhong.png", "/luadb/paizhao.png", "/luadb/Internet.png", "/luadb/dingwei.png", "/luadb/chuanganqi.png" },
        [2] = { "/luadb/denglu.png", "/luadb/lanya.png", "/luadb/chuankou.png", "/luadb/luyin.png", "/luadb/TTS.png" },
        [3] = { "/luadb/APN.png", "/luadb/yitaiwang.png", "/luadb/wifi.png" }
    }
    local label_texts = {
        [1] = { "通话", "拍照", "多网融合", "定位", "传感器" },
        [2] = { "IoT账户", "蓝牙", "串口", "录音", "TTS" },
        [3] = { "APN配置", "以太网", "WIFI" }
    }
    local cell_w, cell_h = 90, 70

    for row = 1, 3 do
        local cols = (row == 3) and 3 or 5
        for col = 1, cols do
            local center_x = col_centers[col]
            local cell_x = center_x - cell_w/2
            local cell_y = row_y_icons[row] - 5
            local win_name = win_map[row][col]
            local cell = airui.container({
                parent = content, x = cell_x, y = cell_y, w = cell_w, h = cell_h,
                color = 0xF3F4F6,
                on_click = function()
                    if win_name then sys.publish("OPEN_" .. string.upper(win_name) .. "_WIN") end
                end
            })
            local icon_w, icon_h = 32, 32
            if row == 2 and col == 3 then icon_w, icon_h = 40, 40 end
            local icon_x = (cell_w - icon_w)/2
            local icon_y = 5
            airui.image({ parent = cell, x = icon_x, y = icon_y, w = icon_w, h = icon_h, src = icon_files[row][col] })
            local label_x = (cell_w - 80)/2
            local label_y = icon_y + icon_h + 6
            airui.label({ parent = cell, x = label_x, y = label_y, w = 80, h = 16,
                text = label_texts[row][col], font_size = 16, color = 0x000000, align = airui.TEXT_ALIGN_CENTER })
        end
    end

    -- 底部按钮
    local bottom_bar = airui.container({ parent = main_container, x=0, y=280, w=480, h=40, color=0xffffff })
    local btn_left = airui.container({ parent = bottom_bar, x=0, y=0, w=240, h=40, color=0x2195F6,
        on_click = function() exwin.close(win_id) end })
    airui.image({ parent = btn_left, x=53, y=4, w=32, h=32, src="/luadb/home.png" })
    airui.label({ parent = btn_left, x=100, y=10, w=80, h=30, text="首页", font_size=20, color=0xfefefe })
    local btn_right = airui.container({ parent = bottom_bar, x=240, y=0, w=240, h=40, color=0xFF9A27 })
    airui.image({ parent = btn_right, x=53, y=4, w=32, h=32, src="/luadb/quanbuyingyong.png" })
    airui.label({ parent = btn_right, x=100, y=10, w=100, h=30, text="全部应用", font_size=20, color=0xfefefe })
end

-- 生命周期回调
function all_app_win_on_create()
    create_ui()
    time_timer = sys.timerLoopStart(update_time, 1000)
    signal_timer = sys.timerLoopStart(update_signal, 2000)
    sys.subscribe("SIM_IND", handle_sim_ind)
    update_time()
    update_signal()
end

function all_app_win_on_destroy()
    if time_timer then sys.timerStop(time_timer); time_timer = nil end
    if signal_timer then sys.timerStop(signal_timer); signal_timer = nil end
    sys.unsubscribe("SIM_IND", handle_sim_ind)
    if main_container then main_container:destroy(); main_container = nil end
    time_label, signal_img = nil, nil
end

function all_app_win_on_get_focus()
    update_time()
    update_signal()
end

function all_app_win_on_lose_focus()
    -- 无需操作
end

-- 订阅打开全部应用页面的消息
local function open_all_app_win_handler()
    win_id = exwin.open({
        on_create = all_app_win_on_create,
        on_destroy = all_app_win_on_destroy,
        on_lose_focus = all_app_win_on_lose_focus,
        on_get_focus = all_app_win_on_get_focus,
    })
end
sys.subscribe("OPEN_ALL_APP_WIN", open_all_app_win_handler)