--[[
@module  battle_latency_win
@summary  对战测速窗口模块 - 双设备通信效率测试
@version  1.0.0
@date    2026.05.09
@author  王世豪
@usage
基于MQTT实现设备间通信，支持公网对战，使用exwin + airui创建界面
支持查看在线设备列表并手动选择连接，实时位置同步和延迟测试
]]

-- 游戏状态
local game_state = {
    -- 在线设备列表：{device_id: {last_seen: timestamp, is_server: boolean}}
    online_devices = {},
    -- 当前连接的设备
    peer_connected = false,
    peer_device_id = nil,
    -- 自己的位置
    my_position = {x = 30, y = 130},
    peer_position = {x = 230, y = 130},
    -- 延迟测试
    latency_list = {},
    test_count = 0,
    last_ping_time = 0,
    is_testing = false,
    is_server = false,
    -- MQTT相关
    mqtt_client = nil,
    mqtt_ready = false,
    is_running = true
}

-- 触摸拖动状态
local touch = {
    dragging = false,
    track_id = nil,
    offset_x = 0,  -- 触摸点相对于玩家的偏移
    offset_y = 0
}

-- 默认位置配置
local SERVER_POS = {x = 60, y = 140}
local CLIENT_POS = {x = 210, y = 140}

-- MQTT服务器配置
local MQTT_SERVER = "lbsmqtt.airm2m.com"
local MQTT_PORT = 1884
local MQTT_QOS = 0
local TASK_NAME = "simple_battle_mqtt"

-- UI元素引用
local win_id = nil
local main_container = nil
local status_label = nil
local latency_label = nil
local test_btn = nil
local player_rect = nil
local peer_rect = nil
local my_id_label = nil
local peer_id_label = nil
-- 设备列表相关UI
local device_list_container = nil
local device_list_items = {}
-- 设备列表弹窗相关
local device_list_win_id = nil
local device_list_main_container = nil
local device_list_popup_items = {}

-- 屏幕尺寸
local screen_w = 320
local screen_h = 480
local scale_x = 1.0
local scale_y = 1.0

-- 读取显示尺寸
local function refresh_display()
    if lcd and lcd.getSize then
        local w, h = lcd.getSize()
        if w and h and w > 0 and h > 0 then
            screen_w = w
            screen_h = h
            log.info("battle", "屏幕尺寸:", screen_w, "x", screen_h)
        end
    end
    -- 计算缩放比例（相对于320*480）
    scale_x = screen_w / 320
    scale_y = screen_h / 480
end

-- 把坐标从320*480缩放到实际屏幕
local function scale_pos(x, y)
    return math.floor(x * scale_x), math.floor(y * scale_y)
end

-- 获取设备ID
local function get_device_id()
    local device_id = "DEV_UNKNOWN"
    if mobile and mobile.imei then
        device_id = mobile.imei()
        log.info("battle", "获取到IMEI:", device_id)
    elseif wlan and wlan.getMac then
        device_id = wlan.getMac()
        log.info("battle", "获取到MAC地址:", device_id)
    else
        device_id = "DEV_" .. tostring(os.time())
        log.info("battle", "使用临时设备ID:", device_id)
    end
    return device_id
end

local my_device_id = get_device_id()
local TOPIC_PRESENCE = "simple_battle/presence"
local TOPIC_DATA = "simple_battle/data/"

-- 更新状态标签
local function update_status(text)
    if not game_state.is_running then return end
    log.info("状态", text)
    if status_label and status_label.set_text then
        status_label:set_text(text)
    end
end

-- 更新延迟标签
local function update_latency_label(text)
    if not game_state.is_running then return end
    if latency_label and latency_label.set_text then
        latency_label:set_text(text)
    end
end

-- 更新自己位置显示
local function update_my_position()
    if not game_state.is_running then return end
    if player_rect and player_rect.set_pos then
        local px, py = scale_pos(game_state.my_position.x, game_state.my_position.y)
        player_rect:set_pos(px, py)
    end
end

-- 更新对方位置显示
local function update_peer_position()
    if not game_state.is_running then return end
    if peer_rect and peer_rect.set_pos then
        local px, py = scale_pos(game_state.peer_position.x, game_state.peer_position.y)
        peer_rect:set_pos(px, py)
    end
end

-- 移动玩家
local function move_player(dx, dy)
    if not game_state.is_running then
        return
    end
    game_state.my_position.x = game_state.my_position.x + dx
    game_state.my_position.y = game_state.my_position.y + dy

    -- 边界限制（基于逻辑坐标系320*480，适配不同分辨率）
    -- 游戏区域：x=5-315, y=75-225，玩家大小30x30，允许贴到灰色边缘
    local game_area_x = 5
    local game_area_y = 75
    local game_area_w = 310
    local game_area_h = 150
    local player_size = 30
    local min_x = game_area_x
    local max_x = game_area_x + game_area_w - player_size
    local min_y = game_area_y
    local max_y = game_area_y + game_area_h - player_size

    if game_state.my_position.x < min_x then game_state.my_position.x = min_x end
    if game_state.my_position.x > max_x then game_state.my_position.x = max_x end
    if game_state.my_position.y < min_y then game_state.my_position.y = min_y end
    if game_state.my_position.y > max_y then game_state.my_position.y = max_y end

    update_my_position()
end

-- 发送位置更新
local function send_position_update()
    if not game_state.is_running or not game_state.peer_connected or not game_state.peer_device_id then
        return
    end
    
    local data = {
        type = "position",
        device_id = my_device_id,
        x = game_state.my_position.x,
        y = game_state.my_position.y
    }
    
    if game_state.mqtt_client then
        game_state.mqtt_client:publish(TOPIC_DATA .. game_state.peer_device_id, json.encode(data), MQTT_QOS)
    end
end

-- 重置触摸状态
local function reset_touch_state()
    touch.dragging = false
    touch.track_id = nil
    touch.offset_x = 0
    touch.offset_y = 0
end

-- 判断是否点击到玩家
local function touch_hits_player(x, y)
    -- 把触摸坐标从实际屏幕缩放到 320*480 坐标系
    local scaled_x = x / scale_x
    local scaled_y = y / scale_y
    local player_size = 30  -- 玩家实际大小是30x30
    local px = game_state.my_position.x
    local py = game_state.my_position.y
    local hit = scaled_x >= px and scaled_x <= px + player_size and scaled_y >= py and scaled_y <= py + player_size
    -- log.info("battle", "touch hit check: raw x="..x..", y="..y..", scaled x="..scaled_x..", y="..scaled_y..", player x="..px..", y="..py..", hit="..tostring(hit))
    return hit
