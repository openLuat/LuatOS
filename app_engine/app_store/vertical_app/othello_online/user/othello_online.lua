--[[
@module  othello_online
@summary 黑白棋联网对战模块
@version 1.0.0
@date    2026.06.04
]]

local M = {}

local exwin = exwin
if not exwin then
    exwin = require "exwin"
end

-- 游戏常量
local BLACK = 1
local WHITE = 2
local EMPTY = 0

-- 屏幕尺寸
local SCREEN_W = 480
local SCREEN_H = 800

-- 游戏状态
local STATE = {
    MENU = 'menu',
    WAITING = 'waiting',
    CONNECTING = 'connecting',
    PLAYING = 'playing',
    GAME_OVER = 'game_over'
}

local gameState = STATE.MENU

-- MQTT 配置
local MQTT_SERVER = "lbsmqtt.airm2m.com"
local MQTT_PORT = 1884
local MQTT_QOS = 0

local TOPIC_PRESENCE = "othello_online/presence"
local TOPIC_DATA = "othello_online/data/"

-- 游戏状态管理
local game_state_mqtt = {
    online_devices = {},
    peer_connected = false,
    peer_ready = false,
    i_am_ready = false,
    peer_device_id = nil,
    mqtt_client = nil,
    mqtt_ready = false,
    is_running = false,
    is_server = false,
    reconnect_count = 0,
    max_reconnect = 3,
    invite_timeout = nil,
    last_heartbeat = 0,
    heartbeat_interval = 5000,
    heartbeat_timer = nil,
    move_confirm_timer = nil,
    pending_move = nil,
    presence_timer = nil
}

-- UI 组件引用
local win_id = nil
local main_container = nil
local board = {}
local cells = {}
local current_player = 1
local black_count = 0
local white_count = 0
local black_label = nil
local white_label = nil
local turn_label = nil
local my_id_label = nil
local status_label = nil

-- 玩家颜色
local player_color = BLACK
local computer_color = WHITE
local game_started = false

-- 设备 ID
local my_device_id = nil

local function get_device_id()
    local device_id = "DEV_UNKNOWN"
    if mobile and mobile.imei then
        device_id = mobile.imei()
    elseif wlan and wlan.getMac then
        device_id = wlan.getMac()
    else
        device_id = "DEV_" .. tostring(os.time())
    end
    return device_id
end

my_device_id = get_device_id()
log.info('device_id', my_device_id)

-- 方向数组
local DIRECTIONS = {
    {-1, -1}, {-1, 0}, {-1, 1},
    {0, -1},          {0, 1},
    {1, -1},  {1, 0},  {1, 1}
}

-- 颜色配置
local COLORS = {
    background = 0xE8E8E8,
    board_bg = 0x00A0A0,
    board_border = 0x2E7D32,
    cell_bg = 0x00A0A0,
    cell_selected = 0xffd000,
    cell_valid_move = 0x00ff00,
    black_piece = 0x1A1A1A,
    white_piece = 0xF5F5F5,
    button = 0x2E7D32,
    button_text = 0xFFFFFF,
    msg_text = 0x2E7D32,
    title_bg = 0x2E7D32,
    title_text = 0xFFFFFF,
}

-- 确保 MQTT 模块可用
local function ensure_mqtt()
    log.info("mqtt", "ensure_mqtt called, mqtt=", mqtt and "exists" or "nil")
    if not mqtt then
        log.error("mqtt", "mqtt module not available")
        return false
    end
    log.info("mqtt", "mqtt module is available")
    
    if not json then
        log.error("mqtt", "json module not available")
        return false
    end
    log.info("mqtt", "json module is available")
    
    log.info("mqtt", "ensure_mqtt completed successfully")
    return true
end

-- 初始化棋盘
local function init_board()
    for i = 1, 8 do
        board[i] = {0, 0, 0, 0, 0, 0, 0, 0}
    end
    board[4][4] = WHITE
    board[4][5] = BLACK
    board[5][4] = BLACK
    board[5][5] = WHITE
    current_player = BLACK
end

-- 前向声明
local update_device_list_display

-- 重置游戏
local function reset_game()
    init_board()
    count_pieces()
    update_board_ui_full()
    update_score_ui()
end

-- 统计棋子
local function count_pieces()
    black_count = 0
    white_count = 0
    for i = 1, 8 do
        for j = 1, 8 do
            if board[i][j] == BLACK then
                black_count = black_count + 1
            elseif board[i][j] == WHITE then
                white_count = white_count + 1
            end
        end
    end
end

-- 更新 UI
local function update_score_ui()
    black_label:set_text("黑：" .. black_count)
    white_label:set_text("白：" .. white_count)
    if current_player == player_color then
        turn_label:set_text("你的回合")
    else
        turn_label:set_text("对手回合")
    end
end

-- 更新棋盘 UI
local function update_board_ui_full()
    for i = 1, 8 do
        for j = 1, 8 do
            local cell = cells[i][j]
            if cell then
                local value = board[i][j]
                if value == BLACK then
                    cell:set_style({ bg_color = COLORS.black_piece })
                elseif value == WHITE then
                    cell:set_style({ bg_color = COLORS.white_piece })
                else
                    cell:set_style({ bg_color = COLORS.board_bg })
                end
            end
        end
    end
end

