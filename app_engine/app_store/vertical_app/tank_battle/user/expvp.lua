--[[
@module  expvp
@summary 通用PVP联网对战游戏框架（MQTT通信 + IOT数据存储 + 房间/匹配系统）
@version 1.0.1
@date    2026.05.22
@author  王世豪
@description
    通用PVP联网对战游戏框架，提供：
    1. MQTT网络连接管理（可配置）
    2. 房间系统（创建/加入/离开/列表）
    3. 匹配系统（自动匹配对手）
    4. 玩家状态管理（准备/在线状态）
    5. 游戏数据同步（状态/动作转发）
    6. IOT积分数据存储（排行榜）
    
    使用示例：
    local expvp = require("expvp")
    expvp.init({
        game_name = "stick_fighter",    -- 游戏名称，用于topic前缀
        score_cls = 2,                   -- 积分分类ID
        callbacks = {
            on_connect = function() end,
            on_disconnect = function() end,
            on_peer_join = function(peer_id, peer_info) end,    -- 有玩家加入
            on_peer_leave = function(peer_id) end,              -- 有玩家离开
            on_peer_ready = function(peer_id, ready) end,       -- 玩家准备状态变化
            on_game_start = function() end,                     -- 游戏开始
            on_game_started = function(data) end,               -- 收到游戏开始通知（含房主分配的玩家信息）
            on_game_data = function(data, from_peer) end,       -- 收到游戏数据
        }
    })
    expvp.start()
]]

local expvp = {}

-- ==================== 默认配置 ====================

local DEFAULT_CONFIG = {
    mqtt_server = "lbsmqtt.airm2m.com",
    mqtt_port = 1884,
    mqtt_qos = 0,
    game_name = "game",
    score_cls = 1,
    room_max_players = 2,           -- 房间最大人数（默认2人对战）
    match_timeout = 30000,          -- 匹配超时时间（毫秒）
}

-- ==================== 状态 ====================

local config = {}                   -- 当前配置
local state = {
    mqtt_client = nil,
    mqtt_ready = false,
    is_running = false,
    device_id = nil,
    device_model = nil,
    nickname = nil,
}

-- 房间状态
local room_state = {
    current_room = nil,             -- 当前房间ID
    room_code = nil,                -- 房间简短代码（6位数字）
    is_host = false,                -- 是否是房主
    players = {},                   -- 房间内的玩家 {device_id -> player_info}
    my_ready = false,               -- 自己是否准备
    game_started = false,           -- 游戏是否已开始
}

-- 匹配状态
local match_state = {
    is_matching = false,            -- 是否正在匹配
    match_timer = nil,              -- 匹配超时定时器
    broadcast_timer = nil,          -- 匹配广播定时器（周期性发请求）
    matched_peers = {},             -- 已处理的匹配请求（防重复）
}

-- 游戏状态
local game_state = {
    is_playing = false,             -- 是否游戏中
    peer_device_id = nil,           -- 对手设备ID
    last_ping_time = 0,             -- 上次收到ping时间
}

-- 回调函数
local callbacks = {}

-- ==================== 工具函数 ====================

-- 获取设备ID
local function get_device_id()
    if mobile and mobile.imei then
        return mobile.imei()
    elseif wlan and wlan.getMac then
        return wlan.getMac()
    end
    return "DEV_" .. tostring(os.time())
end

-- 获取设备型号
local function get_device_model()
    if hmeta and hmeta.model then
        local m = hmeta.model()
        if m then return m end
    end
    return "PC"
end

-- 获取昵称
local function get_nickname()
    if exapp then
        local ok, info = pcall(exapp.iot_get_account_info)
        if ok and info and info.nickname and #info.nickname > 0 then
            return info.nickname
        end
    end
    return state.device_id:sub(-6)
end

-- 生成Topic名称
local function make_topic(name)
    return config.game_name .. "/" .. name
end

-- 生成房间Topic
local function make_room_topic(room_id, name)
    return config.game_name .. "/room/" .. room_id .. "/" .. name
end

-- ==================== 初始化 ====================