end

-- 移动玩家到指定位置（带边界限制）
local function move_player_to(x, y)
    if not game_state.is_running then
        return
    end

    -- 把触摸坐标从实际屏幕缩放到 320*480 坐标系
    local scaled_x = x / scale_x
    local scaled_y = y / scale_y

    -- 应用偏移
    local new_x = scaled_x - touch.offset_x
    local new_y = scaled_y - touch.offset_y

    -- 边界限制（基于逻辑坐标系320*480，适配不同分辨率）
    -- 游戏区域：x=5-315, y=75-225，玩家大小30x30，允许贴到灰色边缘
    local game_area_x = 5
    local game_area_y = 75
    local game_area_w = 310
    local game_area_h = 150
    local player_size = 30
    local min_x = game_area_x
    local max_x = game_area_x + game_area_w - player_size
    local min_y = game_area_y
    local max_y = game_area_y + game_area_h - player_size

    if new_x < min_x then new_x = min_x end
    if new_x > max_x then new_x = max_x end
    if new_y < min_y then new_y = min_y end
    if new_y > max_y then new_y = max_y end

    game_state.my_position.x = new_x
    game_state.my_position.y = new_y
    update_my_position()
    send_position_update()
end

-- 注册触摸订阅
local function register_touch_handler()
    airui.touch_subscribe(function(state, x, y, track_id)
        -- log.info("battle", "touch event: state="..state..", x="..x..", y="..y..", peer_connected="..tostring(game_state.peer_connected)..", scale_x="..scale_x..", scale_y="..scale_y)
        
        if not main_container or not (state and x and y) or not game_state.is_running then
            return
        end
        
        local is_down = (airui.TP_DOWN and state == airui.TP_DOWN) or (tp and tp.EVENT_DOWN and state == tp.EVENT_DOWN) or (state == 1)
        local is_hold = (airui.TP_HOLD and state == airui.TP_HOLD) or (tp and tp.EVENT_MOVE and state == tp.EVENT_MOVE) or (state == 3)
        local is_up = (airui.TP_UP and state == airui.TP_UP) or (tp and tp.EVENT_UP and state == tp.EVENT_UP) or (state == 2)
        
        if is_down then
            -- 按下事件到来时，先重置任何残留拖动状态，避免后续按钮点击被误判为拖动
            if touch.dragging then
                reset_touch_state()
            end

            -- log.info("battle", "DOWN, check conditions: dragging="..tostring(touch.dragging)..", peer_connected="..tostring(game_state.peer_connected))
            if not touch.dragging and game_state.peer_connected and touch_hits_player(x, y) then
                -- log.info("battle", "start dragging")
                touch.dragging = true
                touch.track_id = track_id
                -- 记录偏移：避免按住边缘时突然跳到中心（使用缩放后的坐标）
                local scaled_x = x / scale_x
                local scaled_y = y / scale_y
                touch.offset_x = scaled_x - game_state.my_position.x
                touch.offset_y = scaled_y - game_state.my_position.y
                move_player_to(x, y)
            end
        elseif is_hold then
            -- 拖动中
            -- log.info("battle", "HOLD, dragging="..tostring(touch.dragging))
            if touch.dragging and (track_id == nil or touch.track_id == nil or track_id == touch.track_id) then
                move_player_to(x, y)
            end
        elseif is_up then
            -- 结束触摸
            -- log.info("battle", "UP")
            if touch.dragging and (track_id == nil or touch.track_id == nil or track_id == touch.track_id) then
                reset_touch_state()
            end
        end
    end)
end

-- 发送ping测试
local function send_ping()
    if not game_state.is_running or not game_state.peer_connected or not game_state.peer_device_id then
        return
    end
    
    local ms_h, ms_l = mcu.ticks2(1)
    local timestamp = tostring(ms_h * 1000000 + ms_l)
    game_state.last_ping_time = ms_h * 1000000 + ms_l
    -- log.info("battle_ping", "send_ping", "timestamp=" .. timestamp, "last_ping_time=" .. tostring(game_state.last_ping_time))
    
    local data = {
        type = "ping",
        device_id = my_device_id,
        timestamp = timestamp
    }
    
    if game_state.mqtt_client then
        game_state.mqtt_client:publish(TOPIC_DATA .. game_state.peer_device_id, json.encode(data), MQTT_QOS)
    end
end

-- 发送pong响应
local function send_pong(timestamp)
    if not game_state.is_running or not game_state.peer_connected or not game_state.peer_device_id then
        return
    end
    
    local data = {
        type = "pong",
        device_id = my_device_id,
        timestamp = timestamp
    }
    
    if game_state.mqtt_client then
        game_state.mqtt_client:publish(TOPIC_DATA .. game_state.peer_device_id, json.encode(data), MQTT_QOS)
    end
end

-- 广播自己的存在
local function send_presence()
    if not game_state.is_running or not game_state.mqtt_ready then
        return
    end
    
    -- 如果已经连接了，就不需要再广播了
    if game_state.peer_connected and game_state.peer_device_id then
        return
    end
    
    local data = {
        type = "presence",
        device_id = my_device_id,
        is_server = game_state.is_server
    }
    
    log.info("battle", "广播自己的存在", json.encode(data))
    if game_state.mqtt_client then
        game_state.mqtt_client:publish(TOPIC_PRESENCE, json.encode(data), MQTT_QOS)
    end
end

-- 记录延迟
local function record_latency(latency)
    if not game_state.is_running then return end
    log.info("battle", "记录延迟:", latency, "ms")
    table.insert(game_state.latency_list, latency)
    game_state.test_count = game_state.test_count + 1
    
    if #game_state.latency_list > 100 then
        table.remove(game_state.latency_list, 1)
    end
    
    local sum = 0
    for _, v in ipairs(game_state.latency_list) do
        sum = sum + v
    end
    local avg_latency = sum / #game_state.latency_list
    
    update_latency_label(string.format("测试#%d 当前:%dms 平均:%.1fms", 
        game_state.test_count, latency, avg_latency))
end

-- 关闭设备列表弹窗
local function close_device_list_win()
    if device_list_win_id then
        exwin.close(device_list_win_id)
    end
end