-- 检查是否是有效的移动
local function is_valid_move(row, col, player)
    if row < 1 or row > 8 or col < 1 or col > 8 then
        return false
    end
    if board[row][col] ~= EMPTY then
        return false
    end

    local opponent = (player == BLACK) and WHITE or BLACK

    for _, dir in ipairs(DIRECTIONS) do
        local dr, dc = dir[1], dir[2]
        local r, c = row + dr, col + dc
        local found_opponent = false

        while r >= 1 and r <= 8 and c >= 1 and c <= 8 do
            if board[r][c] == opponent then
                found_opponent = true
            elseif board[r][c] == player then
                if found_opponent then
                    return true
                end
                break
            else
                break
            end
            r = r + dr
            c = c + dc
        end
    end

    return false
end

-- 获取需要翻转的棋子
local function get_flipped(row, col, player)
    local flipped = {}
    local opponent = (player == BLACK) and WHITE or BLACK

    for _, dir in ipairs(DIRECTIONS) do
        local dr, dc = dir[1], dir[2]
        local r, c = row + dr, col + dc
        local dir_flipped = {}

        while r >= 1 and r <= 8 and c >= 1 and c <= 8 do
            if board[r][c] == opponent then
                table.insert(dir_flipped, {r, c})
            elseif board[r][c] == player then
                for _, pos in ipairs(dir_flipped) do
                    table.insert(flipped, pos)
                end
                break
            else
                break
            end
            r = r + dr
            c = c + dc
        end
    end

    return flipped
end

-- 执行移动
local function make_move(row, col, player, flipped)
    board[row][col] = player
    if flipped then
        for _, pos in ipairs(flipped) do
            board[pos[1]][pos[2]] = player
        end
    end
    return true
end

-- 检查是否有有效的移动
local function has_valid_move(player)
    for i = 1, 8 do
        for j = 1, 8 do
            if is_valid_move(i, j, player) then
                return true
            end
        end
    end
    return false
end

-- 检查游戏结束
local function check_game_over()
    local winner
    if black_count > white_count then
        winner = "黑棋胜利!"
    elseif white_count > black_count then
        winner = "白棋胜利!"
    else
        winner = "平局!"
    end
    
    local result_text = winner .. "\n黑:" .. black_count .. " 白:" .. white_count
    if not game_state_mqtt.peer_connected then
        result_text = result_text .. "\n点击重新开始"
    end
    
    airui.msgbox({
        title = "游戏结束",
        text = result_text,
        buttons = { "确定" },
        on_action = function(self, label)
            self:hide()
            self:destroy()
            -- 直接重新开始下一局游戏
            start_game()
        end
    }):show()
    game_started = false
end

-- 断开 MQTT 连接
local function disconnect_mqtt()
    stop_heartbeat()
    
    if game_state_mqtt.presence_timer then
        sys.timerStop(game_state_mqtt.presence_timer)
        game_state_mqtt.presence_timer = nil
    end
    
    if game_state_mqtt.move_confirm_timer then
        sys.timerStop(game_state_mqtt.move_confirm_timer)
        game_state_mqtt.move_confirm_timer = nil
    end
    
    if game_state_mqtt.mqtt_client then
        if game_state_mqtt.peer_connected and game_state_mqtt.peer_device_id then
            local leave_data = {
                type = "leave",
                device_id = my_device_id
            }
            local ok, json_str = pcall(json.encode, leave_data)
            if ok then
                game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
            end
        end
        
        local presence_data = {
            type = "presence",
            device_id = my_device_id,
            online = false,
            timestamp = os.time()
        }
        local ok, json_str = pcall(json.encode, presence_data)
        if ok then
            game_state_mqtt.mqtt_client:publish(TOPIC_PRESENCE, json_str, MQTT_QOS)
        end
        
        game_state_mqtt.mqtt_client:close()
        game_state_mqtt.mqtt_client = nil
        game_state_mqtt.mqtt_ready = false
        game_state_mqtt.peer_connected = false
        game_state_mqtt.peer_device_id = nil
        game_state_mqtt.online_devices = {}
        game_state_mqtt.pending_move = nil
    end
end

-- 心跳机制
function M.Start_heartbeat()
    log.info("mqtt", "starting heartbeat, interval=", game_state_mqtt.heartbeat_interval)
    if game_state_mqtt.heartbeat_timer then
        sys.timerStop(game_state_mqtt.heartbeat_timer)
    end
    
    game_state_mqtt.heartbeat_timer = sys.timerLoopStart(function()
        if game_state_mqtt.mqtt_ready and game_state_mqtt.peer_connected and game_state_mqtt.peer_device_id then
            local heartbeat_data = {
                type = "heartbeat",
                device_id = my_device_id,
                timestamp = os.time()
            }
            local ok, json_str = pcall(json.encode, heartbeat_data)
            if ok and game_state_mqtt.mqtt_client then
                game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
            end
        end
        
        -- 心跳超时检测条件要和发送条件一致，避免误判
        if game_state_mqtt.mqtt_ready and game_state_mqtt.peer_connected and game_state_mqtt.peer_device_id then
            local now = os.time()
            if game_state_mqtt.last_heartbeat > 0 and now - game_state_mqtt.last_heartbeat > 15 then
                log.warn("mqtt", "heartbeat timeout, peer disconnected")
                airui.msgbox({
                    title = "连接超时",
                    text = "与对手的连接已断开",
                    buttons = { "确定" },
                    on_action = function(self)
                        self:hide()
                        self:destroy()
                        create_main_menu()
                    end,
                }):show()
            end
        end
    end, game_state_mqtt.heartbeat_interval)
end

function stop_heartbeat()
    if game_state_mqtt.heartbeat_timer then
        sys.timerStop(game_state_mqtt.heartbeat_timer)
        game_state_mqtt.heartbeat_timer = nil
    end
end