--[[
@api expvp.init(user_config)
@summary 初始化网络框架，配置游戏参数和回调函数
@param user_config table 配置对象
    - game_name string 游戏名称，用于MQTT topic前缀（默认"game"）
    - score_cls number 积分分类ID，用于排行榜（默认1）
    - mqtt_server string MQTT服务器地址（默认"lbsmqtt.airm2m.com"）
    - mqtt_port number MQTT端口（默认1884）
    - mqtt_qos number MQTT QoS等级（默认0）
    - room_max_players number 房间最大人数（默认2）
    - match_timeout number 匹配超时时间（毫秒，默认30000）
    - callbacks table 回调函数集合
@return string 设备ID
@example
    expvp.init({
        game_name = "stick_fighter",
        score_cls = 2,
        callbacks = {
            on_connect = function() end,
            on_game_data = function(data, from) end,
        }
    })
]]
function expvp.init(user_config)
    -- 合并配置
    config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        config[k] = v
    end
    if user_config then
        for k, v in pairs(user_config) do
            config[k] = v
        end
    end
    
    -- 设置回调
    callbacks = config.callbacks or {}
    
    -- 初始化设备信息
    state.device_id = get_device_id()
    state.device_model = get_device_model()
    state.nickname = get_nickname()
    
    log.info('expvp', 'init', config.game_name)
    log.info('expvp', 'device_id', state.device_id)
    log.info('expvp', 'device_model', state.device_model)
    
    return state.device_id
end

-- ==================== 设备信息 ====================

--[[
@api expvp.get_device_id()
@summary 获取当前设备唯一标识
@return string 设备ID（IMEI或MAC地址）
]]
function expvp.get_device_id()
    return state.device_id
end

--[[
@api expvp.get_device_model()
@summary 获取设备型号
@return string 设备型号
]]
function expvp.get_device_model()
    return state.device_model
end

--[[
@api expvp.get_nickname()
@summary 获取玩家昵称
@return string 玩家昵称（优先使用IOT账号昵称，否则使用设备ID后6位）
]]
function expvp.get_nickname()
    return state.nickname
end

--[[
@api expvp.get_account_info()
@summary 获取IOT账号信息
@return table|nil 账号信息表（包含account、nickname、is_guest等字段），未登录或异常时返回nil
]]
function expvp.get_account_info()
    if not exapp then return nil end
    local ok, info = pcall(exapp.iot_get_account_info)
    if ok and info then return info end
    return nil
end

-- ==================== MQTT状态 ====================

--[[
@api expvp.is_ready()
@summary 检查MQTT是否已连接并就绪
@return boolean 是否就绪
]]
function expvp.is_ready()
    return state.mqtt_ready
end

--[[
@api expvp.is_running()
@summary 检查网络服务是否正在运行
@return boolean 是否运行中
]]
function expvp.is_running()
    return state.is_running
end

-- ==================== 消息发送 ====================

-- 【内部】发送消息到指定MQTT topic（自动JSON编码）
-- 仅供模块内部使用，业务代码请使用 send_to_device / broadcast_to_room / send_game_data
local function publish(topic, data)
    if not state.mqtt_ready or not state.mqtt_client then
        return false
    end
    return state.mqtt_client:publish(topic, json.encode(data), config.mqtt_qos)
end

--[[
@api expvp.send_to_device(device_id, data)
@summary 发送消息到指定设备（点对点）
@param device_id string 目标设备ID
@param data table 要发送的数据
@return boolean 是否发送成功
]]
function expvp.send_to_device(device_id, data)
    return publish(make_topic("data/" .. device_id), data)
end

--[[
@api expvp.send_presence(data)
@summary 广播在线状态（用于设备发现和邀请）
@param data table|nil 在线状态数据（可选，会被自动添加 device_id、nickname、model 等字段）
@return boolean 是否发送成功
@note 用于"设备列表"模式的联机，让其他设备发现自己
@example
    expvp.send_presence({is_connected = false, is_matching = true})
]]
function expvp.send_presence(data)
    local payload = data or {}
    payload.device_id = state.device_id
    payload.nickname = state.nickname
    payload.model = state.device_model
    payload.timestamp = os.time()
    return publish(make_topic("presence"), payload)
end

--[[
@api expvp.broadcast_to_room(data)
@summary 广播消息到当前房间内所有人（需要先加入房间）
@param data table 要广播的数据
@return boolean 是否发送成功
]]
function expvp.broadcast_to_room(data)
    if not room_state.current_room then return false end
    return publish(make_room_topic(room_state.current_room, "broadcast"), data)
end



-- ==================== 房间系统 ====================