-- 打开设备列表弹窗
local function open_device_list_win()
    if device_list_win_id then
        return
    end
    
    device_list_win_id = exwin.open({
        on_create = function()
            log.info("battle", "设备列表窗口创建")
            
            device_list_main_container = airui.container({
                x = 0,
                y = 0,
                w = screen_w,
                h = screen_h,
                color = 0xFFFFFF,
                parent = airui.screen
            })
            
            -- 标题
            airui.label({
                parent = device_list_main_container,
                text = "选择设备连接",
                x = math.floor(5 * scale_x),
                y = math.floor(5 * scale_y),
                w = math.floor(310 * scale_x),
                h = math.floor(40 * scale_y),
                font_size = math.floor(18 * math.min(scale_x, scale_y)),
                color = 0x333333,
                align = airui.TEXT_ALIGN_CENTER
            })
            
            -- 刷新按钮
            airui.button({
                parent = device_list_main_container,
                text = "刷新",
                x = math.floor(5 * scale_x),
                y = math.floor(440 * scale_y),
                w = math.floor(100 * scale_x),
                h = math.floor(35 * scale_y),
                font_size = math.floor(14 * math.min(scale_x, scale_y)),
                text_color = 0xFFFFFF,
                bg_color = 0x9932CC,
                on_click = function()
                    send_presence()
                    -- 清空并重新添加设备列表
                    for _, item in ipairs(device_list_popup_items) do
                        if item then
                            item:destroy()
                        end
                    end
                    device_list_popup_items = {}
                    
                    -- 显示在线设备数量
                    local count = 0
                    for _ in pairs(game_state.online_devices) do
                        count = count + 1
                    end
                    
                    local count_label = airui.label({
                        parent = device_list_main_container,
                        text = "在线设备: " .. count .. " 个",
                        x = math.floor(5 * scale_x),
                        y = math.floor(50 * scale_y),
                        w = math.floor(310 * scale_x),
                        h = math.floor(25 * scale_y),
                        font_size = math.floor(14 * math.min(scale_x, scale_y)),
                        color = 0x0066CC,
                        align = airui.TEXT_ALIGN_CENTER
                    })
                    table.insert(device_list_popup_items, count_label)
                    
                    if count == 0 then
                        local label = airui.label({
                            parent = device_list_main_container,
                            text = "暂无在线设备",
                            x = math.floor(5 * scale_x),
                            y = math.floor(80 * scale_y),
                            w = math.floor(310 * scale_x),
                            h = math.floor(30 * scale_y),
                            font_size = math.floor(16 * math.min(scale_x, scale_y)),
                            color = 0x888888,
                            align = airui.TEXT_ALIGN_CENTER
                        })
                        table.insert(device_list_popup_items, label)
                        return
                    end
                    
                    -- 显示每个设备
                    local y = math.floor(80 * scale_y)
                    for device_id, device_info in pairs(game_state.online_devices) do
                        if device_id ~= my_device_id then
                            local id_label = airui.label({
                                parent = device_list_main_container,
                                text = device_id,
                                x = math.floor(5 * scale_x),
                                y = y,
                                w = math.floor(190 * scale_x),
                                h = math.floor(35 * scale_y),
                                font_size = math.floor(12 * math.min(scale_x, scale_y)),
                                color = 0x333333,
                                align = airui.TEXT_ALIGN_LEFT
                            })
                            table.insert(device_list_popup_items, id_label)
                            
                            local btn = airui.button({
                                parent = device_list_main_container, text = "连接",
                                x = math.floor(200 * scale_x),
                                y = y,
                                w = math.floor(110 * scale_x),
                                h = math.floor(35 * scale_y),
                                font_size = math.floor(14 * math.min(scale_x, scale_y)),
                                text_color = 0xFFFFFF,
                                bg_color = 0x009933,
                                on_click = function()
                                    game_state.peer_device_id = device_id
                                    game_state.peer_connected = true
                                    
                                    if my_device_id < device_id then
                                        game_state.is_server = true
                                        game_state.my_position.x = SERVER_POS.x
                                        game_state.my_position.y = SERVER_POS.y
                                        game_state.peer_position.x = CLIENT_POS.x
                                        game_state.peer_position.y = CLIENT_POS.y
                                        if player_rect and player_rect.set_color then
                                            player_rect:set_color(0xFF0000)
                                        end
                                        if peer_rect and peer_rect.set_color then
                                            peer_rect:set_color(0x00FF00)
                                        end
                                    else
                                        game_state.is_server = false
                                        game_state.my_position.x = CLIENT_POS.x
                                        game_state.my_position.y = CLIENT_POS.y
                                        game_state.peer_position.x = SERVER_POS.x
                                        game_state.peer_position.y = SERVER_POS.y
                                        if player_rect and player_rect.set_color then
                                            player_rect:set_color(0x00FF00)
                                        end
                                        if peer_rect and peer_rect.set_color then
                                            peer_rect:set_color(0xFF0000)
                                        end
                                    end
                                    
                                    if my_id_label and my_id_label.set_text then
                                        my_id_label:set_text("自己: " .. my_device_id)
                                    end
                                    if peer_id_label and peer_id_label.set_text then
                                        peer_id_label:set_text("对方: " .. device_id)
                                    end
                                    
                                    update_my_position()
                                    update_peer_position()
                                    update_status("已连接到设备: " .. device_id:sub(1, 15))
                                    
                                    sys.taskInit(function()
                                        sys.wait(300)
                                        send_position_update()
                                    end)
                                    
                                    close_device_list_win()
                                end
                            })
                            table.insert(device_list_popup_items, btn)
                            
                            y = y + math.floor(40 * scale_y)
                        end
                    end
                end
            })
            
            -- 关闭按钮
            airui.button({
                parent = device_list_main_container,
                text = "关闭",
                x = math.floor(215 * scale_x),
                y = math.floor(440 * scale_y),
                w = math.floor(100 * scale_x),
                h = math.floor(35 * scale_y),
                font_size = math.floor(14 * math.min(scale_x, scale_y)),
                text_color = 0xFFFFFF,
                bg_color = 0xCC0000,
                on_click = function()
                    close_device_list_win()
                end
            })
            
            -- 初始显示设备列表
            sys.taskInit(function()
                sys.wait(100)
                -- 清空并重新添加设备列表
                for _, item in ipairs(device_list_popup_items) do
                    if item then
                        item:destroy()
                    end
                end
                device_list_popup_items = {}
                
                -- 显示在线设备数量
                local count = 0
                for _ in pairs(game_state.online_devices) do
                    count = count + 1
                end
                
                local count_label = airui.label({
                    parent = device_list_main_container,
                    text = "在线设备: " .. count .. " 个",
                    x = math.floor(5 * scale_x),
                    y = math.floor(50 * scale_y),
                    w = math.floor(310 * scale_x),
                    h = math.floor(25 * scale_y),
                    font_size = math.floor(14 * math.min(scale_x, scale_y)),
                    color = 0x0066CC,
                    align = airui.TEXT_ALIGN_CENTER
                })
                table.insert(device_list_popup_items, count_label)
                
                if count == 0 then
                    local label = airui.label({
                        parent = device_list_main_container,
                        text = "暂无在线设备",
                        x = math.floor(5 * scale_x),
                        y = math.floor(80 * scale_y),
                        w = math.floor(310 * scale_x),
                        h = math.floor(30 * scale_y),
                        font_size = math.floor(16 * math.min(scale_x, scale_y)),
                        color = 0x888888,
                        align = airui.TEXT_ALIGN_CENTER
                    })
                    table.insert(device_list_popup_items, label)
                    return
                end
                
                -- 显示每个设备
                local y = math.floor(80 * scale_y)
                for device_id, device_info in pairs(game_state.online_devices) do
                    if device_id ~= my_device_id then
                        local id_label = airui.label({
                            parent = device_list_main_container,
                            text = device_id,
                            x = math.floor(5 * scale_x),
                            y = y,
                            w = math.floor(190 * scale_x),
                            h = math.floor(35 * scale_y),
                            font_size = math.floor(12 * math.min(scale_x, scale_y)),
                            color = 0x333333,
                            align = airui.TEXT_ALIGN_LEFT
                        })
                        table.insert(device_list_popup_items, id_label)
                        
                        local btn = airui.button({
                            parent = device_list_main_container,
                            text = "连接",
                            x = math.floor(200 * scale_x),
                            y = y,
                            w = math.floor(110 * scale_x),
                            h = math.floor(35 * scale_y),
                            font_size = math.floor(14 * math.min(scale_x, scale_y)),
                            text_color = 0xFFFFFF,
                            bg_color = 0x009933,
                            on_click = function()
                                game_state.peer_device_id = device_id
                                game_state.peer_connected = true
                                
                                if my_device_id < device_id then
                                    game_state.is_server = true
                                    game_state.my_position.x = SERVER_POS.x
                                    game_state.my_position.y = SERVER_POS.y
                                    game_state.peer_position.x = CLIENT_POS.x
                                    game_state.peer_position.y = CLIENT_POS.y
                                    if player_rect and player_rect.set_color then
                                        player_rect:set_color(0xFF0000)
                                    end
                                    if peer_rect and peer_rect.set_color then
                                        peer_rect:set_color(0x00FF00)
                                    end
                                else
                                    game_state.is_server = false
                                    game_state.my_position.x = CLIENT_POS.x
                                    game_state.my_position.y = CLIENT_POS.y
                                    game_state.peer_position.x = SERVER_POS.x
                                    game_state.peer_position.y = SERVER_POS.y
                                    if player_rect and player_rect.set_color then
                                        player_rect:set_color(0x00FF00)
                                    end
                                    if peer_rect and peer_rect.set_color then
                                        peer_rect:set_color(0xFF0000)
                                    end
                                end
                                
                                if my_id_label and my_id_label.set_text then
                                    my_id_label:set_text("自己: " .. my_device_id)
                                end
                                if my_id_label and my_id_label.set_color then
                                    if game_state.is_server then
                                        my_id_label:set_color(0xFF0000)  -- server是红色
                                    else
                                        my_id_label:set_color(0x00FF00)  -- client是绿色
                                    end
                                end
                                if peer_id_label and peer_id_label.set_text then
                                    peer_id_label:set_text("对方: " .. device_id)
                                end
                                if peer_id_label and peer_id_label.set_color then
                                    if game_state.is_server then
                                        peer_id_label:set_color(0x00FF00)  -- server的对方是绿色
                                    else
                                        peer_id_label:set_color(0xFF0000)  -- client的对方是红色
                                    end
                                end
                                
                                update_my_position()
                                update_peer_position()
                                update_status("已连接到设备: " .. device_id:sub(1, 15))
                                
                                sys.taskInit(function()
                                    sys.wait(300)
                                    send_position_update()
                                end)
                                
                                close_device_list_win()
                            end
                        })
                        table.insert(device_list_popup_items, btn)
                        
                        y = y + math.floor(40 * scale_y)
                    end
                end
            end)
        end,
        on_destroy = function()
            log.info("battle", "设备列表窗口销毁")
            for _, item in ipairs(device_list_popup_items) do
                if item then
                    item:destroy()
                end
            end
            device_list_popup_items = {}
            if device_list_main_container then
                device_list_main_container:destroy()
                device_list_main_container = nil
            end
            device_list_win_id = nil
        end,
    })