-- 处理玩家点击
local function handle_cell_click(row, col)
    if gameState ~= STATE.PLAYING then return end
    if not game_started then return end
    if current_player ~= player_color then return end

    if not is_valid_move(row, col, player_color) then
        return
    end

    local flipped = get_flipped(row, col, player_color)
    make_move(row, col, player_color, flipped)
    count_pieces()
    update_board_ui_full()
    update_score_ui()

    -- 联网模式下发送移动
    if game_state_mqtt.peer_connected and game_state_mqtt.mqtt_client then
        local data = {
            type = "move",
            row = row,
            col = col,
            flipped = flipped,
            from_device = my_device_id
        }
        local ok, json_str = pcall(json.encode, data)
        if ok then
            game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
        end
        
        game_state_mqtt.pending_move = {
            row = row,
            col = col,
            flipped = flipped
        }
        
        if game_state_mqtt.move_confirm_timer then
            sys.timerStop(game_state_mqtt.move_confirm_timer)
        end
        game_state_mqtt.move_confirm_timer = sys.timerStart(function()
            if game_state_mqtt.pending_move then
                log.warn("mqtt", "move confirm timeout, resending")
                local data2 = {
                    type = "move",
                    row = game_state_mqtt.pending_move.row,
                    col = game_state_mqtt.pending_move.col,
                    flipped = game_state_mqtt.pending_move.flipped,
                    from_device = my_device_id
                }
                local ok2, json_str2 = pcall(json.encode, data2)
                if ok2 and game_state_mqtt.mqtt_client then
                    game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str2, MQTT_QOS)
                end
            end
        end, 5000)
    end

    -- 检查游戏状态
    local next_player = (player_color == BLACK) and WHITE or BLACK
    if not has_valid_move(next_player) and not has_valid_move(player_color) then
        check_game_over()
        return
    end

    if not has_valid_move(next_player) then
        -- 对手无法移动，继续我方
        current_player = player_color
        update_score_ui()
    else
        current_player = next_player
        update_score_ui()
    end
end