--[[
@api expvp.create_room(callback)
@summary 创建新房间并成为房主
@param callback function|nil 回调函数 function(success, room_id)
@return string 房间ID
@note 创建后会自动订阅房间topic并广播创建事件
]]
function expvp.create_room(callback)
    -- 生成简短易读的房间代码（6位数字）
    local room_code = "room_" .. tostring(os.time()):sub(-6)
    local room_id = room_code
    room_state.current_room = room_id
    room_state.room_code = room_code
    room_state.is_host = true
    room_state.players = {}
    room_state.my_ready = false
    
    -- 订阅房间相关topic
    if state.mqtt_client then
        state.mqtt_client:subscribe(make_room_topic(room_id, "#"), config.mqtt_qos)
    end
    
    -- 发送创建房间广播
    publish(make_topic("presence"), {
        type = "room_created",
        device_id = state.device_id,
        room_id = room_id,
        nickname = state.nickname,
        model = state.device_model,
    })
    
    log.info('expvp', 'room created', room_id)
    if callback then callback(true, room_id) end
    return room_id
end

--[[
@api expvp.join_room(room_id, callback)
@summary 加入指定房间
@param room_id string 要加入的房间ID
@param callback function|nil 回调函数 function(success)
@note 加入后会自动订阅房间topic并发送加入请求
]]
function expvp.join_room(room_id, callback)
    room_state.current_room = room_id
    room_state.is_host = false
    room_state.players = {}
    room_state.my_ready = false
    
    -- 订阅房间相关topic
    if state.mqtt_client then
        state.mqtt_client:subscribe(make_room_topic(room_id, "#"), config.mqtt_qos)
    end
    
    -- 发送加入请求
    publish(make_room_topic(room_id, "join"), {
        type = "join_request",
        device_id = state.device_id,
        nickname = state.nickname,
        model = state.device_model,
    })
    
    log.info('expvp', 'joining room', room_id)
    if callback then callback(true) end
end

--[[
@api expvp.leave_room(callback)
@summary 离开当前房间
@param callback function|nil 回调函数 function(success)
@note 会通知其他玩家并清理房间状态
]]
function expvp.leave_room(callback)
    if not room_state.current_room then
        if callback then callback(false) end
        return
    end
    
    -- 发送离开通知
    publish(make_room_topic(room_state.current_room, "leave"), {
        type = "leave",
        device_id = state.device_id,
    })
    
    -- 取消订阅
    if state.mqtt_client then
        state.mqtt_client:unsubscribe(make_room_topic(room_state.current_room, "#"))
    end
    
    log.info('expvp', 'left room', room_state.current_room)
    room_state.current_room = nil
    room_state.room_code = nil
    room_state.is_host = false
    room_state.players = {}
    room_state.my_ready = false
    room_state.game_started = false
    
    if callback then callback(true) end
end

--[[
@api expvp.get_room_info()
@summary 获取当前房间信息
@return table 房间信息表
    - room_id string 房间ID
    - is_host boolean 是否为房主
    - players table 房间内玩家列表
    - my_ready boolean 自己是否准备
]]
function expvp.get_room_info()
    return {
        room_id = room_state.current_room,
        room_code = room_state.room_code,
        is_host = room_state.is_host,
        players = room_state.players,
        my_ready = room_state.my_ready,
        game_started = room_state.game_started,
    }
end

--[[
@api expvp.get_room_code()
@summary 获取房间简短代码（用于分享和加入）
@return string|nil 6位数字代码
]]
function expvp.get_room_code()
    return room_state.room_code
end

--[[
@api expvp.is_host()
@summary 检查当前设备是否为房主
@return boolean 是否为房主
]]
function expvp.is_host()
    return room_state.is_host
end

--[[
@api expvp.get_player_count()
@summary 获取房间内玩家数量（含自己）
@return number 玩家数量
]]
function expvp.get_player_count()
    local count = 1  -- 自己
    for _, _ in pairs(room_state.players) do
        count = count + 1
    end
    return count
end

--[[
@api expvp.set_ready(ready, callback)
@summary 设置自己的准备状态
@param ready boolean 是否准备
@param callback function|nil 回调函数 function(success)
@note 所有玩家都准备后，房主会触发on_game_start回调
]]
function expvp.set_ready(ready, callback)
    room_state.my_ready = ready
    if room_state.current_room then
        publish(make_room_topic(room_state.current_room, "ready"), {
            type = "ready",
            device_id = state.device_id,
            ready = ready,
        })
    end
    if callback then callback(true) end