end

-- 更新设备列表UI（现在只更新弹窗，主页面不显示设备列表）
local function update_device_list()
    -- 如果设备列表弹窗是打开的，才更新弹窗中的列表
    if device_list_win_id then
        sys.taskInit(function()
            sys.wait(50)
            -- 清空并重新添加设备列表
            for _, item in ipairs(device_list_popup_items) do
                if item then
                    item:destroy()
                end
            end
            device_list_popup_items = {}
            
            -- 显示在线设备数量
            local count = 0
            for _ in pairs(game_state.online_devices) do
                count = count + 1
            end
            
            local count_label = airui.label({
                parent = device_list_main_container,
                text = "在线设备: " .. count .. " 个",
                x = math.floor(5 * scale_x),
                y = math.floor(50 * scale_y),
                w = math.floor(310 * scale_x),
                h = math.floor(25 * scale_y),
                font_size = math.floor(14 * math.min(scale_x, scale_y)),
                color = 0x0066CC,
                align = airui.TEXT_ALIGN_CENTER
            })
            table.insert(device_list_popup_items, count_label)
            
            if count == 0 then
                local label = airui.label({
                    parent = device_list_main_container,
                    text = "暂无在线设备",
                    x = math.floor(5 * scale_x),
                    y = math.floor(80 * scale_y),
                    w = math.floor(310 * scale_x),
                    h = math.floor(30 * scale_y),
                    font_size = math.floor(16 * math.min(scale_x, scale_y)),
                    color = 0x888888,
                    align = airui.TEXT_ALIGN_CENTER
                })
                table.insert(device_list_popup_items, label)
            else
                -- 显示每个设备
                local y = math.floor(80 * scale_y)
                for device_id, device_info in pairs(game_state.online_devices) do
                    -- 跳过自己
                    if device_id ~= my_device_id then
                        -- 设备ID标签
                        local id_label = airui.label({
                            parent = device_list_main_container,
                            text = device_id:sub(1, 20),
                            x = math.floor(5 * scale_x),
                            y = y,
                            w = math.floor(190 * scale_x),
                            h = math.floor(35 * scale_y),
                            font_size = math.floor(12 * math.min(scale_x, scale_y)),
                            color = 0x333333,
                            align = airui.TEXT_ALIGN_LEFT
                        })
                        table.insert(device_list_popup_items, id_label)
                        
                        -- 连接按钮
                        local btn = airui.button({
                            parent = device_list_main_container,
                            text = "连接",
                            x = math.floor(200 * scale_x),
                            y = y,
                            w = math.floor(110 * scale_x),
                            h = math.floor(35 * scale_y),
                            font_size = math.floor(14 * math.min(scale_x, scale_y)),
                            text_color = 0xFFFFFF,
                            bg_color = 0x009933,
                            on_click = function()
                                game_state.peer_device_id = device_id
                                game_state.peer_connected = true
                                
                                if my_device_id < device_id then
                                    game_state.is_server = true
                                    game_state.my_position.x = SERVER_POS.x
                                    game_state.my_position.y = SERVER_POS.y
                                    game_state.peer_position.x = CLIENT_POS.x
                                    game_state.peer_position.y = CLIENT_POS.y
                                    if player_rect and player_rect.set_color then
                                        player_rect:set_color(0xFF0000)
                                    end
                                    if peer_rect and peer_rect.set_color then
                                        peer_rect:set_color(0x00FF00)
                                    end
                                else
                                    game_state.is_server = false
                                    game_state.my_position.x = CLIENT_POS.x
                                    game_state.my_position.y = CLIENT_POS.y
                                    game_state.peer_position.x = SERVER_POS.x
                                    game_state.peer_position.y = SERVER_POS.y
                                    if player_rect and player_rect.set_color then
                                        player_rect:set_color(0x00FF00)
                                    end
                                    if peer_rect and peer_rect.set_color then
                                        peer_rect:set_color(0xFF0000)
                                    end
                                end
                                
                                if my_id_label and my_id_label.set_text then
                                    my_id_label:set_text("自己: " .. my_device_id)
                                end
                                if my_id_label and my_id_label.set_color then
                                    if game_state.is_server then
                                        my_id_label:set_color(0xFF0000)  -- server是红色
                                    else
                                        my_id_label:set_color(0x00FF00)  -- client是绿色
                                    end
                                end
                                if peer_id_label and peer_id_label.set_text then
                                    peer_id_label:set_text("对方: " .. device_id)
                                end
                                if peer_id_label and peer_id_label.set_color then
                                    if game_state.is_server then
                                        peer_id_label:set_color(0x00FF00)  -- server的对方是绿色
                                    else
                                        peer_id_label:set_color(0xFF0000)  -- client的对方是红色
                                    end
                                end
                                
                                update_my_position()
                                update_peer_position()
                                update_status("已连接到设备: " .. device_id:sub(1, 15))
                                
                                sys.taskInit(function()
                                    sys.wait(300)
                                    send_position_update()
                                end)
                                
                                close_device_list_win()
                            end
                        })
                        table.insert(device_list_popup_items, btn)
                        
                        y = y + math.floor(40 * scale_y)
                    end
                end
            end
        end)
    end
