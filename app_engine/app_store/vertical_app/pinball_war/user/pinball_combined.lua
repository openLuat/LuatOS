--[[
@module  pinball_combined
@summary 弹球大作战整合版本
@version 8.0.0
@date    2026.06.05
@author  LuatOS
]]
local expvp = require "expvp"

local SCREEN_W = 320
local SCREEN_H = 480

-- ============ 窗口管理 ============
local win_id = nil
local main_container = nil

-- ============ 页面状态 ============
local current_page = "menu" -- menu, single_game, net

-- ============ 菜单相关变量 ============
local menu_root = nil
local menu_timer = nil
local destroyed = false
local difficulty_panel = nil
local current_difficulty = "medium"

-- ============ 单机游戏相关变量 ============
local COLOR_BG_GAME = 0x0d1117
local COLOR_GRID_LINE = 0x21262d
local COLOR_PLAYER = 0x3b82f6
local COLOR_AI = 0xff6b35
local COLOR_BALL = 0xffd700
local COLOR_TEXT = 0xffffff
local COLOR_LINE = 0x30363d

local PADDLE_W = 90
local PADDLE_H = 14
local PLAYER_Y = SCREEN_H - 38
local AI_Y = 24
local BALL_SIZE = 12

local difficulty_settings = {
    easy = {
        ball_speed = 4,
        ai_speed = 2,
        ai_prediction = 0.3
    },
    medium = {
        ball_speed = 6,
        ai_speed = 3,
        ai_prediction = 0.6
    },
    hard = {
        ball_speed = 8,
        ai_speed = 4,
        ai_prediction = 0.8
    }
}

local single_game_state = {
    state = "ready",
    player_score = 0,
    ai_score = 0,
    player_paddle = { x = (SCREEN_W - PADDLE_W) / 2 },
    ai_paddle = { x = (SCREEN_W - PADDLE_W) / 2 },
    ball = { 
        x = (SCREEN_W - BALL_SIZE) / 2, 
        y = SCREEN_H / 2 - BALL_SIZE / 2, 
        vx = 0, 
        vy = 0 
    }
}

local single_game_ui = {
    player_score_label = nil,
    ai_score_label = nil,
    player_paddle_obj = nil,
    ai_paddle_obj = nil,
    ball_obj = nil
}
local single_game_timer = nil

-- ============ 联网对战相关变量 ============
local net_state = {
    valid = false,
    on_back_callback = nil,
    current_page = "lobby",
    menu_container = nil,
    room_waiting_container = nil,
    room_player_list = {},
    room_ready_btn = nil,
    room_start_btn = nil,
    room_leave_btn = nil,
    room_status_label = nil,
    join_dialog_container = nil,
    join_input_label = nil,
    join_input_text = "",
    lbl_status = nil,
    toast_container = nil,
    network_connected = false,
    is_host_player = false,
    current_room_id = nil,
    my_ready = false,
    room_has_enough = false,
    my_device_id = nil,
    my_player_number = 1,
    game_container = nil,
    player_score_label = nil,
    peer_score_label = nil,
    game_status_label = nil,
    player_paddle_obj = nil,
    peer_paddle_obj = nil,
    ball_obj = nil,
    game_timer = nil,
    game_state = "ready",
    player_score = 0,
    peer_score = 0,
    max_score = 11,
    game_started = false,
    is_host = false,
    peer_id = nil,
    peer_ready = false,
    player_paddle_x = 0,
    peer_paddle_x = 0,
    ball_x = 0,
    ball_y = 0,
    ball_vx = 0,
    ball_vy = 0,
    display_ball_x = 0,
    display_ball_y = 0,
    target_ball_x = 0,
    target_ball_y = 0,
    predict_frames_since_sync = 0,
    paddle_send_counter = 0,
    last_sent_paddle_x = nil,
    paddle_seq = 0,
    last_peer_paddle_seq = 0,
    touch_state = {
        dragging = false,
        track_id = nil,
        offset_x = 0
    }
}

local expvp_initialized = false

-- ============ 通用工具函数 ============
local function clamp(value, min_val, max_val)
    if value < min_val then return min_val end
    if value > max_val then return max_val end
    return value
end

local function safe_update_label(label, text)
    if not label then return false end
    local success, err = pcall(function()
        label:set_text(text)
    end)
    return success
end

local function safe_update_container(container, x, y)
    if not container then return false end
    local success, err = pcall(function()
        container:set_pos(math.floor(x), math.floor(y))
    end)
    return success
end

local function get_device_id()
    local info = expvp.get_player_info()
    return info.device_id
end