end

--[[
@api expvp.is_all_ready()
@summary 检查房间内所有玩家是否都已准备（含房主自己）
@return boolean 是否全部准备
@note 房主调用start_game前用于检查条件
]]
function expvp.is_all_ready()
    if not room_state.my_ready then return false end
    local player_count = 0
    for _, player in pairs(room_state.players) do
        player_count = player_count + 1
        if not player.ready then
            return false
        end
    end
    return player_count >= 1  -- 至少有1个其他玩家
end

--[[
@api expvp.start_game(player_assignments)
@summary 房主开始游戏，广播游戏开始通知给房间内所有玩家
@param player_assignments table|nil 玩家编号分配表 {[device_id] = player_number}（可选，自动分配时可不传）
@note
    - 只有房主可以调用
    - 需要先加入房间
    - 会触发所有玩家的on_game_started和on_game_start回调
]]
function expvp.start_game(player_assignments)
    if not room_state.is_host then
        log.warn('expvp', '只有房主可以开始游戏')
        return false
    end
    if not room_state.current_room then
        log.warn('expvp', '未加入房间')
        return false
    end
    
    -- 自动分配玩家编号（如果未提供）
    local assignments = player_assignments or {}
    if not next(assignments) then
        -- 按加入顺序分配：房主=P1，其他按顺序P2/P3/P4
        local num = 2
        assignments[state.device_id] = 1
        for device_id, _ in pairs(room_state.players) do
            if device_id ~= state.device_id and num <= config.room_max_players then
                assignments[device_id] = num
                num = num + 1
            end
        end
    end
    
    local start_data = {
        type = "game_start",
        room_id = room_state.current_room,
        host_id = state.device_id,
        player_assignments = assignments,
        timestamp = os.time(),
    }
    
    -- 广播到房间
    publish(make_room_topic(room_state.current_room, "broadcast"), start_data)
    
    -- 房主自己也触发回调
    room_state.game_started = true
    if callbacks.on_game_started then
        callbacks.on_game_started(start_data)
    end
    if callbacks.on_game_start then
        callbacks.on_game_start()
    end
    
    log.info('expvp', 'game started by host', room_state.current_room)
    return true
end

-- ==================== 匹配系统 ====================

--[[
@api expvp.start_match(callback)
@summary 开始自动匹配对手
@param callback function|nil 回调函数 function(success, result)
    - success=true 匹配成功
    - success=false, result="timeout" 匹配超时
    - success=false, result="already matching" 已在匹配中
@note 匹配超时时间通过config.match_timeout配置（默认30秒）
]]
function expvp.start_match(callback)
    if match_state.is_matching then
        if callback then callback(false, "already matching") end
        return
    end
    
    match_state.is_matching = true
    match_state.matched_peers = {}
    match_state.match_callback = callback
    
    -- 超时定时器（30秒）
    match_state.match_timer = sys.timerStart(function()
        expvp.stop_match()
        if callback then callback(false, "timeout") end
    end, config.match_timeout)
    
    -- 周期性广播匹配请求（每2秒发一次，增加被发现几率）
    local function broadcastMatchRequest()
        if not match_state.is_matching then return end
        publish(make_topic("match"), {
            type = "match_request",
            device_id = state.device_id,
            nickname = state.nickname,
            model = state.device_model,
            timestamp = os.time(),
        })
        -- 同时也发到presence topic，让设备列表也能看到匹配状态
        publish(make_topic("presence"), {
            type = "presence",
            device_id = state.device_id,
            nickname = state.nickname,
            model = state.device_model,
            matching = true,
            timestamp = os.time(),
        })
    end
    
    -- 立即发一次
    broadcastMatchRequest()
    -- 然后每2秒重发
    match_state.broadcast_timer = sys.timerLoopStart(broadcastMatchRequest, 2000)
    
    log.info('expvp', 'start matching')
end

--[[
@api expvp.stop_match()
@summary 停止匹配（用户取消匹配时调用）
]]
function expvp.stop_match()
    if match_state.match_timer then
        sys.timerStop(match_state.match_timer)
        match_state.match_timer = nil
    end
    if match_state.broadcast_timer then
        sys.timerStop(match_state.broadcast_timer)
        match_state.broadcast_timer = nil
    end
    match_state.is_matching = false
    match_state.matched_peers = {}
    log.info('expvp', 'stop matching')