end

-- 处理接收到的消息
local function handle_message(topic, payload)
    if not game_state.is_running then 
        return 
    end
    
    local success, data = pcall(json.decode, payload)
    if not success or not data then
        return
    end
    
    -- 忽略自己的消息
    if data.device_id == my_device_id then
        return
    end
    
    if data.type == "presence" then
        -- 添加到在线设备列表
        if not game_state.online_devices[data.device_id] then
            game_state.online_devices[data.device_id] = {}
        end
        local ms_h, ms_l = mcu.ticks2(1)
        game_state.online_devices[data.device_id].last_seen = ms_h * 1000000 + ms_l
        game_state.online_devices[data.device_id].is_server = data.is_server
        
        -- 更新设备列表UI
        update_device_list()
        
        -- 如果设备列表弹窗是打开的，也更新一下弹窗中的列表
        if device_list_win_id then
            sys.taskInit(function()
                sys.wait(50)
                -- 清空并重新添加设备列表
                for _, item in ipairs(device_list_popup_items) do
                    if item then
                        item:destroy()
                    end
                end
                device_list_popup_items = {}
                
                -- 显示在线设备数量
                local count = 0
                for _ in pairs(game_state.online_devices) do
                    count = count + 1
                end
                
                local count_label = airui.label({
                    parent = device_list_main_container,
                    text = "在线设备: " .. count .. " 个",
                    x = 5,
                    y = 50,
                    w = 310,
                    h = 25,
                    font_size = 14,
                    color = 0x0066CC,
                    align = airui.TEXT_ALIGN_CENTER
                })
                table.insert(device_list_popup_items, count_label)
                
                if count == 0 then
                    local label = airui.label({
                        parent = device_list_main_container,
                        text = "暂无在线设备",
                        x = math.floor(5 * scale_x),
                        y = math.floor(80 * scale_y),
                        w = math.floor(310 * scale_x),
                        h = math.floor(30 * scale_y),
                        font_size = math.floor(16 * math.min(scale_x, scale_y)),
                        color = 0x888888,
                        align = airui.TEXT_ALIGN_CENTER
                    })
                    table.insert(device_list_popup_items, label)
                    return
                end
                
                -- 显示每个设备
                local y = math.floor(80 * scale_y)
                for device_id, device_info in pairs(game_state.online_devices) do
                    if device_id ~= my_device_id then
                        local id_label = airui.label({
                            parent = device_list_main_container,
                            text = device_id,
                            x = math.floor(5 * scale_x),
                            y = y,
                            w = math.floor(190 * scale_x),
                            h = math.floor(35 * scale_y),
                            font_size = math.floor(12 * math.min(scale_x, scale_y)),
                            color = 0x333333,
                            align = airui.TEXT_ALIGN_LEFT
                        })
                        table.insert(device_list_popup_items, id_label)
                        
                        local btn = airui.button({
                            parent = device_list_main_container,
                            text = "连接",
                            x = math.floor(200 * scale_x),
                            y = y,
                            w = math.floor(110 * scale_x),
                            h = math.floor(35 * scale_y),
                            font_size = math.floor(14 * math.min(scale_x, scale_y)),
                            text_color = 0xFFFFFF,
                            bg_color = 0x009933,
                            on_click = function()
                                game_state.peer_device_id = device_id
                                game_state.peer_connected = true
                                
                                if my_device_id < device_id then
                                    game_state.is_server = true
                                    game_state.my_position.x = SERVER_POS.x
                                    game_state.my_position.y = SERVER_POS.y
                                    game_state.peer_position.x = CLIENT_POS.x
                                    game_state.peer_position.y = CLIENT_POS.y
                                    if player_rect and player_rect.set_color then
                                        player_rect:set_color(0xFF0000)
                                    end
                                    if peer_rect and peer_rect.set_color then
                                        peer_rect:set_color(0x00FF00)
                                    end
                                else
                                    game_state.is_server = false
                                    game_state.my_position.x = CLIENT_POS.x
                                    game_state.my_position.y = CLIENT_POS.y
                                    game_state.peer_position.x = SERVER_POS.x
                                    game_state.peer_position.y = SERVER_POS.y
                                    if player_rect and player_rect.set_color then
                                        player_rect:set_color(0x00FF00)
                                    end
                                    if peer_rect and peer_rect.set_color then
                                        peer_rect:set_color(0xFF0000)
                                    end
                                end
                                
                                if my_id_label and my_id_label.set_text then
                                    my_id_label:set_text("自己: " .. my_device_id)
                                end
                                if my_id_label and my_id_label.set_color then
                                    if game_state.is_server then
                                        my_id_label:set_color(0xFF0000)  -- server是红色
                                    else
                                        my_id_label:set_color(0x00FF00)  -- client是绿色
                                    end
                                end
                                if peer_id_label and peer_id_label.set_text then
                                    peer_id_label:set_text("对方: " .. device_id)
                                end
                                if peer_id_label and peer_id_label.set_color then
                                    if game_state.is_server then
                                        peer_id_label:set_color(0x00FF00)  -- server的对方是绿色
                                    else
                                        peer_id_label:set_color(0xFF0000)  -- client的对方是红色
                                    end
                                end
                                
                                update_my_position()
                                update_peer_position()
                                update_status("已连接到设备: " .. device_id:sub(1, 15))
                                
                                sys.taskInit(function()
                                    sys.wait(300)
                                    send_position_update()
                                end)
                                
                                close_device_list_win()
                            end
                        })
                        table.insert(device_list_popup_items, btn)
                        
                        y = y + math.floor(40 * scale_y)
                    end
                end
            end)
        end
        
        -- 如果已经连接到这个设备，不需要再回复了
        if game_state.peer_device_id == data.device_id and game_state.peer_connected then
            return
        end
        
    elseif data.type == "position" and data.device_id == game_state.peer_device_id then
        game_state.peer_position.x = data.x
        game_state.peer_position.y = data.y
        update_peer_position()
        
    elseif data.type == "ping" and data.device_id == game_state.peer_device_id then
        send_pong(data.timestamp)
        
    elseif data.type == "pong" and data.device_id == game_state.peer_device_id then
        local ms_h, ms_l = mcu.ticks2(1)
        local recv_time = ms_h * 1000000 + ms_l
        local send_time = tonumber(data.timestamp)
        -- log.info("battle_ping", "recv_pong", "recv_time=" .. tostring(recv_time), "raw_timestamp=" .. tostring(data.timestamp))
        if send_time then
            local latency = recv_time - send_time
            -- log.info("battle_ping", "latency_calc", "send_time=" .. tostring(send_time), "recv_time=" .. tostring(recv_time), "latency=" .. tostring(latency))
            record_latency(latency)
        else
            log.warn("battle_ping", "latency_calc", "invalid send_time", tostring(data.timestamp))
        end
    end