-- 创建游戏界面
local function create_game_screen()
    log.info("game", "create_game_screen called")
    if main_container then
        log.info("game", "destroying existing main_container")
        main_container:destroy()
        main_container = nil
    end

    log.info("game", "creating new main_container")
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = COLORS.background,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 80,
        color = COLORS.title_bg,
    })
    
    airui.label({
        parent = title_bar,
        x = 20,
        y = 20,
        w = 200,
        h = 40,
        text = "联网黑白棋",
        font_size = 38,
        color = COLORS.title_text,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 分数栏
    local score_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 90,
        w = SCREEN_W,
        h = 60,
        color = 0xFFFFFF,
    })

    black_label = airui.label({
        parent = score_bar,
        x = 20,
        y = 10,
        w = 150,
        h = 40,
        text = "黑：2",
        font_size = 38,
        color = COLORS.black_piece,
        align = airui.TEXT_ALIGN_LEFT,
    })

    turn_label = airui.label({
        parent = score_bar,
        x = 165,
        y = 10,
        w = 150,
        h = 40,
        text = "你的回合",
        font_size = 38,
        color = COLORS.msg_text,
        align = airui.TEXT_ALIGN_CENTER,
    })

    white_label = airui.label({
        parent = score_bar,
        x = 310,
        y = 10,
        w = 150,
        h = 40,
        text = "白：2",
        font_size = 38,
        color = COLORS.black_piece,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 棋盘
    local board_container = airui.container({
        parent = main_container,
        x = 10,
        y = 170,
        w = 460,
        h = 460,
        color = COLORS.board_border,
        radius = 8,
    })

    local cell_size = 55
    local gap = 3

    cells = {}
    for i = 1, 8 do
        cells[i] = {}
        for j = 1, 8 do
            local x = (j - 1) * (cell_size + gap)
            local y = (i - 1) * (cell_size + gap)
            local cell = airui.button({
                parent = board_container,
                x = x,
                y = y,
                w = cell_size,
                h = cell_size,
                text = "",
                style = {
                    bg_color = COLORS.board_bg,
                    border_width = 0,
                    radius = cell_size / 2,
                },
                on_click = function()
                    handle_cell_click(i, j)
                end
            })
            cells[i][j] = cell
        end
    end

    -- 底部按钮
    local bottom_bar = airui.container({
        parent = main_container,
        x = 0,
        y = SCREEN_H - 60,
        w = SCREEN_W,
        h = 60,
        color = 0xFFFFFF,
    })

    local btn_w = SCREEN_W / 2
    
    airui.button({
        parent = bottom_bar,
        x = 0,
        y = 0,
        w = btn_w,
        h = 60,
        text = "认输",
        font_size = 38,
        text_color = COLORS.button_text,
        bg_color = 0xF44336,
        radius = 0,
        on_click = function()
            airui.msgbox({
                title = "确认认输",
                text = "确定要认输吗？",
                buttons = { "确定", "取消" },
                on_action = function(self, label)
                    self:hide()
                    self:destroy()
                    if label == "确定" then
                        -- 发送认输消息给对手
                        local surrender_data = {
                            type = "surrender",
                            from_device = my_device_id,
                            target_device = game_state_mqtt.peer_device_id
                        }
                        local ok, json_str = pcall(json.encode, surrender_data)
                        if ok and game_state_mqtt.mqtt_client then
                            game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str, MQTT_QOS)
                        end
                        
                        airui.msgbox({
                            title = "已认输",
                            text = "你已认输，游戏结束",
                            buttons = { "确定" },
                            on_action = function(self)
                                self:hide()
                                self:destroy()
                                -- 直接开始下一局游戏
                                start_game()
                            end,
                        }):show()
                    end
                end,
            }):show()
        end,
    })

    airui.button({
        parent = bottom_bar,
        x = btn_w,
        y = 0,
        w = btn_w,
        h = 60,
        text = "退出",
        font_size = 38,
        text_color = COLORS.button_text,
        bg_color = 0xF44336,
        radius = 0,
        on_click = function()
            disconnect_mqtt()
            if exwin then
                exwin.close(win_id)
            end
        end,
    })

    -- 初始化游戏
    start_game()
end

-- 开始游戏
function start_game()
    init_board()
    count_pieces()
    update_board_ui_full()
    update_score_ui()
    game_started = true
    gameState = STATE.PLAYING
    
    -- 联网模式下确定颜色
    if game_state_mqtt.peer_connected then
        -- 服务器方为黑棋（先手）
        if game_state_mqtt.is_server then
            player_color = BLACK
            computer_color = WHITE
        else
            player_color = WHITE
            computer_color = BLACK
        end
        current_player = BLACK
        update_score_ui()
    end
end

-- 创建主菜单
function create_main_menu()
    gameState = STATE.MENU
    
    if main_container then
        main_container:destroy()
        main_container = nil
    end

    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = COLORS.background,
    })

    -- 标题
    airui.label({
        parent = main_container,
        x = 0,
        y = 80,
        w = SCREEN_W,
        h = 60,
        text = "黑白棋",
        font_size = 48,
        color = COLORS.msg_text,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 设备 ID 显示
    my_id_label = airui.label({
        parent = main_container,
        x = 0,
        y = 150,
        w = SCREEN_W,
        h = 30,
        text = "设备 ID: " .. my_device_id:sub(#my_device_id - 5),
        font_size = 38,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER,
    })

    local btn_w = 220
    local btn_h = 50
    local btn_x = (SCREEN_W - btn_w) / 2
    local btn_y = 220

    airui.label({
        parent = main_container,
        x = 0,
        y = 190,
        w = SCREEN_W,
        h = 30,
        text = "双人联网对战",
        font_size = 36,
        color = COLORS.msg_text,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.button({
        parent = main_container,
        x = btn_x,
        y = btn_y,
        w = btn_w,
        h = btn_h,
        text = "查找对手",
        font_size = 36,
        text_color = COLORS.button_text,
        bg_color = COLORS.button,
        radius = 8,
        on_click = function()
            log.info("ui", "查找对手按钮点击")
            if not ensure_mqtt() then
                log.error("ui", "MQTT 模块加载失败，无法联机对战")
                airui.msgbox({
                    title = "网络模块未加载",
                    text = "无法加载 MQTT 网络模块，无法进行联机对战",
                    buttons = { "确定" },
                    on_action = function(self)
                        self:hide()
                        self:destroy()
                    end,
                }):show()
                return
            end
            log.info("ui", "MQTT 模块已加载，显示设备列表")
            show_device_list()
        end,
    })

    airui.button({
        parent = main_container,
        x = btn_x,
        y = btn_y + 70,
        w = btn_w,
        h = btn_h,
        text = "人机对战",
        font_size = 36,
        text_color = COLORS.button_text,
        bg_color = COLORS.button,
        radius = 8,
        on_click = function()
            -- 切换到人机对战模式，先关闭当前窗口
            disconnect_mqtt()
            -- 直接调用函数打开人机对战窗口
            local game_win = require "game_othello_online_win"
            game_win.open_game_window()
            -- 延迟关闭当前窗口
            sys.timerStart(function()
                if exwin then
                    exwin.close(win_id)
                end
            end, 100)
        end,
    })

    airui.button({
        parent = main_container,
        x = btn_x,
        y = btn_y + 140,
        w = btn_w,
        h = btn_h,
        text = "退出应用",
        font_size = 36,
        text_color = COLORS.button_text,
        bg_color = 0xF44336,
        radius = 8,
        on_click = function()
            disconnect_mqtt()
            if exwin then
                exwin.close(win_id)
            end
        end,
    })
end

-- 显示等待界面
local function show_waiting_screen()
    gameState = STATE.WAITING
    
    if main_container then
        main_container:destroy()
        main_container = nil
    end

    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = COLORS.background,
    })

    connect_mqtt(function(success, err)
        if success then
            log.info("mqtt", "mqtt connected successfully")
            sys.timerStart(function()
                update_device_list()
            end, 1000)
        else
            log.error("mqtt", "connect failed:", err)
        end
    end)

    airui.label({
        parent = main_container,
        x = 0,
        y = 150,
        w = SCREEN_W,
        h = 40,
        text = "等待对手连接...",
        font_size = 38,
        color = COLORS.msg_text,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.label({
        parent = main_container,
        x = 0,
        y = 200,
        w = SCREEN_W,
        h = 30,
        text = "你的设备 ID:",
        font_size = 38,
        color = COLORS.msg_text,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.label({
        parent = main_container,
        x = 0,
        y = 230,
        w = SCREEN_W,
        h = 30,
        text = my_device_id,
        font_size = 36,
        color = COLORS.msg_text,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.button({
        parent = main_container,
        x = (SCREEN_W - 120) / 2,
        y = 350,
        w = 120,
        h = 40,
        text = "取消",
        font_size = 36,
        text_color = COLORS.button_text,
        bg_color = COLORS.button,
        radius = 6,
        on_click = function()
            disconnect_mqtt()
            create_main_menu()
        end,
    })
end

-- 显示连接中界面
local function show_connecting_screen(target_id)
    gameState = STATE.CONNECTING
    
    if main_container then
        main_container:destroy()
        main_container = nil
    end

    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = COLORS.background,
    })

    airui.label({
        parent = main_container,
        x = 0,
        y = 150,
        w = SCREEN_W,
        h = 40,
        text = "连接中...",
        font_size = 38,
        color = COLORS.msg_text,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.label({
        parent = main_container,
        x = 0,
        y = 200,
        w = SCREEN_W,
        h = 30,
        text = "目标设备 ID:",
        font_size = 38,
        color = COLORS.msg_text,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.label({
        parent = main_container,
        x = 0,
        y = 230,
        w = SCREEN_W,
        h = 30,
        text = target_id,
        font_size = 36,
        color = COLORS.msg_text,
        align = airui.TEXT_ALIGN_CENTER,
    })

    airui.button({
        parent = main_container,
        x = (SCREEN_W - 120) / 2,
        y = 350,
        w = 120,
        h = 40,
        text = "取消",
        font_size = 36,
        text_color = COLORS.button_text,
        bg_color = COLORS.button,
        radius = 6,
        on_click = function()
            disconnect_mqtt()
            create_main_menu()
        end,
    })
end

-- 更新设备列表
local function update_device_list()
    if not main_container then return end
    
    local device_ids = {}
    for id, _ in pairs(game_state_mqtt.online_devices) do
        if id ~= my_device_id then
            table.insert(device_ids, id)
        end
    end
    
    log.info("mqtt", "update_device_list: total devices=", #device_ids)
    
    show_device_list()
end

-- 显示设备列表
function show_device_list()
    -- 如果已经在游戏中，不要重新显示设备列表
    if game_state_mqtt.peer_connected then
        log.info("mqtt", "already in game, skipping show_device_list")
        return
    end
    
    if main_container then
        main_container:destroy()
        main_container = nil
    end

    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = COLORS.background,
    })

    connect_mqtt()

    airui.label({
        parent = main_container,
        x = 0,
        y = 10,
        w = SCREEN_W,
        h = 40,
        text = "选择对手",
        font_size = 38,
        color = COLORS.msg_text,
        align = airui.TEXT_ALIGN_CENTER,
    })

    local device_ids = {}
    for id, _ in pairs(game_state_mqtt.online_devices) do
        if id ~= my_device_id then
            table.insert(device_ids, id)
        end
    end

    airui.label({
        parent = main_container,
        x = 0,
        y = 55,
        w = SCREEN_W,
        h = 40,
        text = "在线设备：" .. #device_ids,
        font_size = 36,
        color = 0x0066ff,
        align = airui.TEXT_ALIGN_CENTER,
        name = "online_count",
    })

    local list_y = 110
    if #device_ids == 0 then
        airui.label({
            parent = main_container,
            x = 0,
            y = list_y,
            w = SCREEN_W,
            h = 40,
            text = "暂无在线设备",
            font_size = 38,
            color = 0x666666,
            align = airui.TEXT_ALIGN_CENTER,
        })
    else
        for i, id in ipairs(device_ids) do
            airui.label({
                parent = main_container,
                x = 20,
                y = list_y + (i - 1) * 50,
                w = SCREEN_W - 140,
                h = 45,
                text = id,
                font_size = 38,
                color = 0x000000,
                align = airui.TEXT_ALIGN_LEFT,
            })

            airui.button({
                parent = main_container,
                x = SCREEN_W - 110,
                y = list_y + (i - 1) * 50,
                w = 90,
                h = 35,
                text = "邀请",
                font_size = 36,
                text_color = COLORS.button_text,
                bg_color = COLORS.button,
                radius = 6,
                on_click = function()
                    if game_state_mqtt.peer_connected then
                        airui.msgbox({
                            title = "提示",
                            text = "已经有对手了",
                            buttons = { "确定" },
                        }):show()
                        return
                    end
                    Connect_to_peer(id)
                end,
            })
        end
    end

    local btn_w = 180
    local btn_h = 45

    airui.button({
        parent = main_container,
        x = 20,
        y = SCREEN_H - 60,
        w = btn_w,
        h = btn_h,
        text = "刷新",
        font_size = 36,
        text_color = COLORS.button_text,
        bg_color = COLORS.button,
        radius = 6,
        on_click = function()
            if game_state_mqtt.mqtt_client then
                local presence_data = {
                    type = "presence",
                    device_id = my_device_id,
                    is_server = game_state_mqtt.is_server
                }
                local ok, json_str = pcall(json.encode, presence_data)
                if ok then
                    log.info("mqtt", "publishing presence on refresh")
                    game_state_mqtt.mqtt_client:publish(TOPIC_PRESENCE, json_str, MQTT_QOS)
                end
            end
            -- 只更新设备列表，不重新创建整个界面
            update_device_list_display()
        end,
    })

    airui.button({
        parent = main_container,
        x = SCREEN_W - btn_w - 20,
        y = SCREEN_H - 60,
        w = btn_w,
        h = btn_h,
        text = "关闭",
        font_size = 36,
        text_color = COLORS.button_text,
        bg_color = COLORS.button,
        radius = 6,
        on_click = function()
            disconnect_mqtt()
            create_main_menu()
        end,
    })
end

-- 更新设备列表显示（不重新创建界面）
update_device_list_display = function()
    if not main_container then return end
    
    local device_ids = {}
    for id, _ in pairs(game_state_mqtt.online_devices) do
        if id ~= my_device_id then
            table.insert(device_ids, id)
        end
    end
    
    log.info("mqtt", "update_device_list_display: total devices=", #device_ids)
    
    -- 销毁现有列表项
    for _, child in ipairs(main_container.children) do
        if child.name and child.name:find("device_") then
            child:destroy()
        end
    end
    
    local list_y = 110
    if #device_ids == 0 then
        airui.label({
            parent = main_container,
            x = 0,
            y = list_y,
            w = SCREEN_W,
            h = 40,
            text = "暂无在线设备",
            font_size = 38,
            color = 0x666666,
            align = airui.TEXT_ALIGN_CENTER,
            name = "device_empty",
        })
    else
        for i, id in ipairs(device_ids) do
            airui.label({
                parent = main_container,
                x = 20,
                y = list_y + (i - 1) * 50,
                w = SCREEN_W - 140,
                h = 40,
                text = id,
                font_size = 38,
                color = 0x000000,
                align = airui.TEXT_ALIGN_LEFT,
                name = "device_label_" .. i,
            })

            airui.button({
                parent = main_container,
                x = SCREEN_W - 110,
                y = list_y + (i - 1) * 50,
                w = 90,
                h = 35,
                text = "邀请",
                font_size = 36,
                text_color = COLORS.button_text,
                bg_color = COLORS.button,
                radius = 6,
                name = "device_btn_" .. i,
                on_click = function()
                    if game_state_mqtt.peer_connected then
                        airui.msgbox({
                            title = "提示",
                            text = "已经有对手了",
                            buttons = { "确定" },
                        }):show()
                        return
                    end
                    Connect_to_peer(id)
                end,
            })
        end
    end
    
    -- 更新在线设备数量
    for _, child in ipairs(main_container.children) do
        if child.name == "online_count" then
            child:set_text("在线设备：" .. #device_ids)
            break
        end
    end
end

-- 连接 MQTT
function connect_mqtt(callback)
    callback = callback or function() end
    log.info("mqtt", "connect_mqtt called, device_id=", my_device_id)
    
    -- 如果已经有对战连接，不要重新连接，避免断开现有连接
    if game_state_mqtt.peer_connected then
        log.info("mqtt", "already in game, skipping connect")
        callback(true, "already connected")
        return
    end
    
    if not ensure_mqtt() then
        log.error("mqtt", "mqtt module not loaded, cannot connect")
        callback(false, "MQTT 模块未加载")
        return
    end
    
    if game_state_mqtt.mqtt_client then
        log.info("mqtt", "mqtt client already exists, reusing")
        
        if game_state_mqtt.mqtt_ready then
            log.info("mqtt", "restarting presence broadcast")
            if game_state_mqtt.presence_timer then
                sys.timerStop(game_state_mqtt.presence_timer)
            end
            game_state_mqtt.presence_timer = sys.timerLoopStart(function()
                if game_state_mqtt.mqtt_ready and not game_state_mqtt.peer_connected then
                    local presence_data = {
                        type = "presence",
                        device_id = my_device_id,
                        is_server = game_state_mqtt.is_server
                    }
                    local ok, json_str = pcall(json.encode, presence_data)
                    if ok and game_state_mqtt.mqtt_client then
                        log.info("mqtt", "broadcasting presence")
                        game_state_mqtt.mqtt_client:publish(TOPIC_PRESENCE, json_str, MQTT_QOS)
                    end
                    
                    -- 清理超时的设备
                    local now = os.time()
                    local need_update = false
                    for device_id, device_info in pairs(game_state_mqtt.online_devices) do
                        if device_info.last_seen and now - device_info.last_seen > 30 then
                            log.info("mqtt", "removing timeout device:", device_id)
                            game_state_mqtt.online_devices[device_id] = nil
                            need_update = true
                        end
                    end
                    if need_update and main_container then
                        update_device_list()
                    end
                end
            end, 3000)
        end
        
        callback(true)
        return
    end

    log.info("mqtt", "creating mqtt client, server=", MQTT_SERVER, "port=", MQTT_PORT)
    local mqtt_client = mqtt.create(nil, MQTT_SERVER, MQTT_PORT)
    if not mqtt_client then
        log.error("mqtt", "create mqtt client failed")
        callback(false, "创建客户端失败")
        return
    end
    
    log.info("mqtt", "authenticating mqtt client...")
    local success = true
    if not mqtt_client:auth("othello_" .. my_device_id, '', '', true) then
        success = false
    end
    
    if not success then
        log.error("mqtt", "mqtt auth failed")
        callback(false, "认证失败")
        return
    end
    log.info("mqtt", "mqtt auth success")
    
    mqtt_client:on(function(client, event, data, payload, metas)
        log.info("mqtt", "event received:", event)
        if event == "conack" then
            log.info("mqtt", "connected to mqtt server")
            game_state_mqtt.mqtt_ready = true
            game_state_mqtt.mqtt_client = client
            game_state_mqtt.reconnect_count = 0
            
            log.info("mqtt", "subscribing to topics...")
            client:subscribe(TOPIC_PRESENCE, MQTT_QOS)
            client:subscribe(TOPIC_DATA .. my_device_id, MQTT_QOS)
            log.info("mqtt", "subscribed to", TOPIC_PRESENCE, "and", TOPIC_DATA .. my_device_id)
            
            local presence_data = {
                type = "presence",
                device_id = my_device_id,
                is_server = game_state_mqtt.is_server
            }
            local ok, json_str = pcall(json.encode, presence_data)
            if ok then
                log.info("mqtt", "publishing presence, device_id=", my_device_id)
                client:publish(TOPIC_PRESENCE, json_str, MQTT_QOS)
            end
            
            log.info("mqtt", "starting heartbeat")
            M.Start_heartbeat()
            
            log.info("mqtt", "starting presence broadcast")
            if game_state_mqtt.presence_timer then
                sys.timerStop(game_state_mqtt.presence_timer)
            end
            game_state_mqtt.presence_timer = sys.timerLoopStart(function()
                if game_state_mqtt.mqtt_ready and not game_state_mqtt.peer_connected then
                    local presence_data = {
                        type = "presence",
                        device_id = my_device_id,
                        is_server = game_state_mqtt.is_server
                    }
                    local ok, json_str = pcall(json.encode, presence_data)
                    if ok and game_state_mqtt.mqtt_client then
                        log.info("mqtt", "broadcasting presence")
                        game_state_mqtt.mqtt_client:publish(TOPIC_PRESENCE, json_str, MQTT_QOS)
                    end
                    
                    -- 清理超时的设备
                    local now = os.time()
                    local need_update = false
                    for device_id, device_info in pairs(game_state_mqtt.online_devices) do
                        if device_info.last_seen and now - device_info.last_seen > 30 then
                            log.info("mqtt", "removing timeout device:", device_id)
                            game_state_mqtt.online_devices[device_id] = nil
                            need_update = true
                        end
                    end
                    if need_update and main_container then
                        update_device_list()
                    end
                end
            end, 3000)
            
        elseif event == "offline" then
            log.warn("mqtt", "disconnected from server")
            game_state_mqtt.mqtt_ready = false
            stop_heartbeat()
            
            if game_state_mqtt.reconnect_count < game_state_mqtt.max_reconnect then
                game_state_mqtt.reconnect_count = game_state_mqtt.reconnect_count + 1
                log.info("mqtt", "scheduling reconnect")
                sys.timerStart(function()
                    if not game_state_mqtt.mqtt_client then
                        connect_mqtt()
                    end
                end, 3000)
            else
                log.error("mqtt", "max reconnect attempts reached")
                airui.msgbox({
                    title = "连接断开",
                    text = "网络连接已断开，无法继续游戏",
                    buttons = { "确定" },
                    on_action = function(self)
                        self:hide()
                        self:destroy()
                        create_main_menu()
                    end,
                }):show()
            end
            
        elseif event == "recv" then
            local topic = data
            log.info("mqtt", "received message, topic=", topic, "payload=", payload)
            
            if not topic or not payload then
                log.error("mqtt", "invalid message")
                return
            end
            
            local ok, msg = pcall(json.decode, payload)
            if not ok or not msg then
                log.error("mqtt", "failed to decode json payload")
                return
            end
            log.info("mqtt", "decoded message, type=", msg.type)
            
            if topic == TOPIC_PRESENCE then
                if msg.type == "presence" then
                    if msg.device_id == my_device_id then
                        return
                    end
                    
                    if not game_state_mqtt.online_devices[msg.device_id] then
                        log.info("mqtt", "new device online:", msg.device_id)
                        game_state_mqtt.online_devices[msg.device_id] = {}
                    end
                    game_state_mqtt.online_devices[msg.device_id].last_seen = os.time()
                    game_state_mqtt.online_devices[msg.device_id].is_server = msg.is_server
                    
                    log.info("mqtt", "device online:", msg.device_id)
                    update_device_list()
                end
                
            elseif topic == TOPIC_DATA .. my_device_id then
                log.info("mqtt", "processing data message, type=", msg.type)
                
                if msg.type == "invite" then
                    log.info("mqtt", "received invite from", msg.from_device)
                    if msg.target_device == my_device_id then
                        airui.msgbox({
                            title = "收到邀请",
                            text = msg.from_device .. " 邀请你对战",
                            buttons = { "接受", "拒绝" },
                            on_action = function(self, label)
                                self:hide()
                                self:destroy()
                                if label == "接受" then
                                    log.info("mqtt", "accepted invite from", msg.from_device)
                                    game_state_mqtt.peer_device_id = msg.from_device
                                    game_state_mqtt.is_server = false  -- 接受方是客户端，执白
                                    game_state_mqtt.peer_connected = true
                                    game_state_mqtt.last_heartbeat = os.time()
                                    
                                    if game_state_mqtt.presence_timer then
                                        sys.timerStop(game_state_mqtt.presence_timer)
                                        game_state_mqtt.presence_timer = nil
                                    end
                                    
                                    M.Start_heartbeat()
                                    
                                    local accept_data = {
                                        type = "accept",
                                        from_device = my_device_id,
                                        target_device = msg.from_device
                                    }
                                    local ok2, json_str2 = pcall(json.encode, accept_data)
                                    if ok2 and game_state_mqtt.mqtt_client then
                                        game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. msg.from_device, json_str2, MQTT_QOS)
                                    end
                                    
                                    create_game_screen()
                                    start_game()
                                else
                                    -- 拒绝邀请
                                    log.info("mqtt", "rejected invite from", msg.from_device)
                                    local reject_data = {
                                        type = "reject",
                                        from_device = my_device_id,
                                        target_device = msg.from_device
                                    }
                                    local ok2, json_str2 = pcall(json.encode, reject_data)
                                    if ok2 and game_state_mqtt.mqtt_client then
                                        game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. msg.from_device, json_str2, MQTT_QOS)
                                    end
                                end
                            end,
                        }):show()
                    end
                    
                elseif msg.type == "accept" then
                    log.info("mqtt", "game accepted by", msg.from_device)
                    
                    if game_state_mqtt.invite_timeout then
                        sys.timerStop(game_state_mqtt.invite_timeout)
                        game_state_mqtt.invite_timeout = nil
                    end
                    
                    game_state_mqtt.peer_connected = true
                    game_state_mqtt.peer_device_id = msg.from_device
                    game_state_mqtt.is_server = true  -- 邀请方是服务器，执黑
                    game_state_mqtt.last_heartbeat = os.time()
                    
                    -- 停止 presence 广播并启动心跳
                    if game_state_mqtt.presence_timer then
                        sys.timerStop(game_state_mqtt.presence_timer)
                        game_state_mqtt.presence_timer = nil
                    end
                    
                    M.Start_heartbeat()
                    
                    create_game_screen()
                    start_game()
                    
                elseif msg.type == "move" then
                    log.info("mqtt", "received move from", msg.from_device)
                    if game_started and current_player ~= player_color then
                        local row, col = msg.row, msg.col
                        local flipped = msg.flipped
                        
                        make_move(row, col, computer_color, flipped)
                        count_pieces()
                        update_board_ui_full()
                        update_score_ui()
                        
                        local ack_data = {
                            type = "move_ack",
                            from_device = my_device_id,
                            success = true
                        }
                        local ok2, json_str2 = pcall(json.encode, ack_data)
                        if ok2 and game_state_mqtt.mqtt_client then
                            game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. game_state_mqtt.peer_device_id, json_str2, MQTT_QOS)
                        end
                        
                        if not has_valid_move(player_color) and not has_valid_move(computer_color) then
                            check_game_over()
                        elseif not has_valid_move(player_color) then
                            current_player = computer_color
                            update_score_ui()
                        else
                            current_player = player_color
                            update_score_ui()
                        end
                    end
                    
                elseif msg.type == "move_ack" then
                    log.info("mqtt", "received move_ack")
                    if game_state_mqtt.move_confirm_timer then
                        sys.timerStop(game_state_mqtt.move_confirm_timer)
                        game_state_mqtt.move_confirm_timer = nil
                    end
                    game_state_mqtt.pending_move = nil
                    
                elseif msg.type == "heartbeat" then
                    log.info("mqtt", "received heartbeat")
                    game_state_mqtt.last_heartbeat = os.time()
                    
                elseif msg.type == "leave" then
                    log.info("mqtt", "peer left the game")
                    airui.msgbox({
                        title = "对手离开",
                        text = "对手已离开游戏",
                        buttons = { "确定" },
                        on_action = function(self)
                            self:hide()
                            self:destroy()
                            create_main_menu()
                        end,
                    }):show()
                    
                elseif msg.type == "surrender" then
                    log.info("mqtt", "peer surrendered")
                    airui.msgbox({
                        title = "对手认输",
                        text = "对手已认输，你获得胜利！",
                        buttons = { "确定" },
                        on_action = function(self)
                            self:hide()
                            self:destroy()
                            -- 直接开始下一局游戏
                            start_game()
                        end,
                    }):show()
                    
                elseif msg.type == "reject" then
                    log.info("mqtt", "invite rejected by", msg.from_device)
                    if game_state_mqtt.invite_timeout then
                        sys.timerStop(game_state_mqtt.invite_timeout)
                        game_state_mqtt.invite_timeout = nil
                    end
                    airui.msgbox({
                        title = "邀请被拒绝",
                        text = msg.from_device .. " 拒绝了你的邀请",
                        buttons = { "确定" },
                        on_action = function(self)
                            self:hide()
                            self:destroy()
                            create_main_menu()
                        end,
                    }):show()
                end
            end
        end
    end)
    
    log.info("mqtt", "connecting to mqtt server...")
    local connect_result = mqtt_client:connect()
    if not connect_result then
        log.error("mqtt", "mqtt connect failed")
        callback(false, "连接失败")
        return
    end
    log.info("mqtt", "mqtt connect initiated, waiting for conack...")
end

-- 连接到对手
function Connect_to_peer(target_id)
    log.info("game", "Connect_to_peer called, target_id=", target_id)
    game_state_mqtt.peer_device_id = target_id
    game_state_mqtt.is_server = true  -- 邀请方是服务器，执黑先手
    game_state_mqtt.peer_connected = false  -- 先设为未连接，等待对方接受
    
    if game_state_mqtt.presence_timer then
        sys.timerStop(game_state_mqtt.presence_timer)
        game_state_mqtt.presence_timer = nil
    end
    
    show_connecting_screen(target_id)
    
    connect_mqtt(function(success, err)
        if success then
            log.info("mqtt", "connected, sending invite to", target_id)
            
            local invite_data = {
                type = "invite",
                from_device = my_device_id,
                target_device = target_id
            }
            local ok, json_str = pcall(json.encode, invite_data)
            if ok then
                game_state_mqtt.mqtt_client:publish(TOPIC_DATA .. target_id, json_str, MQTT_QOS)
            end
            
            game_state_mqtt.invite_timeout = sys.timerStart(function()
                if not game_state_mqtt.peer_connected then
                    log.warn("mqtt", "invite timeout")
                    airui.msgbox({
                        title = "邀请超时",
                        text = "对手未响应邀请",
                        buttons = { "确定" },
                        on_action = function(self)
                            self:hide()
                            self:destroy()
                            create_main_menu()
                        end,
                    }):show()
                end
            end, 15000)
        else
            log.error("mqtt", "connection failed:", err)
            create_main_menu()
        end
    end)
end

-- 窗口事件处理
local function on_create()
    create_main_menu()
end

local function on_destroy()
    log.info("on_destroy: cleaning up, peer_connected=", game_state_mqtt.peer_connected)
    disconnect_mqtt()
    
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    
    cells = {}
    board = {}
end

local function on_get_focus()
    if main_container then
        main_container:show()
    end
end

local function on_lose_focus()
    if main_container then
        main_container:hide()
    end
end

-- 打开窗口
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

-- 注册消息处理
sys.subscribe("OPEN_OTHELLO_ONLINE", open_handler)

return M