end

--[[
@api expvp.is_matching()
@summary 检查是否正在匹配中
@return boolean 是否正在匹配
]]
function expvp.is_matching()
    return match_state.is_matching
end

-- ==================== 游戏数据同步 ====================

--[[
@api expvp.set_game_playing(playing, peer_id)
@summary 设置游戏状态和对手设备ID
@param playing boolean 是否游戏中
@param peer_id string|nil 对手设备ID（游戏开始时传入）
@note 设置对手ID后，可以使用 send_to_device(peer_id, {...}) 发送游戏数据
@example
    expvp.set_game_playing(true, opponent_id)
    expvp.send_to_device(opponent_id, {action = "move", x = 100, y = 200})
]]
function expvp.set_game_playing(playing, peer_id)
    game_state.is_playing = playing
    game_state.peer_device_id = peer_id
    game_state.last_ping_time = os.time()
end

--[[
@api expvp.is_peer_online()
@summary 检查对手是否在线
@return boolean 对手是否在线（10秒内收到过消息视为在线）
]]
function expvp.is_peer_online()
    if not game_state.peer_device_id then return false end
    return (os.time() - game_state.last_ping_time) < 10  -- 10秒内收到过消息算在线
end

-- ==================== 消息处理 ====================

local function handle_room_message(topic, data)
    if not room_state.current_room then return end
    
    -- 处理加入请求
    if data.type == "join_request" and room_state.is_host then
        if data.device_id ~= state.device_id then
            -- 检查房间是否已满
            local current_count = 0
            for _, _ in pairs(room_state.players) do
                current_count = current_count + 1
            end
            if current_count >= config.room_max_players then
                -- 房间已满，拒绝加入
                publish(make_room_topic(room_state.current_room, "join_ack"), {
                    type = "join_ack",
                    to = data.device_id,
                    room_id = room_state.current_room,
                    host_id = state.device_id,
                    rejected = true,
                    reason = "房间已满",
                })
                return
            end
            room_state.players[data.device_id] = {
                device_id = data.device_id,
                nickname = data.nickname,
                model = data.model,
                ready = false,
            }
            -- 回复加入确认
            publish(make_room_topic(room_state.current_room, "join_ack"), {
                type = "join_ack",
                to = data.device_id,
                room_id = room_state.current_room,
                host_id = state.device_id,
                players = room_state.players,
            })
            if callbacks.on_peer_join then
                callbacks.on_peer_join(data.device_id, data)
            end
        end
    end
    
    -- 处理加入确认
    if data.type == "join_ack" and data.to == state.device_id then
        if data.rejected then
            -- 被拒绝加入
            log.warn('expvp', '加入房间被拒绝:', data.reason or '未知原因')
            if callbacks.on_join_rejected then
                callbacks.on_join_rejected(data.reason or '房间已满')
            end
            room_state.current_room = nil
            return
        end
        room_state.players = data.players or {}
        room_state.players[data.host_id] = {
            device_id = data.host_id,
            is_host = true,
        }
    end
    
    -- 处理离开
    if data.type == "leave" then
        room_state.players[data.device_id] = nil
        if callbacks.on_peer_leave then
            callbacks.on_peer_leave(data.device_id)
        end
    end
    
    -- 处理准备状态
    if data.type == "ready" then
        if room_state.players[data.device_id] then
            room_state.players[data.device_id].ready = data.ready
        end
        if callbacks.on_peer_ready then
            callbacks.on_peer_ready(data.device_id, data.ready)
        end
    end
    
    -- 处理游戏开始（房主广播）
    if data.type == "game_start" then
        room_state.game_started = true
        if callbacks.on_game_started then
            callbacks.on_game_started(data)
        end
        if callbacks.on_game_start then
            callbacks.on_game_start()
        end
    end
    
    -- 处理游戏数据
    if data.type == "game_data" and callbacks.on_game_data then
        callbacks.on_game_data(data.data, data.from)
        return
    end
    
    -- 处理通用广播消息（如 input、game_state 等）
    if callbacks.on_message then
        callbacks.on_message(data)
    end
end