end

-- 切换延迟测试
local function toggle_latency_test()
    if not game_state.is_running then 
        return 
    end
    game_state.is_testing = not game_state.is_testing
    
    if game_state.is_testing then
        if test_btn and test_btn.set_text then
            test_btn:set_text("停止延迟测试")
        end
        update_status("开始延迟测试...")
        sys.taskInit(function()
            while game_state.is_running and game_state.is_testing and game_state.peer_connected do
                send_ping()
                sys.wait(1000)
            end
        end)
    else
        if test_btn and test_btn.set_text then
            test_btn:set_text("开始延迟测试")
        end
        update_status("停止延迟测试")
    end
end

-- 断开连接
local function disconnect()
    if not game_state.is_running then 
        return 
    end
    
    game_state.peer_connected = false
    game_state.peer_device_id = nil
    game_state.latency_list = {}
    game_state.test_count = 0
    game_state.my_position.x = 30
    game_state.my_position.y = 130
    game_state.peer_position.x = 230
    game_state.peer_position.y = 130
    
    if peer_id_label and peer_id_label.set_text then
        peer_id_label:set_text("对方: 等待连接...")
    end
    if peer_id_label and peer_id_label.set_color then
        peer_id_label:set_color(0x888888)  -- 改回灰色
    end
    if my_id_label and my_id_label.set_color then
        my_id_label:set_color(0x333333)  -- 改回灰色
    end
    if latency_label and latency_label.set_text then
        latency_label:set_text("延迟: --")
    end
    if test_btn and test_btn.set_text then
        test_btn:set_text("开始延迟测试")
    end
    game_state.is_testing = false
    
    update_my_position()
    update_peer_position()
    update_status("已断开连接")
    
    -- 更新设备列表
    update_device_list()
end

-- 关闭窗口
local function close_battle_window()
    if win_id then
        exwin.close(win_id)
    end
end

-- MQTT事件回调函数
local function mqtt_client_event_cbfunc(mqtt_client, event, data, payload, metas)
    if not game_state.is_running then return end
    
    -- log.info("mqtt_client_event_cbfunc", event, data)

    if event == "conack" then
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "CONNECT", true)
        
        if not mqtt_client:subscribe(TOPIC_PRESENCE, MQTT_QOS) then
            sys.sendMsg(TASK_NAME, "MQTT_EVENT", "SUBSCRIBE", false, -1)
        end
        
        if not mqtt_client:subscribe(TOPIC_DATA .. my_device_id, MQTT_QOS) then
            sys.sendMsg(TASK_NAME, "MQTT_EVENT", "SUBSCRIBE", false, -1)
        end

    elseif event == "suback" then
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "SUBSCRIBE", data, payload)

    elseif event == "unsuback" then
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "UNSUBSCRIBE", true)

    elseif event == "recv" then
        handle_message(data, payload)

    elseif event == "sent" then

    elseif event == "disconnect" then
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "DISCONNECTED", false)

    elseif event == "pong" then

    elseif event == "error" then
        if data == "connect" or data == "conack" then
            sys.sendMsg(TASK_NAME, "MQTT_EVENT", "CONNECT", false)
        elseif data == "other" or data == "tx" then
            sys.sendMsg(TASK_NAME, "MQTT_EVENT", "ERROR")
        end
    end