-- ============ Toast 显示函数 ============
local function show_toast(message, duration)
    duration = duration or 2000
    
    if net_state.toast_container then
        pcall(function() net_state.toast_container:destroy() end)
        net_state.toast_container = nil
    end
    
    if not main_container then return end
    
    net_state.toast_container = airui.container({
        parent = main_container,
        x = SCREEN_W / 2 - 150,
        y = SCREEN_H / 2 - 30,
        w = 300,
        h = 60,
        color = 0x1a1a2e,
        radius = 10,
        scrollable = false
    })
    
    airui.label({
        parent = net_state.toast_container,
        x = 0,
        y = 10,
        w = 300,
        h = 40,
        text = message,
        font_size = 16,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    sys.timerStart(function()
        if net_state.toast_container then
            pcall(function() net_state.toast_container:destroy() end)
            net_state.toast_container = nil
        end
    end, duration)
end

-- ============ 清理页面函数 ============
local function destroy_page()
    -- 停止单机游戏计时器
    if single_game_timer then
        sys.timerStop(single_game_timer)
        single_game_timer = nil
    end
    
    -- 停止联网游戏计时器
    if net_state.game_timer then
        sys.timerStop(net_state.game_timer)
        net_state.game_timer = nil
    end
    
    -- 清理菜单UI
    if menu_root then
        pcall(function() menu_root:destroy() end)
        menu_root = nil
    end
    
    -- 清理联网游戏相关UI
    if net_state.menu_container then
        pcall(function() net_state.menu_container:destroy() end)
        net_state.menu_container = nil
    end
    if net_state.room_waiting_container then
        pcall(function() net_state.room_waiting_container:destroy() end)
        net_state.room_waiting_container = nil
    end
    if net_state.join_dialog_container then
        pcall(function() net_state.join_dialog_container:destroy() end)
        net_state.join_dialog_container = nil
    end
    if net_state.game_container then
        pcall(function() net_state.game_container:destroy() end)
        net_state.game_container = nil
    end
    
    if net_state.toast_container then
        pcall(function() net_state.toast_container:destroy() end)
        net_state.toast_container = nil
    end
    
    -- 重置所有UI组件引用
    net_state.game_status_label = nil
    net_state.player_score_label = nil
    net_state.peer_score_label = nil
    net_state.player_paddle_obj = nil
    net_state.peer_paddle_obj = nil
    net_state.ball_obj = nil
    net_state.lbl_status = nil
    net_state.room_status_label = nil
    net_state.room_player_list = {}
    net_state.room_ready_btn = nil
    net_state.room_start_btn = nil
    net_state.room_leave_btn = nil
    net_state.join_input_label = nil
    
    -- 重置单机游戏UI引用
    single_game_ui.player_score_label = nil
    single_game_ui.ai_score_label = nil
    single_game_ui.player_paddle_obj = nil
    single_game_ui.ai_paddle_obj = nil
    single_game_ui.ball_obj = nil
    
    -- 重置联网状态
    net_state.valid = false
    net_state.on_back_callback = nil
    net_state.current_page = "lobby"
    net_state.network_connected = false
    net_state.is_host_player = false
    net_state.current_room_id = nil
    net_state.my_ready = false
    net_state.room_has_enough = false
    net_state.my_player_number = 1
    net_state.game_state = "ready"
    net_state.player_score = 0
    net_state.peer_score = 0
    net_state.game_started = false
    net_state.is_host = false
    net_state.peer_id = nil
    net_state.peer_ready = false
    net_state.player_paddle_x = 0
    net_state.peer_paddle_x = 0
    net_state.ball_x = 0
    net_state.ball_y = 0
    net_state.ball_vx = 0
    net_state.ball_vy = 0
    net_state.touch_state = {
        dragging = false,
        track_id = nil,
        offset_x = 0
    }
    
    -- 重置单机游戏状态
    single_game_state.state = "ready"
    single_game_state.player_score = 0
    single_game_state.ai_score = 0
    single_game_state.player_paddle.x = (SCREEN_W - PADDLE_W) / 2
    single_game_state.ai_paddle.x = (SCREEN_W - PADDLE_W) / 2
    single_game_state.ball.x = (SCREEN_W - BALL_SIZE) / 2
    single_game_state.ball.y = SCREEN_H / 2 - BALL_SIZE / 2
    single_game_state.ball.vx = 0
    single_game_state.ball.vy = 0
end

-- ============ 菜单函数 ============
local function animate_ball()
    if destroyed then
        return
    end
end

local function on_menu_tick()
    animate_ball()
end

local function create_difficulty_buttons(parent)
    if difficulty_panel then
        difficulty_panel:destroy()
    end
    difficulty_panel = airui.container({
        parent = parent,
        x = 20,
        y = 235,
        w = 280,
        h = 50,
        color = 0x16213e,
        opacity = 0.9,
        radius = 25
    })
    
    local COLOR_EASY = 0x22c55e
    local COLOR_MEDIUM = 0xf97316
    local COLOR_HARD = 0xef4444
    local DEFAULT_COLOR = 0x0f3460
    
    local function on_click_easy()
        current_difficulty = "easy"
        create_difficulty_buttons(parent)
    end
    
    local function on_click_medium()
        current_difficulty = "medium"
        create_difficulty_buttons(parent)
    end
    
    local function on_click_hard()
        current_difficulty = "hard"
        create_difficulty_buttons(parent)
    end
    
    -- 简单难度按钮
    local btn_easy = airui.container({
        parent = difficulty_panel,
        x = 10,
        y = 10,
        w = 80,
        h = 30,
        color = (current_difficulty == "easy") and COLOR_EASY or DEFAULT_COLOR,
        opacity = (current_difficulty == "easy") and 1 or 0.8,
        radius = 15,
        border_color = (current_difficulty == "easy") and 0xffffff or 0x533483,
        border_width = (current_difficulty == "easy") and 2 or 1,
        on_click = on_click_easy
    })
    -- 简单图片
    airui.image({
        parent = btn_easy,
        x = 8,
        y = 7,
        w = 16,
        h = 16,
        src = "/luadb/jiandan.png"
    })
    -- 简单文字
    airui.label({
        parent = btn_easy,
        x = 28,
        y = 9,
        w = 45,
        h = 14,
        text = "简单",
        font_size = 12,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 普通难度按钮
    local btn_medium = airui.container({
        parent = difficulty_panel,
        x = 100,
        y = 10,
        w = 80,
        h = 30,
        color = (current_difficulty == "medium") and COLOR_MEDIUM or DEFAULT_COLOR,
        opacity = (current_difficulty == "medium") and 1 or 0.8,
        radius = 15,
        border_color = (current_difficulty == "medium") and 0xffffff or 0x533483,
        border_width = (current_difficulty == "medium") and 2 or 1,
        on_click = on_click_medium
    })
    -- 普通图片
    airui.image({
        parent = btn_medium,
        x = 8,
        y = 7,
        w = 16,
        h = 16,
        src = "/luadb/putong.png"
    })
    -- 普通文字
    airui.label({
        parent = btn_medium,
        x = 28,
        y = 9,
        w = 45,
        h = 14,
        text = "普通",
        font_size = 12,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 困难难度按钮
    local btn_hard = airui.container({
        parent = difficulty_panel,
        x = 190,
        y = 10,
        w = 80,
        h = 30,
        color = (current_difficulty == "hard") and COLOR_HARD or DEFAULT_COLOR,
        opacity = (current_difficulty == "hard") and 1 or 0.8,
        radius = 15,
        border_color = (current_difficulty == "hard") and 0xffffff or 0x533483,
        border_width = (current_difficulty == "hard") and 2 or 1,
        on_click = on_click_hard
    })
    -- 困难图片
    airui.image({
        parent = btn_hard,
        x = 8,
        y = 7,
        w = 16,
        h = 16,
        src = "/luadb/kunnan.png"
    })
    -- 困难文字
    airui.label({
        parent = btn_hard,
        x = 28,
        y = 9,
        w = 45,
        h = 14,
        text = "困难",
        font_size = 12,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_LEFT
    })
end

local function on_click_single()
    switch_to_game()
end

local function on_click_online()
    switch_to_net()
end

local function on_click_exit()
    if win_id then
        exwin.close(win_id)
    end
end

local function show_menu()
    current_page = "menu"
    destroy_page()
    
    -- 清理菜单定时器
    if menu_timer then
        sys.timerStop(menu_timer)
        menu_timer = nil
    end
    
    -- 停止联网模块，避免后台重连
    if expvp_initialized and expvp then
        expvp.stop()
        expvp_initialized = false
        log.info("PINBALL", "Network stopped, exit to menu")
    end
    
    -- 重置联网状态
    net_state.valid = false
    net_state.current_page = "menu"
    net_state.game_started = false
    net_state.current_room_id = nil
    net_state.my_ready = false
    net_state.is_host_player = false
    net_state.peer_ready = false
    net_state.peer_id = nil
    net_state.player_score = 0
    net_state.peer_score = 0
    net_state.game_state = "ready"
    net_state.is_host = false
    
    -- 停止游戏定时器
    if net_state.game_timer then
        sys.timerStop(net_state.game_timer)
        net_state.game_timer = nil
    end
    
    -- 创建菜单UI容器
    menu_root = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0x1a1a2e,
        scrollable = false
    })
    
    -- 装饰性发光效果
    airui.container({
        parent = menu_root,
        x = 80,
        y = 20,
        w = 160,
        h = 160,
        color = 0x3b82f6,
        opacity = 0.15,
        radius = 80
    })
    
    -- 弹跳球阴影
    local ball_shadow = airui.container({
        parent = menu_root,
        x = 142,
        y = 155,
        w = 36,
        h = 8,
        color = 0x000000,
        opacity = 0.4,
        radius = 4
    })
    
    -- 弹跳球
    ball_gfx = airui.container({
        parent = menu_root,
        x = 135,
        y = 60,
        w = 50,
        h = 50,
        color = 0xffcc88,
        radius = 25
    })
    
    -- 球的高光效果
    airui.container({
        parent = ball_gfx,
        x = 8,
        y = 5,
        w = 20,
        h = 20,
        color = 0xffeeaa,
        radius = 10,
        opacity = 0.9
    })
    
    -- 主标题
    airui.label({
        parent = menu_root,
        x = 0,
        y = 170,
        w = SCREEN_W,
        h = 40,
        text = "弹球大作战",
        font_size = 24,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 副标题
    airui.label({
        parent = menu_root,
        x = 0,
        y = 210,
        w = SCREEN_W,
        h = 25,
        text = "极速AI 炫彩对决",
        font_size = 13,
        color = 0xa0a0c0,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 创建难度选择按钮
    create_difficulty_buttons(menu_root)
    
    -- 开始对战按钮
    local btn_single_container = airui.container({
        parent = menu_root,
        x = 25,
        y = 295,
        w = 240,
        h = 50,
        color = 0x3b82f6,
        radius = 25,
        on_click = function()
            show_single_game()
        end
    })
    -- 开始对战图片
    airui.image({
        parent = btn_single_container,
        x = 28,
        y = 17,
        w = 16,
        h = 16,
        src = "/luadb/youxi.png"
    })
    -- 开始对战文字
    airui.label({
        parent = btn_single_container,
        x = 52,
        y = 16,
        w = 160,
        h = 20,
        text = "开始对战",
        font_size = 17,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 联网对战按钮
    local btn_online = airui.container({
        parent = menu_root,
        x = 25,
        y = 355,
        w = 240,
        h = 50,
        color = 0xf97316,
        radius = 25,
        on_click = function()
            show_net_game()
        end
    })
    -- 联网对战图片
    airui.image({
        parent = btn_online,
        x = 28,
        y = 17,
        w = 16,
        h = 16,
        src = "/luadb/lianwang.png"
    })
    -- 联网对战文字
    airui.label({
        parent = btn_online,
        x = 52,
        y = 16,
        w = 160,
        h = 20,
        text = "联网对战",
        font_size = 17,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 退出游戏按钮
    local btn_exit = airui.container({
        parent = menu_root,
        x = 25,
        y = 415,
        w = 240,
        h = 35,
        color = 0x4b5563,
        radius = 17,
        on_click = on_click_exit
    })
    -- 退出图片
    airui.image({
        parent = btn_exit,
        x = 28,
        y = 9,
        w = 16,
        h = 16,
        src = "/luadb/tuichu.png"
    })
    -- 退出文字
    airui.label({
        parent = btn_exit,
        x = 52,
        y = 9,
        w = 160,
        h = 16,
        text = "退出游戏",
        font_size = 14,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    -- 页脚信息
    airui.label({
        parent = menu_root,
        x = 0,
        y = SCREEN_H - 20,
        w = SCREEN_W,
        h = 18,
        text = "自由移动 左右反弹 全新视觉",
        font_size = 10,
        color = 0x6b7280,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 启动菜单动画定时器
    menu_timer = sys.timerLoopStart(on_menu_tick, 16)
end

-- ============ 单机游戏函数 ============
local function single_update_score()
    safe_update_label(single_game_ui.player_score_label, single_game_state.player_score)
    safe_update_label(single_game_ui.ai_score_label, single_game_state.ai_score)
end

local function single_reset_game()
    single_game_state.state = "ready"
    
    local content_padding = 2
    local container_w = SCREEN_W - content_padding * 2
    local container_h = SCREEN_H - content_padding * 2
    
    single_game_state.ball.x = (container_w - BALL_SIZE) / 2
    single_game_state.ball.y = container_h / 2 - BALL_SIZE / 2
    single_game_state.ball.vx = 0
    single_game_state.ball.vy = 0
    
    single_game_state.player_paddle.x = (container_w - PADDLE_W) / 2
    single_game_state.ai_paddle.x = (container_w - PADDLE_W) / 2
    
    safe_update_container(single_game_ui.player_paddle_obj, single_game_state.player_paddle.x, container_h - 38)
    safe_update_container(single_game_ui.ai_paddle_obj, single_game_state.ai_paddle.x, 24)
    safe_update_container(single_game_ui.ball_obj, single_game_state.ball.x, single_game_state.ball.y)
end

local function single_handle_paddle_hit(paddle, is_top)
    local hit_pos = (single_game_state.ball.x + BALL_SIZE / 2 - paddle.x) / PADDLE_W
    hit_pos = clamp(hit_pos, 0.05, 0.95)
    local offset = (hit_pos - 0.5) * 2
    local settings = difficulty_settings[current_difficulty]
    single_game_state.ball.vx = offset * settings.ball_speed * 1.2
    
    if is_top then
        single_game_state.ball.vy = settings.ball_speed
        single_game_state.ball.y = 24 + PADDLE_H + 1
    else
        local content_padding = 2
        local container_h = SCREEN_H - content_padding * 2
        single_game_state.ball.vy = -settings.ball_speed
        single_game_state.ball.y = (container_h - 38) - BALL_SIZE - 1
    end
end

local function single_update_ball()
    if single_game_state.state ~= "playing" then return end
    
    single_game_state.ball.x = single_game_state.ball.x + single_game_state.ball.vx
    single_game_state.ball.y = single_game_state.ball.y + single_game_state.ball.vy
    
    -- 获取游戏容器边界
    local content_padding = 2
    local container_w = SCREEN_W - content_padding * 2
    local container_h = SCREEN_H - content_padding * 2
    
    if single_game_state.ball.x <= 5 then
        single_game_state.ball.x = 5
        single_game_state.ball.vx = math.abs(single_game_state.ball.vx)
    elseif single_game_state.ball.x + BALL_SIZE >= container_w - 5 then
        single_game_state.ball.x = container_w - 5 - BALL_SIZE
        single_game_state.ball.vx = -math.abs(single_game_state.ball.vx)
    end
    
    if single_game_state.ball.vy < 0 then
        if single_game_state.ball.y <= 24 + PADDLE_H and single_game_state.ball.y + BALL_SIZE >= 24 and
           single_game_state.ball.x + BALL_SIZE > single_game_state.ai_paddle.x and single_game_state.ball.x < single_game_state.ai_paddle.x + PADDLE_W then
            single_handle_paddle_hit(single_game_state.ai_paddle, true)
        end
    end
    
    if single_game_state.ball.vy > 0 then
        if single_game_state.ball.y + BALL_SIZE >= container_h - 38 and single_game_state.ball.y <= (container_h - 38) + PADDLE_H and
           single_game_state.ball.x + BALL_SIZE > single_game_state.player_paddle.x and single_game_state.ball.x < single_game_state.player_paddle.x + PADDLE_W then
            single_handle_paddle_hit(single_game_state.player_paddle, false)
        end
    end
    
    if single_game_state.ball.y < 24 - 15 then
        single_game_state.player_score = single_game_state.player_score + 1
        single_update_score()
        if single_game_state.player_score >= 11 then
            single_game_state.state = "gameover"
        else
            single_reset_game()
        end
        return
    end
    
    if single_game_state.ball.y > (container_h - 38) + PADDLE_H + 15 then
        single_game_state.ai_score = single_game_state.ai_score + 1
        single_update_score()
        if single_game_state.ai_score >= 11 then
            single_game_state.state = "gameover"
        else
            single_reset_game()
        end
        return
    end
    
    safe_update_container(single_game_ui.ball_obj, single_game_state.ball.x, single_game_state.ball.y)
end

local function single_update_ai()
    if single_game_state.state ~= "playing" then return end
    
    local settings = difficulty_settings[current_difficulty]
    
    -- 降低AI的预测准确性
    local predict_error = 1 - settings.ai_prediction
    local predict_x = single_game_state.ball.x + single_game_state.ball.vx * 0.5 + (math.random() - 0.5) * predict_error * 100
    
    local ai_target_x = predict_x - PADDLE_W / 2
    local content_padding = 2
    local container_w = SCREEN_W - content_padding * 2
    ai_target_x = clamp(ai_target_x, 5, container_w - 5 - PADDLE_W)
    
    local move_speed = settings.ai_speed
    local dx = ai_target_x - single_game_state.ai_paddle.x
    if math.abs(dx) < move_speed then
        single_game_state.ai_paddle.x = ai_target_x
    else
        single_game_state.ai_paddle.x = single_game_state.ai_paddle.x + (dx > 0 and move_speed or -move_speed)
    end
    
    single_game_state.ai_paddle.x = clamp(single_game_state.ai_paddle.x, 5, container_w - 5 - PADDLE_W)
    
    safe_update_container(single_game_ui.ai_paddle_obj, single_game_state.ai_paddle.x, 24)
end

local function single_game_loop()
    single_update_ball()
    single_update_ai()
end

local function single_move_paddle_to(x)
    if single_game_state.state == "paused" then return end
    
    local content_padding = 2
    local container_w = SCREEN_W - content_padding * 2
    single_game_state.player_paddle.x = clamp(x - PADDLE_W / 2, 5, container_w - 5 - PADDLE_W)
    
    if single_game_ui.player_paddle_obj then
        local container_h = SCREEN_H - content_padding * 2
        safe_update_container(single_game_ui.player_paddle_obj, single_game_state.player_paddle.x, container_h - 38)
    end
end

function show_single_game()
    current_page = "single_game"
    destroy_page()
    
    -- 主容器
    local game_root = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = COLOR_BG_GAME,
        scrollable = false
    })
    
    -- 游戏区域容器
    local content_padding = 2
    local game_container = airui.container({
        x = content_padding,
        y = content_padding,
        w = SCREEN_W - content_padding * 2,
        h = SCREEN_H - content_padding * 2,
        color = COLOR_BG_GAME,
        parent = game_root,
        scrollable = false
    })
    
    -- 创建网格背景
    local grid_size = 16
    local container_w = SCREEN_W - content_padding * 2
    local container_h = SCREEN_H - content_padding * 2
    local max_x = (container_w // grid_size) * grid_size
    local max_y = (container_h // grid_size) * grid_size
    
    for y = 0, max_y, grid_size do
        airui.container({
            parent = game_container,
            x = 0,
            y = y,
            w = container_w,
            h = 1,
            color = COLOR_GRID_LINE,
            opacity = 0.3
        })
    end
    for x = 0, max_x, grid_size do
        airui.container({
            parent = game_container,
            x = x,
            y = 0,
            w = 1,
            h = container_h,
            color = COLOR_GRID_LINE,
            opacity = 0.3
        })
    end
    
    -- 返回按钮
    local back_btn = airui.container({
        parent = game_container,
        x = 4,
        y = 4,
        w = 36,
        h = 36,
        color = 0x21262d,
        opacity = 0.85,
        radius = 18,
        on_click = function()
            show_menu()
        end
    })
    
    -- 返回箭头
    airui.label({
        parent = back_btn,
        x = 8,
        y = 6,
        w = 20,
        h = 24,
        text = "<",
        font_size = 20,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- AI分数标签
    single_game_ui.ai_score_label = airui.label({
        parent = game_container,
        x = container_w / 2 - 25,
        y = container_h / 2 - 70,
        w = 50,
        h = 45,
        text = "0",
        font_size = 36,
        color = COLOR_BALL,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 玩家分数标签
    single_game_ui.player_score_label = airui.label({
        parent = game_container,
        x = container_w / 2 - 25,
        y = container_h / 2 + 15,
        w = 50,
        h = 45,
        text = "0",
        font_size = 36,
        color = COLOR_BALL,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 中线（虚线）
    local dash_gap = 8
    for i = 0, container_w // (dash_gap * 2) do
        airui.container({
            parent = game_container,
            x = i * dash_gap * 2,
            y = container_h / 2 - 1,
            w = dash_gap,
            h = 2,
            color = COLOR_LINE,
            opacity = 0.5
        })
    end
    
    -- 玩家球拍
    single_game_ui.player_paddle_obj = airui.container({
        parent = game_container,
        x = (container_w - PADDLE_W) / 2,
        y = container_h - 38,
        w = PADDLE_W,
        h = PADDLE_H,
        color = COLOR_PLAYER,
        radius = 7
    })
    
    -- AI球拍
    single_game_ui.ai_paddle_obj = airui.container({
        parent = game_container,
        x = (container_w - PADDLE_W) / 2,
        y = 24,
        w = PADDLE_W,
        h = PADDLE_H,
        color = COLOR_AI,
        radius = 7
    })
    
    -- 球
    single_game_ui.ball_obj = airui.container({
        parent = game_container,
        x = (container_w - BALL_SIZE) / 2,
        y = container_h / 2 - BALL_SIZE / 2,
        w = BALL_SIZE,
        h = BALL_SIZE,
        color = COLOR_BALL,
        radius = BALL_SIZE / 2
    })
    
    -- 游戏逻辑
    single_game_state.state = "ready"
    single_game_state.player_score = 0
    single_game_state.ai_score = 0
    single_reset_game()
    single_update_score()
    
    -- 启动游戏循环
    single_game_timer = sys.timerLoopStart(single_game_loop, 16)
    
    -- 触摸处理
    airui.touch_subscribe(function(state_tp, x, y, track_id)
        local is_down = (airui.TP_DOWN and state_tp == airui.TP_DOWN) or (state_tp == 1)
        local is_hold = (airui.TP_HOLD and state_tp == airui.TP_HOLD) or (state_tp == 2)
        
        if is_down then
            single_move_paddle_to(x)
            if single_game_state.state == "ready" then
                single_game_state.state = "playing"
                local settings = difficulty_settings[current_difficulty]
                single_game_state.ball.vx = (math.random() - 0.5) * settings.ball_speed * 1.5
                single_game_state.ball.vy = -settings.ball_speed
            elseif single_game_state.state == "gameover" then
                single_game_state.player_score = 0
                single_game_state.ai_score = 0
                single_update_score()
                single_reset_game()
            end
        elseif is_hold then
            single_move_paddle_to(x)
        end
    end)
end

-- ============ 联网对战函数 ============
local function send_opponent_left()
    if not net_state.current_room_id then return end
    expvp.broadcast_to_room({
        type = "opponent_left",
        from_device = net_state.my_device_id,
    })
    log.info("PINBALL", "已发送退出通知给对方")
end

local function update_room_ui()
    log.info("PINBALL", "update_room_ui 被调用")
    if not net_state.room_waiting_container or not net_state.valid then return end
    
    -- 先确保 my_device_id 有值
    if not net_state.my_device_id then
        net_state.my_device_id = get_device_id()
    end
    
    local room_info = expvp.get_room_info()
    if not room_info then return end
    
    log.info("PINBALL", "room_info:", room_info)
    
    net_state.is_host_player = room_info.is_host
    net_state.current_room_id = room_info.room_id
    local players = room_info.players or {}
    local player_count = 0
    
    -- 提取房间号（去掉 room_ 前缀）
    local room_display_id = net_state.current_room_id or ""
    if room_display_id:sub(1, 5) == "room_" then
        room_display_id = room_display_id:sub(6)
    end
    
    -- 更新房间号标签
    safe_update_label(net_state.room_status_label, "房间: " .. room_display_id)
    
    -- 收集和排序玩家
    local sorted_devices = {}
    
    -- 先添加房主
    if room_info.host_device_id then
        table.insert(sorted_devices, room_info.host_device_id)
    end
    
    -- 再添加其他玩家
    for device_id, _ in pairs(players) do
        if device_id ~= room_info.host_device_id then
            table.insert(sorted_devices, device_id)
        end
    end
    
    -- 如果没有玩家（理论上不应该），至少添加自己
    if #sorted_devices == 0 then
        table.insert(sorted_devices, net_state.my_device_id)
    end
    
    player_count = #sorted_devices
    net_state.room_has_enough = player_count >= 2
    net_state.my_ready = room_info.my_ready
    
    -- 更新玩家列表显示
    for i = 1, 2 do
        local slot = net_state.room_player_list[i]
        if slot then
            local device_id = sorted_devices[i]
            
            if device_id and players[device_id] then
                local pinfo = players[device_id]
                local nickname = ""
                local ready = false
                
                if device_id == net_state.my_device_id then
                    -- 自己
                    nickname = (pinfo.nickname or device_id:sub(-6)) .. " [你]"
                    ready = room_info.my_ready
                elseif pinfo then
                    -- 其他玩家
                    nickname = pinfo.nickname or device_id:sub(-6)
                    ready = pinfo.ready or false
                else
                    -- 没有信息
                    nickname = device_id:sub(-6)
                end
                
                -- 更新玩家名称
                safe_update_label(slot.name_label, nickname)
                
                -- 更新准备状态显示和颜色
                if ready then
                    safe_update_label(slot.ready_label, "已准备")
                    if slot.ready_label then
                        pcall(function() slot.ready_label:set_color(0x22c55e) end)
                    end
                else
                    safe_update_label(slot.ready_label, "未准备")
                    if slot.ready_label then
                        pcall(function() slot.ready_label:set_color(0xff4444) end)
                    end
                end
                
                -- 更新槽位背景色
                if device_id == net_state.my_device_id then
                    pcall(function() slot.container:set_color(0x2a2a5e) end)
                else
                    pcall(function() slot.container:set_color(0x2a2a3e) end)
                end
            else
                -- 空槽位
                safe_update_label(slot.name_label, "等待加入...")
                safe_update_label(slot.ready_label, "")
                pcall(function() slot.container:set_color(0x1a1a2e) end)
            end
        end
    end
    
    -- 更新准备按钮颜色和文本
    if net_state.room_ready_btn then
        if net_state.my_ready then
            net_state.room_ready_btn:set_color(0x22c55e)
            safe_update_label(net_state.room_ready_label, "取消准备")
        else
            net_state.room_ready_btn:set_color(0x3b82f6)
            safe_update_label(net_state.room_ready_label, "准备")
        end
    end
    
    -- 开始按钮（房主可见）
    if net_state.room_start_btn then
        if net_state.is_host_player then
            -- 检查双方是否都准备
            local all_ready = true
            for i = 1, 2 do
                local device_id = sorted_devices[i]
                if device_id then
                    if device_id == net_state.my_device_id then
                        all_ready = all_ready and room_info.my_ready
                    elseif players[device_id] then
                        all_ready = all_ready and (players[device_id].ready or false)
                    else
                        all_ready = false
                    end
                else
                    all_ready = false
                end
            end
            
            if net_state.room_has_enough and all_ready then
                net_state.room_start_btn:set_color(0xff6b35)
            else
                net_state.room_start_btn:set_color(0x6b7280)
            end
            net_state.room_start_btn:set_hidden(false)
        else
            net_state.room_start_btn:set_hidden(true)
        end
    end
end

local function hide_room_waiting_ui()
    if net_state.room_waiting_container then
        pcall(function() net_state.room_waiting_container:destroy() end)
        net_state.room_waiting_container = nil
    end
    -- 重新显示主菜单
    if net_state.menu_container then
        pcall(function() net_state.menu_container:show() end)
    end
    net_state.room_player_list = {}
    net_state.room_ready_btn = nil
    net_state.room_ready_label = nil
    net_state.room_start_btn = nil
    net_state.room_leave_btn = nil
    net_state.room_status_label = nil
end

local function show_room_waiting_ui()
    log.info("PINBALL", "show_room_waiting_ui 被调用")
    
    -- 确保隐藏主菜单
    if net_state.menu_container then
        pcall(function() net_state.menu_container:hide() end)
    end
    
    -- 设置当前页面状态
    net_state.current_page = "lobby"
    
    -- 创建房间等待界面
    net_state.room_waiting_container = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0x0a0a1a,
        scrollable = false,
        clip = true
    })
    
    -- 顶部标题区域
    local header = airui.container({
        parent = net_state.room_waiting_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 50,
        color = 0x1a365d
    })
    
    -- 标题
    airui.label({
        parent = header,
        x = 0,
        y = 10,
        w = SCREEN_W,
        h = 30,
        text = "等待对手加入",
        font_size = 18,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 房间号显示
    net_state.room_status_label = airui.label({
        parent = net_state.room_waiting_container,
        x = 0,
        y = 60,
        w = SCREEN_W,
        h = 25,
        text = "房间: --",
        font_size = 14,
        color = 0xffd700,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 玩家列表区域
    local player_list_container = airui.container({
        parent = net_state.room_waiting_container,
        x = 30,
        y = 95,
        w = SCREEN_W - 60,
        h = 195,
        color = 0x1a1a2e,
        radius = 10,
        scrollable = false,
        clip = true
    })
    
    -- P1 槽位（宽度改小）
    local p1_slot = airui.container({
        parent = player_list_container,
        x = 10,
        y = 15,
        w = (SCREEN_W - 60) - 20,
        h = 75,
        color = 0x2a2a3e,
        radius = 8
    })
    
    net_state.room_player_list = {
        {
            container = p1_slot,
            label = airui.label({
                parent = p1_slot,
                x = 15,
                y = 10,
                w = 80,
                h = 25,
                text = "P1 (房主)",
                font_size = 14,
                color = 0xffd700,
                align = airui.TEXT_ALIGN_LEFT
            }),
            name_label = airui.label({
                parent = p1_slot,
                x = 15,
                y = 35,
                w = (SCREEN_W - 80) - 100,
                h = 30,
                text = "等待中...",
                font_size = 16,
                color = 0x888888,
                align = airui.TEXT_ALIGN_LEFT
            }),
            ready_label = airui.label({
                parent = p1_slot,
                x = (SCREEN_W - 80) - 85,
                y = 25,
                w = 70,
                h = 25,
                text = "未准备",
                font_size = 12,
                color = 0xff4444,
                align = airui.TEXT_ALIGN_CENTER
            })
        },
        {
            container = airui.container({
                parent = player_list_container,
                x = 10,
                y = 110,
                w = (SCREEN_W - 60) - 20,
                h = 75,
                color = 0x2a2a3e,
                radius = 8
            }),
            label = nil,
            name_label = nil,
            ready_label = nil
        }
    }
    
    -- P2 槽位的标签
    net_state.room_player_list[2].label = airui.label({
        parent = net_state.room_player_list[2].container,
        x = 15,
        y = 10,
        w = 50,
        h = 25,
        text = "P2",
        font_size = 14,
        color = 0x00c0ff,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    net_state.room_player_list[2].name_label = airui.label({
        parent = net_state.room_player_list[2].container,
        x = 15,
        y = 35,
        w = (SCREEN_W - 80) - 100,
        h = 30,
        text = "等待加入...",
        font_size = 16,
        color = 0x888888,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    net_state.room_player_list[2].ready_label = airui.label({
        parent = net_state.room_player_list[2].container,
        x = (SCREEN_W - 80) - 85,
        y = 25,
        w = 70,
        h = 25,
        text = "未准备",
        font_size = 12,
        color = 0x888888,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local btn_x = (SCREEN_W - 180) / 2
    local btn_start_y = 300
    local btn_h = 42
    local btn_gap = 8
    
    -- 准备按钮
    net_state.room_ready_btn = airui.container({
        parent = net_state.room_waiting_container,
        x = btn_x,
        y = btn_start_y,
        w = 180,
        h = btn_h,
        color = 0x3b82f6,
        radius = 22,
        on_click = function()
            log.info("PINBALL", "准备/取消准备")
            net_state.my_ready = not net_state.my_ready
            expvp.set_ready(net_state.my_ready)
            update_room_ui()
        end
    })
    -- 保存准备按钮的文本标签引用
    net_state.room_ready_label = airui.label({
        parent = net_state.room_ready_btn,
        x = 0,
        y = 12,
        w = 180,
        h = 20,
        text = "准备",
        font_size = 16,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 开始游戏按钮
    net_state.room_start_btn = airui.container({
        parent = net_state.room_waiting_container,
        x = btn_x,
        y = btn_start_y + (btn_h + btn_gap),
        w = 180,
        h = btn_h,
        color = 0x6b7280,
        radius = 22,
        hidden = true,
        on_click = function()
            log.info("PINBALL", "房主点击开始游戏")
            if net_state.is_host_player and net_state.room_has_enough then
                expvp.start_game()
            end
        end
    })
    airui.label({
        parent = net_state.room_start_btn,
        x = 0,
        y = 12,
        w = 180,
        h = 20,
        text = "开始游戏",
        font_size = 16,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 离开房间按钮
    net_state.room_leave_btn = airui.container({
        parent = net_state.room_waiting_container,
        x = btn_x,
        y = btn_start_y + (btn_h + btn_gap) * 2,
        w = 180,
        h = btn_h,
        color = 0x884444,
        radius = 22,
        on_click = function()
            log.info("PINBALL", "离开房间")
            send_opponent_left()
            net_state.my_ready = false
            net_state.is_host_player = false
            net_state.current_room_id = nil
            expvp.leave_room()
            hide_room_waiting_ui()
            show_net_game()
        end
    })
    airui.label({
        parent = net_state.room_leave_btn,
        x = 0,
        y = 12,
        w = 180,
        h = 20,
        text = "离开房间",
        font_size = 16,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    update_room_ui()
end

local function net_update_score()
    safe_update_label(net_state.player_score_label, net_state.player_score)
    safe_update_label(net_state.peer_score_label, net_state.peer_score)
end

-- 缓存常量避免重复计算（必须在使用前定义）
local BALL_SIZE_HALF = BALL_SIZE / 2
local CONTAINER_W = SCREEN_W - 4
local CONTAINER_H = SCREEN_H - 4
local PADDLE_TOP = 24
local PADDLE_BOTTOM = CONTAINER_H - 38
local PADDLE_TOP_END = PADDLE_TOP + PADDLE_H
local PADDLE_BOTTOM_END = PADDLE_BOTTOM + PADDLE_H
local NET_HIT_TOLERANCE = 10          -- 联网碰撞容错，降低延迟下的漏接
local MAX_CLIENT_PREDICT_FRAMES = 8   -- 玩家端最多预测8帧，避免长时间跑偏
local DISPLAY_SMOOTH_FAST = 0.45      -- 显示球追踪强度，误差较小时使用
local DISPLAY_SMOOTH_SLOW = 0.28      -- 显示球追踪强度，误差较大时使用
local DISPLAY_SNAP_DISTANCE = 100     -- 误差超过该距离时直接校正显示球

local function net_schedule_back_to_room(result_text)
    local state = net_state
    if state.return_room_pending then return end
    state.return_room_pending = true
    state.game_started = false
    state.game_state = "gameover"
    state.ball_vx = 0
    state.ball_vy = 0
    show_toast((result_text or "游戏结束") .. "，3秒后返回房间")
    
    sys.timerStart(function()
        if not state.return_room_pending then return end
        state.return_room_pending = false
        
        if not state.current_room_id then return end
        
        if state.game_timer then
            sys.timerStop(state.game_timer)
            state.game_timer = nil
        end
        
        if state.game_container then
            pcall(function() state.game_container:destroy() end)
            state.game_container = nil
        end
        
        state.current_page = "lobby"
        state.game_started = false
        state.game_state = "ready"
        state.ball_vx = 0
        state.ball_vy = 0
        state.player_score = 0
        state.peer_score = 0
        state.my_ready = false
        state.peer_ready = false
        
        if expvp_initialized and expvp then
            pcall(function() expvp.set_ready(false) end)
        end
        
        show_room_waiting_ui()
        update_room_ui()
    end, 3000)
end

local function net_reset_game()
    local state = net_state
    state.game_state = "ready"
    
    -- 使用预缓存的常量
    local container_w = CONTAINER_W
    local container_h = CONTAINER_H
    
    state.ball_x = (container_w - BALL_SIZE) / 2
    state.ball_y = container_h / 2 - BALL_SIZE_HALF
    state.target_ball_x = state.ball_x
    state.target_ball_y = state.ball_y
    state.display_ball_x = state.ball_x
    state.display_ball_y = state.ball_y
    state.ball_vx = 0
    state.ball_vy = 0
    state.predict_frames_since_sync = 0
    state.paddle_send_counter = 0
    state.last_sent_paddle_x = nil
    state.paddle_seq = 0
    state.last_peer_paddle_seq = 0
    
    state.player_paddle_x = (container_w - PADDLE_W) / 2
    state.peer_paddle_x = (container_w - PADDLE_W) / 2
    
    -- 更新UI
    safe_update_container(state.player_paddle_obj, state.player_paddle_x, state.is_host and PADDLE_BOTTOM or PADDLE_TOP)
    safe_update_container(state.peer_paddle_obj, state.peer_paddle_x, state.is_host and PADDLE_TOP or PADDLE_BOTTOM)
    safe_update_container(state.ball_obj, state.ball_x, state.ball_y)
    
    -- 房主需要广播重置状态给对手
    if state.is_host then
        expvp.broadcast_to_room({
            type = "full_state",
            from = state.my_device_id,
            ball_x = state.ball_x,
            ball_y = state.ball_y,
            ball_vx = state.ball_vx,
            ball_vy = state.ball_vy,
            player_paddle_x = state.player_paddle_x,
            peer_paddle_x = state.peer_paddle_x,
            player_score = state.player_score,
            peer_score = state.peer_score,
            game_state = state.game_state
        })
    end
end

local function net_update_ball()
    if not net_state.is_host then return end
    
    -- 缓存状态变量
    local state = net_state
    local game_state = state.game_state
    if game_state ~= "playing" and game_state ~= "ready" then return end
    
    -- 如果在 ready 状态但球有速度，自动变成 playing
    local vx, vy = state.ball_vx, state.ball_vy
    if game_state == "ready" and (vx ~= 0 or vy ~= 0) then
        state.game_state = "playing"
    end
    
    -- 只有球有速度时才更新
    if vx == 0 and vy == 0 then return end
    
    -- 更新球位置
    local bx, by = state.ball_x + vx, state.ball_y + vy
    
    -- 边界碰撞检测（快速版本）
    if bx < 0 then bx = 0; vx = -vx
    elseif bx + BALL_SIZE > CONTAINER_W then bx = CONTAINER_W - BALL_SIZE; vx = -vx end
    
    -- 对手球拍碰撞检测（顶部）：加入联网容错，降低延迟导致的漏接
    local peer_x = state.peer_paddle_x
    if vy < 0 and by <= PADDLE_TOP_END + NET_HIT_TOLERANCE and by + BALL_SIZE >= PADDLE_TOP - NET_HIT_TOLERANCE then
        if bx + BALL_SIZE > peer_x - NET_HIT_TOLERANCE and bx < peer_x + PADDLE_W + NET_HIT_TOLERANCE then
            local hit_pos = (bx + BALL_SIZE_HALF - peer_x) / PADDLE_W
            if hit_pos < 0.05 then hit_pos = 0.05
            elseif hit_pos > 0.95 then hit_pos = 0.95 end
            local offset = (hit_pos - 0.5) * 2
            vx = offset * 4.8
            vy = 4
            by = PADDLE_TOP_END + 1
        end
    end
    
    -- 玩家球拍碰撞检测（底部）：加入联网容错，降低延迟导致的漏接
    local player_x = state.player_paddle_x
    if vy > 0 and by + BALL_SIZE >= PADDLE_BOTTOM - NET_HIT_TOLERANCE and by <= PADDLE_BOTTOM_END + NET_HIT_TOLERANCE then
        if bx + BALL_SIZE > player_x - NET_HIT_TOLERANCE and bx < player_x + PADDLE_W + NET_HIT_TOLERANCE then
            local hit_pos = (bx + BALL_SIZE_HALF - player_x) / PADDLE_W
            if hit_pos < 0.05 then hit_pos = 0.05
            elseif hit_pos > 0.95 then hit_pos = 0.95 end
            local offset = (hit_pos - 0.5) * 2
            vx = offset * 4.8
            vy = -4
            by = PADDLE_BOTTOM - BALL_SIZE - 1
        end
    end
    
    -- 得分检测
    local score_updated = false
    local need_reset = false
    local is_game_over = false
    
    if by < 0 then
        -- 玩家得分（球出顶部）
        state.player_score = state.player_score + 1
        score_updated = true
        if state.player_score >= state.max_score then
            state.game_state = "gameover"
            is_game_over = true
        else
            need_reset = true
        end
    elseif by > CONTAINER_H then
        -- 对手得分（球出底部）
        state.peer_score = state.peer_score + 1
        score_updated = true
        if state.peer_score >= state.max_score then
            state.game_state = "gameover"
            is_game_over = true
        else
            need_reset = true
        end
    end
    
    -- 更新UI：先更新分数
    if score_updated then
        net_update_score()
    end
    
    -- 游戏结束处理
    if is_game_over then
        -- 停止球移动
        state.ball_vx = 0
        state.ball_vy = 0
        
        -- 更新球位置（停止在边界）
        if by < 0 then by = 0 end
        if by > CONTAINER_H then by = CONTAINER_H - BALL_SIZE end
        state.ball_x, state.ball_y = bx, by
        
        -- 更新球显示
        safe_update_container(state.ball_obj, bx, by)
        
        -- 广播游戏结束状态给对手
        expvp.broadcast_to_room({
            type = "full_state",
            from = state.my_device_id,
            ball_x = state.ball_x,
            ball_y = state.ball_y,
            ball_vx = state.ball_vx,
            ball_vy = state.ball_vy,
            player_paddle_x = state.player_paddle_x,
            peer_paddle_x = state.peer_paddle_x,
            player_score = state.player_score,
            peer_score = state.peer_score,
            game_state = state.game_state
        })
        
        -- 显示结果并在3秒后返回房间
        net_schedule_back_to_room(state.player_score >= state.max_score and "你获胜了！" or "对手获胜！")
        return
    end
    
    -- 更新状态
    state.ball_x, state.ball_y = bx, by
    state.ball_vx, state.ball_vy = vx, vy
    
    -- 需要重置游戏时再重置
    if need_reset then
        net_reset_game()
        return
    end
    
    -- 更新UI
    safe_update_container(state.ball_obj, bx, by)
end

local function net_move_paddle_to(x, force_send)
    if not net_state.game_started or net_state.current_page ~= "game" then return end
    
    local content_padding = 2
    local container_w = SCREEN_W - content_padding * 2
    local container_h = SCREEN_H - content_padding * 2
    net_state.player_paddle_x = clamp(x - PADDLE_W / 2, 5, container_w - 5 - PADDLE_W)
    
    -- 根据是否是房主设置玩家球拍的Y坐标
    local player_paddle_y
    if net_state.is_host then
        player_paddle_y = container_h - 38
    else
        player_paddle_y = 24
    end
    
    -- 本地球拍立即更新，保证自己操作跟手
    safe_update_container(net_state.player_paddle_obj, net_state.player_paddle_x, player_paddle_y)
    
    -- 球拍网络同步节流：减少拖动时的消息堆积，但保留明显位移和按下首包
    local send_counter = net_state.paddle_send_counter or 0
    send_counter = send_counter + 1
    net_state.paddle_send_counter = send_counter
    
    local last_x = net_state.last_sent_paddle_x
    local need_send = force_send or not last_x or math.abs(net_state.player_paddle_x - last_x) >= 8 or (send_counter % 2 == 0)
    if not need_send then return end
    
    net_state.last_sent_paddle_x = net_state.player_paddle_x
    net_state.paddle_seq = (net_state.paddle_seq or 0) + 1
    expvp.broadcast_to_room({
        type = "paddle",
        paddle = { x = net_state.player_paddle_x },
        seq = net_state.paddle_seq,
        from = net_state.my_device_id
    })
end

-- 预计算同步频率常量
local SYNC_INTERVAL = 2  -- 每2帧同步一次（约30fps）

local function net_game_loop()
    local state = net_state
    if state.return_room_pending then return end
    
    if state.is_host then
        -- 房主：更新球的物理
        net_update_ball()
        
        -- 帧计数和同步
        local cnt = state.sync_frame_counter
        if not cnt then cnt = 0 end
        cnt = cnt + 1
        state.sync_frame_counter = cnt
        
        -- 每SYNC_INTERVAL帧同步一次
        if cnt % SYNC_INTERVAL == 0 then
            expvp.broadcast_to_room({
                type = "full_state",
                from = state.my_device_id,
                ball_x = state.ball_x,
                ball_y = state.ball_y,
                ball_vx = state.ball_vx,
                ball_vy = state.ball_vy,
                player_paddle_x = state.player_paddle_x,
                peer_paddle_x = state.peer_paddle_x,
                player_score = state.player_score,
                peer_score = state.peer_score,
                game_state = state.game_state
            })
        end
    else
        -- 非房主：显示球平滑层
        if state.game_state == "playing" and state.ball_vx and state.ball_vy then
            -- 逻辑球继续做短时间轻量预测，避免跑偏
            local predict_frames = state.predict_frames_since_sync or 0
            if predict_frames < MAX_CLIENT_PREDICT_FRAMES then
                local bx = state.ball_x + state.ball_vx
                local by = state.ball_y + state.ball_vy
                
                -- 快速边界检测
                if bx < 0 then bx = 0
                elseif bx + BALL_SIZE > CONTAINER_W then bx = CONTAINER_W - BALL_SIZE end
                
                if by < 0 then by = 0
                elseif by + BALL_SIZE > CONTAINER_H then by = CONTAINER_H - BALL_SIZE end
                
                state.predict_frames_since_sync = predict_frames + 1
                state.ball_x, state.ball_y = bx, by
                state.target_ball_x, state.target_ball_y = bx, by
            end
            
            -- 显示球向目标平滑追踪，避免收到状态时跳变
            local dx = state.target_ball_x - state.display_ball_x
            local dy = state.target_ball_y - state.display_ball_y
            local dist = math.sqrt(dx * dx + dy * dy)
            
            if dist > DISPLAY_SNAP_DISTANCE then
                -- 差距过大直接校正
                state.display_ball_x = state.target_ball_x
                state.display_ball_y = state.target_ball_y
            else
                -- 误差小时贴得快，误差大时贴得慢，减少视觉拉扯
                local factor = dist < 25 and DISPLAY_SMOOTH_FAST or DISPLAY_SMOOTH_SLOW
                state.display_ball_x = state.display_ball_x + dx * factor
                state.display_ball_y = state.display_ball_y + dy * factor
            end
            
            safe_update_container(state.ball_obj, state.display_ball_x, state.display_ball_y)
        elseif state.game_state == "ready" then
            -- ready 状态保持显示和目标一致
            state.display_ball_x = state.target_ball_x
            state.display_ball_y = state.target_ball_y
            safe_update_container(state.ball_obj, state.display_ball_x, state.display_ball_y)
        end
    end
end

local function create_net_game_ui()
    -- 游戏区域容器
    local content_padding = 2
    local container_w = SCREEN_W - content_padding * 2
    local container_h = SCREEN_H - content_padding * 2
    
    -- 确保主容器也不可滚动
    if main_container then
        main_container.scrollable = false
    end
    
    net_state.game_container = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0x0d1117,
        parent = main_container,
        scrollable = false,
        clip = true  -- 启用裁剪，防止子元素超出边界
    })
    
    -- 游戏区域容器
    local game_area = airui.container({
        x = content_padding,
        y = content_padding,
        w = container_w,
        h = container_h,
        color = 0x0d1117,
        parent = net_state.game_container,
        scrollable = false,
        clip = true  -- 启用裁剪
    })
    
    -- 创建网格背景
    local grid_size = 16
    local max_x = (container_w // grid_size) * grid_size
    local max_y = (container_h // grid_size) * grid_size
    
    for y = 0, max_y, grid_size do
        airui.container({
            parent = game_area,
            x = 0,
            y = y,
            w = container_w,
            h = 1,
            color = 0x21262d,
            opacity = 0.3
        })
    end
    for x = 0, max_x, grid_size do
        airui.container({
            parent = game_area,
            x = x,
            y = 0,
            w = 1,
            h = container_h,
            color = 0x21262d,
            opacity = 0.3
        })
    end
    
    -- 返回按钮（左上角圆形按钮）
    local back_btn = airui.container({
        parent = game_area,
        x = 4,
        y = 4,
        w = 36,
        h = 36,
        color = 0x21262d,
        opacity = 0.85,
        radius = 18,
        on_click = function()
            log.info("PINBALL", "游戏界面返回按钮被点击")
            send_opponent_left()
            if net_state.current_room_id then
                expvp.leave_room()
            end
            show_menu()
        end
    })
    
    -- 返回箭头
    airui.label({
        parent = back_btn,
        x = 8,
        y = 6,
        w = 20,
        h = 24,
        text = "<",
        font_size = 20,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 分数标签位置：固定显示，顶部是玩家（加入者）分数，底部是房主分数
    -- 双方看到的分数位置一致，不需要翻转
    local peer_score_y = math.floor(container_h / 2 - 70)  -- 玩家（顶部球拍）分数在上方
    local player_score_y = math.floor(container_h / 2 + 15)  -- 房主（底部球拍）分数在下方
    
    -- 对手分数标签（玩家/加入者分数）
    net_state.peer_score_label = airui.label({
        parent = game_area,
        x = math.floor(container_w / 2 - 25),
        y = peer_score_y,
        w = 50,
        h = 45,
        text = "0",
        font_size = 36,
        color = 0xffd700,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 玩家分数标签
    net_state.player_score_label = airui.label({
        parent = game_area,
        x = math.floor(container_w / 2 - 25),
        y = player_score_y,
        w = 50,
        h = 45,
        text = "0",
        font_size = 36,
        color = 0xffd700,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 中线（虚线）
    local dash_gap = 8
    for i = 0, container_w // (dash_gap * 2) do
        airui.container({
            parent = game_area,
            x = i * dash_gap * 2,
            y = container_h / 2 - 1,
            w = dash_gap,
            h = 2,
            color = 0x30363d,
            opacity = 0.5
        })
    end
    
    -- 球拍位置：固定位置，房主在底部（蓝色），玩家在顶部（橙色）
    -- 房主视角：自己在底部，对手在顶部
    -- 玩家视角：自己在顶部，对手在底部
    local player_paddle_y, peer_paddle_y
    local player_color, peer_color
    
    if net_state.is_host then
        -- 房主：自己在底部，蓝色球拍
        player_paddle_y = container_h - 38
        peer_paddle_y = 24
        player_color = 0x3b82f6  -- 蓝色
        peer_color = 0xff6b35    -- 橙色
    else
        -- 非房主：自己在顶部，橙色球拍
        player_paddle_y = 24
        peer_paddle_y = container_h - 38
        player_color = 0xff6b35  -- 橙色
        peer_color = 0x3b82f6    -- 蓝色
    end
    
    -- 玩家球拍
    net_state.player_paddle_obj = airui.container({
        parent = game_area,
        x = math.floor((container_w - PADDLE_W) / 2),
        y = player_paddle_y,
        w = PADDLE_W,
        h = PADDLE_H,
        color = player_color,
        radius = 7
    })
    
    -- 对手球拍
    net_state.peer_paddle_obj = airui.container({
        parent = game_area,
        x = math.floor((container_w - PADDLE_W) / 2),
        y = peer_paddle_y,
        w = PADDLE_W,
        h = PADDLE_H,
        color = peer_color,
        radius = 7
    })
    
    -- 球
    net_state.ball_obj = airui.container({
        parent = game_area,
        x = math.floor((container_w - BALL_SIZE) / 2),
        y = math.floor(container_h / 2 - BALL_SIZE / 2),
        w = BALL_SIZE,
        h = BALL_SIZE,
        color = 0xffd700,
        radius = BALL_SIZE / 2
    })
end

local function net_touch_handler(state_tp, x, y, track_id)
    if not net_state.valid or net_state.current_page ~= "game" then return end
    
    local is_down = (airui.TP_DOWN and state_tp == airui.TP_DOWN) or (state_tp == 1)
    local is_hold = (airui.TP_HOLD and state_tp == airui.TP_HOLD) or (state_tp == 2)
    local is_up = (airui.TP_UP and state_tp == airui.TP_UP) or (state_tp == 0)
    
    if is_down then
                    -- 点击时立即移动球拍，并强制同步首包
                    net_move_paddle_to(x, true)
                    
                    if net_state.game_state == "ready" then
                        -- 发球：点击屏幕开始游戏（只有房主可以）
                        if net_state.is_host then
                            local angle = (math.random() - 0.5) * 60
                            local speed = 4
                            net_state.ball_vx = speed * math.sin(math.rad(angle))
                            net_state.ball_vy = -math.abs(speed * math.cos(math.rad(angle)))
                            net_state.game_state = "playing"
                            -- 广播状态给对手
                            expvp.broadcast_to_room({
                                type = "full_state",
                                from = net_state.my_device_id,
                                ball_x = net_state.ball_x,
                                ball_y = net_state.ball_y,
                                ball_vx = net_state.ball_vx,
                                ball_vy = net_state.ball_vy,
                                player_paddle_x = net_state.player_paddle_x,
                                peer_paddle_x = net_state.peer_paddle_x,
                                player_score = net_state.player_score,
                                peer_score = net_state.peer_score,
                                game_state = net_state.game_state
                            })
                        else
                            show_toast("等待房主发球")
                        end
                    end
    elseif is_hold then
        -- 按住时持续移动球拍
        net_move_paddle_to(x)
    elseif is_up then
        -- 松手时强制同步最终位置，避免对方停留在旧球拍坐标
        net_move_paddle_to(x, true)
    end
end

local function init_network()
    log.info("PINBALL", "Initializing network...")
    
    if not expvp_initialized then
        local ok, err = expvp.init({
            game_name = "pinball_war",
            score_cls = 1,
            room_max_players = 2
        })
        
        if not ok then
            log.error("PINBALL", "expvp init failed:", err)
        end
        
        expvp.on(function(event, payload)
            if not net_state.valid then
                return
            end
            
            if event == "connect" then
                log.info("PINBALL", "Network connected")
                net_state.network_connected = true
                if net_state.lbl_status then
                    safe_update_label(net_state.lbl_status, "已连接到服务器")
                end
            elseif event == "disconnect" then
                log.info("PINBALL", "Network disconnected")
                net_state.network_connected = false
                if net_state.lbl_status then
                    safe_update_label(net_state.lbl_status, "未连接到服务器")
                end
            elseif event == "room_created" then
                log.info("PINBALL", "Room created")
                -- 隐藏主菜单，显示房间等待界面
                if net_state.menu_container and not net_state.menu_container:is_hidden() then
                    pcall(function() net_state.menu_container:hide() end)
                end
                show_room_waiting_ui()
                update_room_ui()
                show_toast("房间已创建，等待其他玩家加入...")
            elseif event == "room_joined" then
                log.info("PINBALL", "Room joined")
                if net_state.join_dialog_container then
                    pcall(function() net_state.join_dialog_container:destroy() end)
                    net_state.join_dialog_container = nil
                end
                -- 隐藏主菜单，显示房间等待界面
                if net_state.menu_container and not net_state.menu_container:is_hidden() then
                    pcall(function() net_state.menu_container:hide() end)
                end
                show_room_waiting_ui()
                update_room_ui()
                show_toast("成功加入房间！")
            elseif event == "room_left" then
                log.info("PINBALL", "Room left")
                net_state.current_room_id = nil
                net_state.my_ready = false
                net_state.is_host_player = false
                -- 显示主菜单
                if net_state.menu_container and net_state.menu_container:is_hidden() then
                    pcall(function() net_state.menu_container:show() end)
                end
                hide_room_waiting_ui()
            elseif event == "peer_join" then
                log.info("PINBALL", "玩家加入房间:", payload.nickname or payload.device_id)
                net_state.peer_id = payload.device_id
                update_room_ui()
            elseif event == "peer_leave" then
                log.info("PINBALL", "玩家离开房间:", payload.device_id)
                net_state.peer_id = nil
                net_state.peer_ready = false
                update_room_ui()
                if net_state.current_page == "game" then
                    net_state.game_state = "gameover"
                    show_toast("对方已退出游戏")
                    sys.timerStart(function()
                        show_menu()
                    end, 1500)
                end
            elseif event == "peer_ready" then
                log.info("PINBALL", "玩家准备状态:", payload.device_id, payload.ready)
                net_state.peer_ready = payload.ready
                update_room_ui()
            elseif event == "game_start" then
                log.info("PINBALL", "收到游戏开始通知")
                -- 使用官方方法获取房主身份
                local room_info = expvp.get_room_info()
                local assignments = payload.player_assignments or {}
                net_state.my_player_number = assignments[net_state.my_device_id] or 1
                net_state.is_host = room_info.is_host
                log.info("PINBALL", "房主身份判断: is_host=" .. tostring(net_state.is_host))
                
                hide_room_waiting_ui()
                if net_state.menu_container then
                    pcall(function() net_state.menu_container:hide() end)
                end
                create_net_game_ui()
                
                net_state.current_page = "game"  -- 关键修复：设为游戏页状态
                net_state.game_state = "ready"
                net_state.game_started = true
                net_state.player_score = 0
                net_state.peer_score = 0
                net_state.predict_frames_since_sync = 0
                net_state.paddle_send_counter = 0
                net_state.last_sent_paddle_x = nil
                net_update_score()
                net_reset_game()
                
                -- 启动游戏循环
                net_state.game_timer = sys.timerLoopStart(net_game_loop, 16)
                
                -- 订阅触摸事件
                airui.touch_subscribe(net_touch_handler)
                
                -- 房主立即广播一次 full_state，让非房主初始化球状态
                if net_state.is_host then
                    sys.timerStart(function()
                        expvp.broadcast_to_room({
                            type = "full_state",
                            from = net_state.my_device_id,  -- 添加发送者ID
                            ball_x = net_state.ball_x,
                            ball_y = net_state.ball_y,
                            ball_vx = net_state.ball_vx,
                            ball_vy = net_state.ball_vy,
                            player_paddle_x = net_state.player_paddle_x,
                            peer_paddle_x = net_state.peer_paddle_x,
                            player_score = net_state.player_score,
                            peer_score = net_state.peer_score,
                            game_state = net_state.game_state
                        })
                    end, 100)  -- 延迟 100ms，确保非房主准备好了
                end
                
            elseif event == "message" then
                local data = payload
                
                if data.type == "opponent_left" then
                    log.info("PINBALL", "收到对手退出通知")
                    net_state.peer_id = nil
                    net_state.peer_ready = false
                    if net_state.current_page == "lobby" or net_state.current_page == "room" then
                        update_room_ui()
                        show_toast("对方已离开房间")
                    elseif net_state.current_page == "game" then
                        show_toast("对方已退出游戏")
                        sys.timerStart(function()
                            show_menu()
                        end, 1500)
                    end
                    return
                end
                
                if not net_state.game_started or net_state.current_page ~= "game" then return end
                
                if data.type == "paddle" and data.paddle and data.from and data.from ~= net_state.my_device_id then
                    local seq = data.seq or 0
                    if seq >= (net_state.last_peer_paddle_seq or 0) then
                        net_state.last_peer_paddle_seq = seq
                        local content_padding = 2
                        local container_w = SCREEN_W - content_padding * 2
                        local container_h = SCREEN_H - content_padding * 2
                        net_state.peer_paddle_x = clamp(data.paddle.x, 5, container_w - 5 - PADDLE_W)
                        -- 根据是否是房主设置对手球拍的Y坐标
                        local peer_paddle_y
                        if net_state.is_host then
                            peer_paddle_y = 24
                        else
                            peer_paddle_y = container_h - 38
                        end
                        safe_update_container(net_state.peer_paddle_obj, net_state.peer_paddle_x, peer_paddle_y)
                    end
                end
                
                if data.type == "full_state" then
                    -- 检查是否是自己发送的消息，如果是就忽略
                    if data.from and data.from == net_state.my_device_id then
                        return
                    end
                    
                    -- 更新球的状态：双方视角一致，不需要翻转
                    if net_state.is_host then
                        -- 房主：直接使用收到的球坐标（其实房主不应该收到这个消息）
                        net_state.ball_x = data.ball_x
                        net_state.ball_y = data.ball_y
                        net_state.ball_vx = data.ball_vx
                        net_state.ball_vy = data.ball_vy
                        safe_update_container(net_state.ball_obj, net_state.ball_x, net_state.ball_y)
                    else
                        -- 非房主：更新逻辑球和显示目标，不再直接改变显示位置
                        net_state.ball_x = data.ball_x
                        net_state.ball_y = data.ball_y
                        net_state.target_ball_x = data.ball_x
                        net_state.target_ball_y = data.ball_y
                        if not net_state.display_ball_x or not net_state.display_ball_y then
                            net_state.display_ball_x = data.ball_x
                            net_state.display_ball_y = data.ball_y
                        end
                        
                        -- 更新速度并重置短预测计数
                        net_state.ball_vx = data.ball_vx
                        net_state.ball_vy = data.ball_vy
                        net_state.predict_frames_since_sync = 0
                    end
                    
                    -- 同步房主状态包里的球拍坐标，保证视觉位置和房主碰撞逻辑一致
                    if data.player_paddle_x ~= nil or data.peer_paddle_x ~= nil then
                        local content_padding = 2
                        local container_w = SCREEN_W - content_padding * 2
                        local container_h = SCREEN_H - content_padding * 2
                        if net_state.is_host then
                            if data.peer_paddle_x ~= nil then
                                net_state.peer_paddle_x = clamp(data.peer_paddle_x, 5, container_w - 5 - PADDLE_W)
                                safe_update_container(net_state.peer_paddle_obj, net_state.peer_paddle_x, 24)
                            end
                        else
                            if data.player_paddle_x ~= nil then
                                net_state.peer_paddle_x = clamp(data.player_paddle_x, 5, container_w - 5 - PADDLE_W)
                                safe_update_container(net_state.peer_paddle_obj, net_state.peer_paddle_x, container_h - 38)
                            end
                        end
                    end
                    
                    -- 更新分数：双方视角一致，不需要交换
                    -- player_score 是房主得分（底部），peer_score 是玩家得分（顶部）
                    if data.player_score ~= nil then
                        net_state.player_score = data.player_score  -- 房主得分
                    end
                    if data.peer_score ~= nil then
                        net_state.peer_score = data.peer_score      -- 玩家得分
                    end
                    net_update_score()
                    
                    -- 更新游戏状态
                    if data.game_state then
                        net_state.game_state = data.game_state
                        if data.game_state == "gameover" then
                            local result_text = "游戏结束"
                            if net_state.is_host then
                                result_text = net_state.player_score >= net_state.max_score and "你获胜了！" or "对手获胜！"
                            else
                                result_text = net_state.peer_score >= net_state.max_score and "你获胜了！" or "对手获胜！"
                            end
                            net_schedule_back_to_room(result_text)
                        end
                    end
                end
            end
        end)
        
        expvp.start()
        
        local function sendPresence()
            if not net_state.valid then return end
            local player_info = expvp.get_player_info()
            expvp.send_presence({
                type = "presence",
                device_id = player_info.device_id,
                device_model = player_info.device_model,
                nickname = player_info.nickname,
                timestamp = os.time()
            })
        end
        
        sys.timerStart(sendPresence, 5000)
        
        expvp_initialized = true
    end
    
    if not net_state.my_device_id then
        net_state.my_device_id = get_device_id()
    end
    log.info("PINBALL", "Network initialized, device_id:", net_state.my_device_id)
end

function show_net_game()
    current_page = "net"
    destroy_page()
    
    net_state.valid = true
    
    if not net_state.my_device_id then
        net_state.my_device_id = get_device_id()
    end
    
    -- 初始化网络（先初始化，再创建UI）
    init_network()
    
    -- 创建联网菜单容器
    net_state.menu_container = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0x0a0a1a,
        scrollable = false
    })
    
    local header = airui.container({
        parent = net_state.menu_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 50,
        color = 0x1a365d,
        scrollable = false
    })
    
    local back_btn = airui.container({
        parent = header,
        x = 10,
        y = 10,
        w = 70,
        h = 30,
        color = 0x3b82f6,
        radius = 15,
        on_click = function()
            log.info("PINBALL", "返回主菜单")
            show_menu()
        end
    })
    airui.label({
        parent = back_btn,
        x = 0,
        y = 3,
        w = 70,
        h = 24,
        text = "返回",
        font_size = 14,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    airui.label({
        parent = header,
        x = 85,
        y = 10,
        w = 150,
        h = 30,
        text = "联网对战",
        font_size = 18,
        color = 0xff6b35,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    net_state.lbl_status = airui.label({
        parent = net_state.menu_container,
        x = 0,
        y = 60,
        w = SCREEN_W,
        h = 25,
        text = "正在连接服务器...",
        font_size = 14,
        color = 0xffd700,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    local btn_x = (SCREEN_W - 200) / 2
    
    -- 创建房间按钮
    airui.container({
        parent = net_state.menu_container,
        x = btn_x,
        y = 150,
        w = 200,
        h = 50,
        color = 0x3b82f6,
        radius = 25,
        on_click = function()
            log.info("PINBALL", "创建房间")
            net_state.my_ready = false
            net_state.is_host_player = true
            net_state.current_room_id = expvp.create_room()
            if net_state.current_room_id then
                log.info("PINBALL", "房间创建成功:", net_state.current_room_id)
                show_room_waiting_ui()
                update_room_ui()
                show_toast("房间已创建，等待其他玩家加入...")
            else
                show_toast("创建房间失败")
            end
        end
    })
    airui.label({
        parent = net_state.menu_container,
        x = btn_x,
        y = 165,
        w = 200,
        h = 20,
        text = "创建房间",
        font_size = 17,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 加入房间按钮
    airui.container({
        parent = net_state.menu_container,
        x = btn_x,
        y = 220,
        w = 200,
        h = 50,
        color = 0xf97316,
        radius = 25,
        on_click = function()
            log.info("PINBALL", "加入房间")
            show_join_dialog()
        end
    })
    airui.label({
        parent = net_state.menu_container,
        x = btn_x,
        y = 235,
        w = 200,
        h = 20,
        text = "加入房间",
        font_size = 17,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
end

function show_join_dialog()
    -- 清理已存在的对话框
    if net_state.join_dialog_container then
        pcall(function() net_state.join_dialog_container:destroy() end)
        net_state.join_dialog_container = nil
    end
    net_state.join_input_text = ""
    
    -- 全屏对话框，适配320x480屏幕
    net_state.join_dialog_container = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0x1a1a2e
    })
    
    -- 标题
    airui.label({
        parent = net_state.join_dialog_container,
        x = 0,
        y = 30,
        w = SCREEN_W,
        h = 40,
        text = "加入房间",
        font_size = 24,
        color = 0xf0c040,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 提示
    airui.label({
        parent = net_state.join_dialog_container,
        x = 20,
        y = 80,
        w = SCREEN_W - 40,
        h = 24,
        text = "请输入房主分享的6位房间码",
        font_size = 14,
        color = 0xaaaaaa,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 输入框显示
    net_state.join_input_label = airui.label({
        parent = net_state.join_dialog_container,
        x = 20,
        y = 120,
        w = SCREEN_W - 40,
        h = 40,
        text = "|",
        font_size = 24,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 数字键盘（适配320x480屏幕）
    local kb_start_x = 35
    local kb_start_y = 180
    local kb_w = 80
    local kb_h = 45
    local kb_gap = 15
    
    -- 1-9
    for row = 0, 2 do
        for col = 0, 2 do
            local num = row * 3 + col + 1
            airui.button({
                parent = net_state.join_dialog_container,
                x = kb_start_x + col * (kb_w + kb_gap),
                y = kb_start_y + row * (kb_h + kb_gap),
                w = kb_w,
                h = kb_h,
                text = tostring(num),
                font_size = 22,
                style = {bg_color = 0x333333, text_color = 0xffffff, border_width = 0, radius = 8},
                on_click = function()
                    if #net_state.join_input_text < 6 then
                        net_state.join_input_text = net_state.join_input_text .. tostring(num)
                        safe_update_label(net_state.join_input_label, net_state.join_input_text .. "|")
                    end
                end
            })
        end
    end
    
    -- 0
    airui.button({
        parent = net_state.join_dialog_container,
        x = kb_start_x + (kb_w + kb_gap),
        y = kb_start_y + 3 * (kb_h + kb_gap),
        w = kb_w,
        h = kb_h,
        text = "0",
        font_size = 22,
        style = {bg_color = 0x333333, text_color = 0xffffff, border_width = 0, radius = 8},
        on_click = function()
            if #net_state.join_input_text < 6 then
                net_state.join_input_text = net_state.join_input_text .. "0"
                safe_update_label(net_state.join_input_label, net_state.join_input_text .. "|")
            end
        end
    })
    
    -- 删除
    airui.button({
        parent = net_state.join_dialog_container,
        x = kb_start_x + 2 * (kb_w + kb_gap),
        y = kb_start_y + 3 * (kb_h + kb_gap),
        w = kb_w,
        h = kb_h,
        text = "删除",
        font_size = 16,
        style = {bg_color = 0x884444, text_color = 0xffffff, border_width = 0, radius = 8},
        on_click = function()
            if #net_state.join_input_text > 0 then
                net_state.join_input_text = net_state.join_input_text:sub(1, -2)
                safe_update_label(net_state.join_input_label, #net_state.join_input_text > 0 and (net_state.join_input_text .. "|") or "|")
            end
        end
    })
    
    -- 取消按钮
    airui.button({
        parent = net_state.join_dialog_container,
        x = 20,
        y = kb_start_y + 4 * (kb_h + kb_gap) + 15,
        w = (SCREEN_W - 50) / 2,
        h = 45,
        text = "取消",
        font_size = 18,
        style = {bg_color = 0x444444, text_color = 0xffffff, border_width = 0, radius = 8},
        on_click = function()
            if net_state.join_dialog_container then
                pcall(function() net_state.join_dialog_container:destroy() end)
                net_state.join_dialog_container = nil
                net_state.join_input_label = nil
            end
            net_state.join_input_text = ""
        end
    })
    
    -- 确认加入按钮
    airui.button({
        parent = net_state.join_dialog_container,
        x = SCREEN_W / 2 + 5,
        y = kb_start_y + 4 * (kb_h + kb_gap) + 15,
        w = (SCREEN_W - 50) / 2,
        h = 45,
        text = "确认加入",
        font_size = 18,
        style = {bg_color = 0x3b82f6, text_color = 0xffffff, border_width = 0, radius = 8},
        on_click = function()
            if #net_state.join_input_text == 6 then
                local room_id = "room_" .. net_state.join_input_text
                net_state.my_ready = false
                net_state.is_host_player = false
                expvp.join_room(room_id)
                net_state.current_room_id = room_id
                if net_state.join_dialog_container then
                    pcall(function() net_state.join_dialog_container:destroy() end)
                    net_state.join_dialog_container = nil
                    net_state.join_input_label = nil
                end
                show_room_waiting_ui()
                update_room_ui()
                show_toast("已加入房间，请点击准备")
            else
                show_toast("请输入6位房间号")
            end
        end
    })
end

-- ==================== 窗口管理函数 ====================

local function menu_on_create()
    -- 创建主容器（窗口根容器）
    main_container = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0x1a1a2e,
        scrollable = false
    })
    
    -- 显示菜单
    show_menu()
end

local function menu_on_destroy()
    destroyed = true
    
    -- 停止菜单动画定时器
    if menu_timer then
        sys.timerStop(menu_timer)
        menu_timer = nil
    end
    
    -- 清理当前页面
    destroy_current_page()
    
    -- 确保所有UI组件正确销毁
    if main_container then
        pcall(function() main_container:destroy() end)
        main_container = nil
    end
    
    -- 清除窗口引用
    win_id = nil
end

local function menu_on_get_focus() end
local function menu_on_lose_focus() end

local function menu_open_handler()
    if win_id then
        return
    end
    win_id = exwin.open({
        on_create = menu_on_create,
        on_destroy = menu_on_destroy,
        on_get_focus = menu_on_get_focus,
        on_lose_focus = menu_on_lose_focus,
    })
end

sys.subscribe("OPEN_PINBALL_WAR_MENU", menu_open_handler)

-- ==================== 兼容原有接口 ====================
-- 保持与原有三个模块相同的对外接口

local page_container = nil
local current_page = nil

local function destroy_current_page()
    log.info("MENU", "destroy_current_page called for page:", current_page)
    
    if current_page == "game" then
        pcall(function()
            if _G.game_destroy then
                _G.game_destroy()
            end
        end)
    elseif current_page == "net" then
        pcall(function()
            if _G.net_destroy then
                _G.net_destroy()
            end
        end)
    end
    
    if page_container then
        pcall(function()
            page_container:destroy()
        end)
        page_container = nil
    end
    
    current_page = nil
    log.info("MENU", "destroy_current_page completed")
end

local function switch_to_menu()
    destroy_current_page()
    if menu_root then
        menu_root:open()
    end
    if menu_timer then
        sys.timerStop(menu_timer)
    end
    menu_timer = sys.timerLoopStart(on_menu_tick, 16)
    current_page = "menu"
end

local function switch_to_game()
    if current_page == "game" then return end
    if _G.set_difficulty then
        _G.set_difficulty(current_difficulty)
    end

    if menu_root then
        menu_root:hide()
    end
    if menu_timer then
        sys.timerStop(menu_timer)
        menu_timer = nil
    end

    destroy_current_page()

    page_container = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = SCREEN_W, h = SCREEN_H,
        color = 0x000000,
        opacity = 0
    })

    current_page = "game"
    game_create(page_container, switch_to_menu)
end

local function switch_to_net()
    if current_page == "net" then
        return
    end
    
    if menu_root then
        menu_root:hide()
    end
    if menu_timer then
        sys.timerStop(menu_timer)
        menu_timer = nil
    end
    
    destroy_current_page()
    
    page_container = airui.container({
        parent = main_container,
        x = 0, y = 0, w = SCREEN_W, h = SCREEN_H,
        color = 0x000000, opacity = 0
    })
    
    current_page = "net"
    net_create(page_container, switch_to_menu)
end

_G.pinball_switch_to_menu = switch_to_menu
_G.pinball_switch_to_net = switch_to_net

sys.subscribe("OPEN_PINBALL_NET_WIN", function()
    log.info("MENU", "Received OPEN_PINBALL_NET_WIN event")
    switch_to_net()
end)

-- ==================== pinball_win 兼容接口 ====================
local pinball_on_back_callback = nil
local pinball_main_container = nil
local pinball_player_score = 0
local pinball_ai_score = 0
local pinball_game_state = "ready"
local pinball_game_timer = nil

function game_create(parent, on_back)
    pinball_on_back_callback = on_back
    single_current_difficulty = current_difficulty
    
    -- 停止菜单动画
    if menu_timer then
        sys.timerStop(menu_timer)
        menu_timer = nil
    end
    
    -- 显示单机游戏
    show_single_game(parent, function()
        if pinball_on_back_callback then
            pinball_on_back_callback()
        end
    end)
end

function game_destroy()
    destroy_single_game()
end

_G.set_difficulty = function(diff)
    current_difficulty = diff
    single_current_difficulty = diff
end

-- ==================== pinball_net 兼容接口 ====================
local net_on_back_callback = nil

function net_create(parent, on_back)
    net_on_back_callback = on_back
    
    -- 停止菜单动画
    if menu_timer then
        sys.timerStop(menu_timer)
        menu_timer = nil
    end
    
    show_net_game(parent, function()
        if net_on_back_callback then
            net_on_back_callback()
        end
    end)
end

function net_destroy()
    destroy_net_game()
end

-- ==================== 导出接口 ====================

return {
    create_window = create_game_window,
    destroy_window = destroy_game_window
}