local function handle_match_message(data)
    if not match_state.is_matching then return end
    if not data.device_id or data.device_id == state.device_id then return end

    -- 处理来自 match 或 presence 的匹配请求
    local is_match_request = (data.type == "match_request") or
                             (data.type == "presence" and data.matching == true)

    if is_match_request then
        -- 防止重复匹配同一设备
        if match_state.matched_peers[data.device_id] then return end
        match_state.matched_peers[data.device_id] = true

        -- 找到匹配，停止匹配
        expvp.stop_match()
        -- 通知对方匹配成功（发到 match 主题，对方才能收到）
        publish(make_topic("match"), {
            type = "match_accept",
            device_id = state.device_id,
            nickname = state.nickname,
            model = state.device_model,
            target_id = data.device_id,  -- 指定匹配的对方
        })
        -- 通知回调
        if callbacks.on_match_found then
            callbacks.on_match_found(data.device_id, data)
        end
        return
    end

    -- 处理 match_accept（来自对方匹配成功的确认）
    if data.type == "match_accept" then
        -- 只处理目标是自己的匹配接受消息
        if data.target_id and data.target_id ~= state.device_id then return end

        if match_state.matched_peers[data.device_id] then return end
        match_state.matched_peers[data.device_id] = true
        expvp.stop_match()
        if callbacks.on_match_found then
            callbacks.on_match_found(data.device_id, data)
        end
    end
end

local function handle_message(topic, payload)
    local ok, data = pcall(json.decode, payload)
    if not ok or not data then return end
    
    -- 更新ping时间
    if data.device_id and data.device_id ~= state.device_id then
        game_state.last_ping_time = os.time()
    end
    
    -- 处理房间消息
    if room_state.current_room and topic:find("/room/" .. room_state.current_room) then
        handle_room_message(topic, data)
        return
    end
    
    -- 处理匹配消息
    if topic:find("/match") then
        handle_match_message(data)
        return
    end
    
    -- 处理点对点消息
    if topic:find("/data/" .. state.device_id) then
        if data.type == "game_data" and callbacks.on_game_data then
            callbacks.on_game_data(data.data, data.from or data.device_id)
        elseif data.type == "ping" then
            -- 自动回复pong
            expvp.send_to_device(data.device_id, {
                type = "pong",
                device_id = state.device_id,
            })
        elseif callbacks.on_message then
            callbacks.on_message(data)
        end
        return
    end
    
    -- 处理在线广播
    if topic:find("/presence") then
        -- 如果对方也在匹配，同时走匹配流程
        if data.matching == true and data.device_id ~= state.device_id then
            handle_match_message(data)
        end
        if callbacks.on_presence then
            callbacks.on_presence(data)
        end
        return
    end
    
    if callbacks.on_message then
        callbacks.on_message(data)
    end
end

-- ==================== MQTT任务 ====================

local function mqtt_client_event_cbfunc(mqtt_client, event, data, payload, metas)
    if not state.is_running then return end
    
    if event == 'conack' then
        -- 订阅必要的topic
        mqtt_client:subscribe(make_topic("presence"), config.mqtt_qos)
        mqtt_client:subscribe(make_topic("match"), config.mqtt_qos)
        mqtt_client:subscribe(make_topic("data/" .. state.device_id), config.mqtt_qos)
        sys.sendMsg(config.game_name .. "_mqtt", 'MQTT_EVENT', 'CONNECT', true)
    elseif event == 'suback' then
        state.mqtt_ready = true
        if callbacks.on_connect then
            callbacks.on_connect()
        end
        sys.sendMsg(config.game_name .. "_mqtt", 'MQTT_EVENT', 'SUBSCRIBE', true)
    elseif event == 'recv' then
        handle_message(data, payload)
    elseif event == 'disconnect' then
        state.mqtt_ready = false
        if callbacks.on_disconnect then
            callbacks.on_disconnect()
        end
        sys.sendMsg(config.game_name .. "_mqtt", 'MQTT_EVENT', 'DISCONNECTED')
    elseif event == 'error' then
        if callbacks.on_error then
            callbacks.on_error()
        end
        sys.sendMsg(config.game_name .. "_mqtt", 'MQTT_EVENT', 'ERROR')
    end
end