end

-- MQTT主任务
local function mqtt_client_main_task_func()
    local mqtt_client
    local result, msg

    while game_state.is_running do
        while game_state.is_running and not socket.adapter(socket.dft()) do
            log.warn("battle", "等待网络...")
            update_status("等待网络连接...")
            sys.waitUntil("IP_READY", 1000)
        end
        
        if not game_state.is_running then break end
        
        update_status("正在连接MQTT...")
        
        sys.cleanMsg(TASK_NAME)
        
        mqtt_client = mqtt.create(nil, MQTT_SERVER, MQTT_PORT)
        if not mqtt_client then
            log.error("battle", "mqtt.create失败")
            update_status("MQTT创建失败")
            sys.wait(5000)
            goto EXCEPTION_PROC
        end
        
        result = mqtt_client:auth(TASK_NAME..my_device_id, "", "", true)
        if not result then
            log.error("battle", "mqtt_client:auth失败")
            goto EXCEPTION_PROC
        end
        
        mqtt_client:on(mqtt_client_event_cbfunc)
        mqtt_client:keepalive(60)
        
        result = mqtt_client:connect()
        if not result then
            log.error("battle", "mqtt_client:connect失败")
            goto EXCEPTION_PROC
        end
        
        game_state.mqtt_client = mqtt_client
        
        while game_state.is_running do
            msg = sys.waitMsg(TASK_NAME, "MQTT_EVENT")
            if not msg then
                break
            end
            
            log.info("battle waitMsg", msg[2], msg[3])

            if msg[2] == "CONNECT" then
                if msg[3] then
                    log.info("battle", "MQTT连接成功")
                    update_status("MQTT已连接")
                else
                    log.info("battle", "MQTT连接失败")
                    break
                end

            elseif msg[2] == "SUBSCRIBE" then
                if msg[3] then
                    log.info("battle", "订阅成功")
                    
                    if not game_state.mqtt_ready then
                        game_state.mqtt_ready = true
                        
                        sys.taskInit(function()
                            sys.wait(1000)
                            if game_state.is_running and game_state.mqtt_ready and not (game_state.peer_connected and game_state.peer_device_id) then
                                send_presence()
                            end
                        end)
                        
                        sys.taskInit(function()
                            while game_state.is_running do
                                sys.wait(10000) -- 10秒广播一次
                                if game_state.is_running and game_state.mqtt_ready and not (game_state.peer_connected and game_state.peer_device_id) then
                                    send_presence()
                                end
                            end
                        end)
                    end
                else
                    log.error("battle", "订阅失败", "code", msg[4])
                    mqtt_client:disconnect()
                    sys.wait(1000)
                    break
                end

            elseif msg[2] == "UNSUBSCRIBE" then
                log.info("battle", "取消订阅成功")

            elseif msg[2] == "DISCONNECTED" then
                log.warn("battle", "MQTT连接断开")
                break

            elseif msg[2] == "ERROR" then
                log.error("battle", "MQTT异常")
                break
            end
        end

        ::EXCEPTION_PROC::

        sys.cleanMsg(TASK_NAME)
        
        game_state.mqtt_ready = false
        
        if mqtt_client then
            mqtt_client:close()
            mqtt_client = nil
        end
        game_state.mqtt_client = nil
        
        if game_state.is_running then
            update_status("MQTT连接断开，等待重连...")
            sys.wait(5000)
        end
    end
end

-- 创建游戏窗口
local function on_create()
    log.info("battle", "on_create被调用")
    
    -- 刷新屏幕尺寸
    refresh_display()
    
    main_container = airui.container({
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = 0xFFFFFF,
        parent = airui.screen
    })
    
    airui.button({
        parent = main_container,
        text = "返回",
        x = math.floor(5 * scale_x),
        y = math.floor(5 * scale_y),
        w = math.floor(45 * scale_x),
        h = math.floor(25 * scale_y),
        font_size = math.floor(12 * math.min(scale_x, scale_y)),
        text_color = 0xFFFFFF,
        bg_color = 0x38bdf8,
        on_click = function()
            close_battle_window()
        end
    })
    
    airui.label({
        parent = main_container,
        text = "双人对战测试",
        x = math.floor(100 * scale_x),
        y = math.floor(5 * scale_y),
        w = math.floor(120 * scale_x),
        h = math.floor(30 * scale_y),
        font_size = math.floor(16 * math.min(scale_x, scale_y)),
        color = 0x333333,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    status_label = airui.label({
        parent = main_container,
        text = "等待网络连接...",
        x = math.floor(5 * scale_x),
        y = math.floor(35 * scale_y),
        w = math.floor(310 * scale_x),
        h = math.floor(20 * scale_y),
        font_size = math.floor(11 * math.min(scale_x, scale_y)),
        color = 0x009933,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    latency_label = airui.label({
        parent = main_container,
        text = "延迟: --",
        x = math.floor(5 * scale_x),
        y = math.floor(55 * scale_y),
        w = math.floor(310 * scale_x),
        h = math.floor(20 * scale_y),
        font_size = math.floor(11 * math.min(scale_x, scale_y)),
        color = 0xFF9900,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 游戏区域背景
    airui.container({
        parent = main_container,
        x = math.floor(5 * scale_x),
        y = math.floor(75 * scale_y),
        w = math.floor(310 * scale_x),
        h = math.floor(150 * scale_y),
        color = 0xEFEFEF
    })
    
    -- 创建玩家矩形
    local px, py = scale_pos(game_state.my_position.x, game_state.my_position.y)
    player_rect = airui.container({
        parent = main_container,
        x = px,
        y = py,
        w = math.floor(30 * scale_x),
        h = math.floor(30 * scale_y),
        color = 0x00FF00
    })
    
    -- 创建对方矩形
    local peer_x, peer_y = scale_pos(game_state.peer_position.x, game_state.peer_position.y)
    peer_rect = airui.container({
        parent = main_container,
        x = peer_x,
        y = peer_y,
        w = math.floor(30 * scale_x),
        h = math.floor(30 * scale_y),
        color = 0xFF0000
    })
    
    my_id_label = airui.label({
        parent = main_container,
        text = "自己: " .. my_device_id,
        x = math.floor(5 * scale_x),
        y = math.floor(250 * scale_y),
        w = math.floor(310 * scale_x),
        h = math.floor(16 * scale_y),
        font_size = math.floor(10 * math.min(scale_x, scale_y)),
        color = 0x333333,  -- 默认灰色
        align = airui.TEXT_ALIGN_LEFT
    })
    
    peer_id_label = airui.label({
        parent = main_container,
        text = "对方: 等待连接...",
        x = math.floor(5 * scale_x),
        y = math.floor(268 * scale_y),
        w = math.floor(310 * scale_x),
        h = math.floor(16 * scale_y),
        font_size = math.floor(10 * math.min(scale_x, scale_y)),
        color = 0x888888,  -- 默认灰色
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 断开连接按钮
    airui.button({
        parent = main_container,
        text = "断开",
        x = math.floor(5 * scale_x),
        y = math.floor(288 * scale_y),
        w = math.floor(60 * scale_x),
        h = math.floor(25 * scale_y),
        font_size = math.floor(11 * math.min(scale_x, scale_y)),
        text_color = 0xFFFFFF,
        bg_color = 0xCC0000,
        on_click = function()
            disconnect()
        end
    })
    
    -- 查看更多设备按钮
    airui.button({
        parent = main_container,
        text = "查看设备",
        x = math.floor(120 * scale_x),
        y = math.floor(288 * scale_y),
        w = math.floor(180 * scale_x),
        h = math.floor(25 * scale_y),
        font_size = math.floor(12 * math.min(scale_x, scale_y)),
        text_color = 0xFFFFFF,
        bg_color = 0x0099CC,
        on_click = function()
            open_device_list_win()
        end
    })
    
    -- -- 添加提示标签
    -- airui.label({
    --     parent = main_container,
    --     text = "连接后直接拖拽色块移动",
    --     x = math.floor(5 * scale_x),
    --     y = math.floor(320 * scale_y),
    --     w = math.floor(310 * scale_x),
    --     h = math.floor(20 * scale_y),
    --     font_size = math.floor(12 * math.min(scale_x, scale_y)),
    --     color = 0x888888,
    --     align = airui.TEXT_ALIGN_CENTER
    -- })
    
    -- 方向控制按钮
    local btn_w = math.floor(45 * scale_x)
    local btn_h = math.floor(35 * scale_y)
    local btn_y = math.floor(370 * scale_y)
    local center_x = math.floor(160 * scale_x)
    
    airui.button({
        parent = main_container,
        text = "上",
        x = math.floor(center_x - btn_w/2),
        y = math.floor(btn_y - 45 * scale_y),
        w = btn_w,
        h = btn_h,
        font_size = math.floor(14 * math.min(scale_x, scale_y)),
        text_color = 0xFFFFFF,
        bg_color = 0x666666,
        on_click = function()
            move_player(0, -20)
            send_position_update()
        end
    })
    
    airui.button({
        parent = main_container,
        text = "下",
        x = math.floor(center_x - btn_w/2),
        y = math.floor(btn_y + 5 * scale_y),
        w = btn_w,
        h = btn_h,
        font_size = math.floor(14 * math.min(scale_x, scale_y)),
        text_color = 0xFFFFFF,
        bg_color = 0x666666,
        on_click = function()
            move_player(0, 20)
            send_position_update()
        end
    })
    
    airui.button({
        parent = main_container,
        text = "左",
        x = math.floor(center_x - btn_w - 50 * scale_x),
        y = math.floor(btn_y - 18 * scale_y),
        w = btn_w,
        h = btn_h,
        font_size = math.floor(14 * math.min(scale_x, scale_y)),
        text_color = 0xFFFFFF,
        bg_color = 0x666666,
        on_click = function()
            move_player(-20, 0)
            send_position_update()
        end
    })
    
    airui.button({
        parent = main_container,
        text = "右",
        x = math.floor(center_x + 50 * scale_x),
        y = math.floor(btn_y - 18 * scale_y),
        w = btn_w,
        h = btn_h,
        font_size = math.floor(14 * math.min(scale_x, scale_y)),
        text_color = 0xFFFFFF,
        bg_color = 0x666666,
        on_click = function()
            move_player(20, 0)
            send_position_update()
        end
    })
    
    -- 测试按钮
    test_btn = airui.button({
        parent = main_container,
        text = "开始延迟测试",
        x = math.floor(5 * scale_x),
        y = math.floor(430 * scale_y),
        w = math.floor(310 * scale_x),
        h = math.floor(30 * scale_y),
        font_size = math.floor(13 * math.min(scale_x, scale_y)),
        text_color = 0xFFFFFF,
        bg_color = 0x0066CC,
        on_click = function()
            toggle_latency_test()
        end
    })
    
    -- 注册触摸订阅
    register_touch_handler()
end

local function on_destroy()
    log.info("battle_win", "窗口销毁")
    
    game_state.is_running = false
    game_state.is_testing = false
    game_state.mqtt_ready = false
    game_state.peer_connected = false
    game_state.peer_device_id = nil
    -- 清空在线设备列表
    game_state.online_devices = {}
    
    sys.cleanMsg(TASK_NAME)
    
    if game_state.mqtt_client then
        game_state.mqtt_client:on(nil)
        game_state.mqtt_client:close()
        game_state.mqtt_client = nil
    end
    
    -- 取消触摸订阅
    if airui and airui.touch_unsubscribe then
        airui.touch_unsubscribe()
    end
    
    -- 重置触摸状态
    reset_touch_state()
    
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    
    win_id = nil
    
    -- 清空UI引用
    status_label = nil
    latency_label = nil
    test_btn = nil
    player_rect = nil
    peer_rect = nil
    my_id_label = nil
    peer_id_label = nil
    device_list_items = {}
end

local function open_handler()
    if win_id then
        return
    end
    
    log.info("battle", "打开窗口")
    
    game_state.is_running = true
    game_state.peer_device_id = nil
    game_state.peer_connected = false
    game_state.mqtt_ready = false
    game_state.latency_list = {}
    game_state.test_count = 0
    game_state.my_position.x = 30
    game_state.my_position.y = 130
    game_state.peer_position.x = 230
    game_state.peer_position.y = 130
    game_state.online_devices = {}
    
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
    })
    
    sys.taskInitEx(mqtt_client_main_task_func, TASK_NAME)
end

sys.subscribe("OPEN_BATTLE_WIN", open_handler)