local function mqtt_client_main_task_func()
    while state.is_running do
        while state.is_running and not socket.adapter(socket.dft()) do
            sys.waitUntil('IP_READY', 1000)
        end
        if not state.is_running then break end
        
        sys.cleanMsg(config.game_name .. "_mqtt")
        
        local mqtt_client = mqtt.create(nil, config.mqtt_server, config.mqtt_port)
        if mqtt_client then
            local success = true
            
            if not mqtt_client:auth(config.game_name .. "_" .. state.device_id, '', '', true) then
                success = false
            end
            
            if success then
                mqtt_client:on(mqtt_client_event_cbfunc)
                mqtt_client:keepalive(60)
                
                if mqtt_client:connect() then
                    state.mqtt_client = mqtt_client
                    
                    while state.is_running do
                        local msg = sys.waitMsg(config.game_name .. "_mqtt", 'MQTT_EVENT')
                        if not msg then break end
                        if msg[2] == 'CONNECT' and not msg[3] then
                            break
                        elseif msg[2] == 'SUBSCRIBE' and not msg[3] then
                            mqtt_client:disconnect()
                            sys.wait(1000)
                            break
                        elseif msg[2] == 'DISCONNECTED' or msg[2] == 'ERROR' then
                            break
                        end
                    end
                else
                    success = false
                end
            end
            
            state.mqtt_ready = false
            mqtt_client:close()
            state.mqtt_client = nil
        end
        
        if state.is_running then
            sys.wait(3000)
        end
    end
end

-- ==================== 生命周期 ====================

--[[
@api expvp.start()
@summary 启动网络服务，开始连接MQTT服务器
@note 必须在expvp.init之后调用，会启动一个独立的MQTT任务
]]
function expvp.start()
    state.is_running = true
    sys.taskInitEx(mqtt_client_main_task_func, config.game_name .. "_mqtt")
end

--[[
@api expvp.stop()
@summary 停止网络服务，断开MQTT连接
@note 应用退出时务必调用此API释放资源
]]
function expvp.stop()
    state.is_running = false
    if state.mqtt_client then
        state.mqtt_client:close()
        state.mqtt_client = nil
    end
end

-- ==================== 积分系统 ====================

local score_state = {
    local_score = 0,
    just_deleted = false,
    is_uploading = false,
}

--[[
@api expvp.get_local_score()
@summary 获取本地累计积分（尚未上传到服务器的积分）
@return number 本地积分值
]]
function expvp.get_local_score()
    return score_state.local_score
end

--[[
@api expvp.set_local_score(score)
@summary 直接设置本地积分（一般用于初始化或重置）
@param score number 积分值
@return number 设置后的积分值
]]
function expvp.set_local_score(score)
    score_state.local_score = score or 0
    return score_state.local_score
end

--[[
@api expvp.add_score(delta)
@summary 增加本地积分（游戏过程中获得积分时调用）
@param delta number 要增加的积分值（可以为负数）
@return number 增加后的总积分
]]
function expvp.add_score(delta)
    score_state.local_score = score_state.local_score + (delta or 0)
    log.info("score", "add:", delta, "total:", score_state.local_score)
    return score_state.local_score
end

--[[
@api expvp.reset_score()
@summary 重置本地积分为0
]]
function expvp.reset_score()
    score_state.local_score = 0
    score_state.just_deleted = false
end

--[[
@api expvp.upload_score(callback)
@summary 上传本地积分到服务器（自动累加服务器历史积分）
@param callback function|nil 回调函数 function(success, total_score)
@note
    - 需要用户已登录IOT账号（非访客模式）
    - 本地积分为0时不会上传
    - 上传成功后本地积分自动清零
    - 如果之前调用过mark_deleted/delete_score，则不叠加历史积分
]]
function expvp.upload_score(callback)
    log.info("score", "【upload】start, local:", score_state.local_score)

    if score_state.local_score == 0 then
        log.info("score", "【upload】score is 0, skip")
        if callback then callback(true, 0) end
        return
    end

    if not exapp then
        log.warn("score", "【upload】exapp not available")
        if callback then callback(false, 0) end
        return
    end

    local ok, info = pcall(exapp.iot_get_account_info)
    if not ok or not info or info.is_guest then
        log.warn("score", "【upload】not logged in or guest mode")
        if callback then callback(false, 0) end
        return
    end

    local account = info.account or "unknown"
    local nickname = info.nickname or "unknown"
    local local_score = score_state.local_score

    if score_state.is_uploading then
        log.warn("score", "【upload】already uploading")
        if callback then callback(false, 0) end
        return
    end

    score_state.is_uploading = true
    log.info("score", "【upload】account:", account, "local:", local_score)

    exapp.list_record({
        cls = config.score_cls,
        size = 1,
        filter = {
            aks = {"uni_key"},
            acs = {"eq"},
            avs = {account},
        },
    }, function(success, data)
        if success and data and data.value then
            data = data.value
        end

        local server_score = 0
        if success and data and data.records and #data.records > 0 then
            server_score = data.records[1].i1 or 0
        end

        local new_score = score_state.just_deleted and local_score or (server_score + local_score)
        log.info("score", "【upload】server:", server_score, "local:", local_score, "new:", new_score)

        exapp.add_record({
            cls = config.score_cls,
            uni_key = account,
            i1 = new_score,
            s1 = nickname,
        }, function(ok, result)
            score_state.is_uploading = false

            if ok then
                log.info("score", "【upload】success, total:", new_score)
                score_state.local_score = 0
                score_state.just_deleted = false
                if callback then callback(true, new_score) end
            else
                log.warn("score", "【upload】failed")
                if callback then callback(false, server_score) end
            end
        end)
    end)
end

--[[
@api expvp.query_total_score(callback)
@summary 查询当前账号在服务器上的总积分
@param callback function 回调函数 function(success, total_score)
@note 需要用户已登录IOT账号
]]
function expvp.query_total_score(callback)
    if not exapp then
        if callback then callback(false, 0) end
        return
    end

    local ok, info = pcall(exapp.iot_get_account_info)
    if not ok or not info or info.is_guest then
        if callback then callback(false, 0) end
        return
    end

    local account = info.account or "unknown"

    exapp.list_record({
        cls = config.score_cls,
        size = 1,
        filter = {
            aks = {"uni_key"},
            acs = {"eq"},
            avs = {account},
        },
    }, function(success, data)
        if success and data and data.value then
            data = data.value
        end

        if success and data and data.records and #data.records > 0 then
            local total = data.records[1].i1 or 0
            if callback then callback(true, total) end
        else
            if callback then callback(false, 0) end
        end
    end)
end

--[[
@api expvp.delete_score(callback)
@summary 删除当前账号在服务器上的积分记录
@param callback function|nil 回调函数 function(success, deleted_count)
@note
    - 需要用户已登录IOT账号
    - 删除成功后会自动设置just_deleted标记，下次上传不会叠加
]]
function expvp.delete_score(callback)
    if not exapp then
        if callback then callback(false, 0) end
        return
    end

    local ok, info = pcall(exapp.iot_get_account_info)
    if not ok or not info then
        if callback then callback(false, 0) end
        return
    end

    local account = info.account or "unknown"

    exapp.list_record({
        cls = config.score_cls,
        filter = {
            aks = {"uni_key"},
            acs = {"eq"},
            avs = {account},
        },
    }, function(success, data)
        if success and data and data.value then
            data = data.value
        end

        if not success or not data or not data.records then
            if callback then callback(false, 0) end
            return
        end

        local deleted = 0
        for _, record in ipairs(data.records) do
            if record.uni_key == account then
                local ok = pcall(exapp.delete_record, {cls = config.score_cls, id = record.id})
                if ok then deleted = deleted + 1 end
            end
        end

        if deleted > 0 then
            score_state.just_deleted = true
        end

        if callback then callback(true, deleted) end
    end)
end

--[[
@api expvp.query_leaderboard(page, callback, size)
@summary 查询排行榜（按积分降序）
@param page number|nil 页码（默认1）
@param callback function 回调函数 function(success, data)
    - data.records 排行榜记录数组，每条记录包含 i1(积分)、s1(昵称)、uni_key(账号) 等字段
    - data.total 总记录数
@param size number|nil 每页条数（默认11）
@example
    expvp.query_leaderboard(1, function(success, data)
        if success and data.records then
            for i, rec in ipairs(data.records) do
                print(i, rec.s1, rec.i1)
            end
        end
    end, 30)
]]
function expvp.query_leaderboard(page, callback, size)
    page = page or 1
    size = size or 11

    if not exapp then
        if callback then callback(false, "exapp not available") end
        return
    end

    exapp.list_record({
        cls = config.score_cls,
        sort = "i1 desc",
        size = size,
        offset = (page - 1) * size,
    }, function(success, data)
        if success and data and data.value then
            data = data.value
        end
        if callback then
            callback(success, data)
        end
    end)
end

return expvp
