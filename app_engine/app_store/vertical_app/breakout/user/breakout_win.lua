--[[
@module  breakout_win
@summary 打砖块游戏窗口模块
@version 1.0.1
@date    2026.04.23
@author  王世豪
]]

local win_id = nil
local main_container = nil
local game_area = nil

-- 游戏常量
local SCREEN_W = 480
local SCREEN_H = 800
local HEADER_H = 60
local GAME_AREA_Y = 60
local GAME_AREA_H = 740
local PADDLE_W = 100
local PADDLE_H = 16
local PADDLE_Y = 570
local BALL_SIZE = 14
local BRICK_W = 40
local BRICK_H = 20
local BRICK_ROWS = 6
local BRICK_COLS = 10
local BRICK_GAP_X = 4
local BRICK_GAP_Y = 4
local BRICK_START_Y = 20

-- 颜色定义
local COLOR_BG = 0x1a1a2e
local COLOR_PADDLE = 0x4a90e2
local COLOR_BALL = 0xf5f5f5
local COLOR_BRICKS = {
    0xff6b6b, -- 红色
    0xff9f43, -- 橙色
    0xfeca57, -- 黄色
    0x1dd1a1, -- 绿色
    0x54a0ff, -- 蓝色
    0xa55eea, -- 紫色
}

-- 游戏状态
local game_state = "ready" -- ready, playing, paused, gameover, victory
local score = 0
local lives = 3
local level = 1

-- 游戏对象
local paddle = { x = 0, obj = nil }
local ball = { x = 0, y = 0, vx = 0, vy = 0, obj = nil }
local bricks = {}
local brick_objs = {}

-- UI组件
local score_label = nil
local lives_label = nil
local level_label = nil
local status_label = nil
local game_over_msg = nil

-- 触摸状态
local touch_state = {
    dragging = false,
    track_id = nil,
    offset_x = 0
}

-- 定时器
local game_timer = nil

-- 限制值在范围内
local function clamp(value, min_val, max_val)
    if value < min_val then return min_val end
    if value > max_val then return max_val end
    return value
end

-- 初始化砖块（随机分布）
local function init_bricks()
    log.info("BREAKOUT", "init_bricks called", "level", level)
    bricks = {}
    brick_objs = {}
    
    local start_x = (SCREEN_W - (BRICK_COLS * (BRICK_W + BRICK_GAP_X) - BRICK_GAP_X)) / 2
    
    -- 根据关卡调整砖块密度，关卡越高砖块越多
    local min_brick_ratio = 0.5
    local max_brick_ratio = 0.9
    local brick_ratio = min_brick_ratio + (max_brick_ratio - min_brick_ratio) * math.min(level / 10, 1)
    
    local brick_count = 0
    for row = 1, BRICK_ROWS do
        bricks[row] = {}
        brick_objs[row] = {}
        -- 奇数行和偶数行交错排列
        local offset_x = (row % 2 == 0) and (BRICK_W + BRICK_GAP_X) / 2 or 0
        -- 偶数行少一个砖块，避免超出边界
        local cols_in_row = (row % 2 == 0) and (BRICK_COLS - 1) or BRICK_COLS
        
        for col = 1, cols_in_row do
            -- 随机决定是否创建砖块
            local should_create = math.random() < brick_ratio
            
            -- 随机选择颜色
            local color_index = math.random(#COLOR_BRICKS)
            
            bricks[row][col] = {
                exists = should_create,
                x = start_x + offset_x + (col - 1) * (BRICK_W + BRICK_GAP_X),
                y = BRICK_START_Y + (row - 1) * (BRICK_H + BRICK_GAP_Y),
                color = COLOR_BRICKS[color_index],
                points = (BRICK_ROWS - row + 1) * 10
            }
            if should_create then
                brick_count = brick_count + 1
            end
        end
    end
    
    -- 确保至少有一些砖块存在
    local has_bricks = false
    for row = 1, BRICK_ROWS do
        local cols_in_row = (row % 2 == 0) and (BRICK_COLS - 1) or BRICK_COLS
        for col = 1, cols_in_row do
            if bricks[row][col] and bricks[row][col].exists then
                has_bricks = true
                break
            end
        end
        if has_bricks then break end
    end
    
    -- 如果没有砖块，强制创建一些
    if not has_bricks then
        for row = 1, BRICK_ROWS do
            local cols_in_row = (row % 2 == 0) and (BRICK_COLS - 1) or BRICK_COLS
            for col = 1, cols_in_row do
                if col <= 3 then
                    bricks[row][col].exists = true
                    brick_count = brick_count + 1
                end
            end
        end
    end
    
    log.info("BREAKOUT", "init_bricks finished", "brick_count", brick_count, "has_bricks", has_bricks)
end

-- 创建砖块UI
local function create_brick_ui()
    log.info("BREAKOUT", "create_brick_ui called", "game_area", game_area ~= nil)
    local brick_count = 0
    for row = 1, BRICK_ROWS do
        -- 偶数行列数不同
        local cols_in_row = (row % 2 == 0) and (BRICK_COLS - 1) or BRICK_COLS
        for col = 1, cols_in_row do
            if bricks[row] and bricks[row][col] and bricks[row][col].exists then
                local brick = bricks[row][col]
                brick_objs[row][col] = airui.button({
                    parent = game_area,
                    x = brick.x,
                    y = brick.y,
                    w = BRICK_W,
                    h = BRICK_H,
                    text = "",
                    style = {
                        bg_color = brick.color,
                        border_width = 0,
                        radius = 3,
                    },
                    on_click = function() end
                })
                brick_count = brick_count + 1
            end
        end
    end
    log.info("BREAKOUT", "create_brick_ui finished", "brick_count", brick_count)
end

-- 重置球位置
local function reset_ball()
    ball.x = SCREEN_W / 2
    ball.y = PADDLE_Y - BALL_SIZE - 5
    ball.vx = 0
    ball.vy = 0
    
    if ball.obj then
        ball.obj:set_pos(ball.x, ball.y)
    end
end

-- 发射球
local function launch_ball()
    if game_state ~= "ready" then return end
    
    game_state = "playing"
    local angle = math.random(-60, 60)
    local speed = 5 + level
    ball.vx = speed * math.sin(math.rad(angle))
    ball.vy = -speed * math.cos(math.rad(angle))
    
    if status_label then
        status_label:set_text("")
    end
end

-- 更新UI显示
local function update_ui()
    if score_label then
        score_label:set_text("分数: " .. score)
    end
    if lives_label then
        lives_label:set_text("生命: " .. lives)
    end
    if level_label then
        level_label:set_text("关卡: " .. level)
    end
end

-- 返回按钮点击处理
local function on_exit_btn_click()
    log.info("BREAKOUT", "返回按钮点击")
    if win_id then
        exwin.close(win_id)
    end
end

-- 清理砖块UI
local function clear_brick_ui()
    log.info("BREAKOUT", "clear_brick_ui called")
    local destroy_count = 0
    for row = 1, BRICK_ROWS do
        -- 偶数行列数不同
        local cols_in_row = (row % 2 == 0) and (BRICK_COLS - 1) or BRICK_COLS
        for col = 1, cols_in_row do
            if brick_objs[row] and brick_objs[row][col] then
                brick_objs[row][col]:destroy()
                brick_objs[row][col] = nil
                destroy_count = destroy_count + 1
            end
        end
    end
    log.info("BREAKOUT", "clear_brick_ui finished", "destroy_count", destroy_count)
end

-- 重置拖拽状态（参考 airplane_battle）
local function reset_drag_state()
    touch_state.dragging = false
    touch_state.track_id = nil
    touch_state.offset_x = 0
end

-- 重置触摸状态
local function reset_touch_state()
    reset_drag_state()
end

-- 重置游戏
local function reset_game()
    log.info("BREAKOUT", "reset_game called")
    game_state = "ready"
    score = 0
    lives = 3
    level = 1
    
    reset_touch_state()
    clear_brick_ui()
    init_bricks()
    reset_ball()
    paddle.x = (SCREEN_W - PADDLE_W) / 2
    
    if paddle.obj then
        paddle.obj:set_pos(math.floor(paddle.x), PADDLE_Y)
    end
    
    update_ui()
    create_brick_ui()
    
    if status_label then
        status_label:set_text("点击发射球")
    end
    log.info("BREAKOUT", "reset_game finished")
end

-- 检测球与砖块碰撞
local function check_brick_collision()
    for row = 1, BRICK_ROWS do
        -- 偶数行列数不同
        local cols_in_row = (row % 2 == 0) and (BRICK_COLS - 1) or BRICK_COLS
        for col = 1, cols_in_row do
            local brick = bricks[row] and bricks[row][col]
            if brick and brick.exists then
                -- AABB碰撞检测
                if ball.x + BALL_SIZE > brick.x and
                   ball.x < brick.x + BRICK_W and
                   ball.y + BALL_SIZE > brick.y and
                   ball.y < brick.y + BRICK_H then
                    
                    -- 消除砖块
                    brick.exists = false
                    score = score + brick.points
                    
                    if brick_objs[row] and brick_objs[row][col] then
                        brick_objs[row][col]:destroy()
                        brick_objs[row][col] = nil
                    end
                    
                    -- 反弹球
                    local brick_cx = brick.x + BRICK_W / 2
                    local brick_cy = brick.y + BRICK_H / 2
                    local ball_cx = ball.x + BALL_SIZE / 2
                    local ball_cy = ball.y + BALL_SIZE / 2
                    
                    local dx = math.abs(ball_cx - brick_cx)
                    local dy = math.abs(ball_cy - brick_cy)
                    
                    if dx / BRICK_W > dy / BRICK_H then
                        ball.vx = -ball.vx
                    else
                        ball.vy = -ball.vy
                    end
                    
                    update_ui()
                    
                    -- 检查胜利
                    local remaining = 0
                    for r = 1, BRICK_ROWS do
                        local cols_in_r = (r % 2 == 0) and (BRICK_COLS - 1) or BRICK_COLS
                        for c = 1, cols_in_r do
                            if bricks[r] and bricks[r][c] and bricks[r][c].exists then
                                remaining = remaining + 1
                            end
                        end
                    end
                    
                    if remaining == 0 then
                        game_state = "victory"
                        if status_label then
                            status_label:set_text("胜利！点击进入下一关")
                        end
                    end
                    
                    return
                end
            end
        end
    end
end

-- 检测球与挡板碰撞
local function check_paddle_collision()
    if ball.y + BALL_SIZE >= PADDLE_Y and
       ball.y <= PADDLE_Y + PADDLE_H and
       ball.x + BALL_SIZE >= paddle.x and
       ball.x <= paddle.x + PADDLE_W then
        
        -- 根据击中挡板的位置调整反弹角度
        local hit_pos = (ball.x + BALL_SIZE / 2 - paddle.x) / PADDLE_W
        local angle = (hit_pos - 0.5) * 120 -- -60到60度
        local speed = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
        
        ball.vx = speed * math.sin(math.rad(angle))
        ball.vy = -math.abs(speed * math.cos(math.rad(angle)))
    end
end

-- 更新球位置
local function update_ball()
    if game_state ~= "playing" then return end
    
    ball.x = ball.x + ball.vx
    ball.y = ball.y + ball.vy
    
    -- 墙壁碰撞
    if ball.x <= 0 then
        ball.x = 0
        ball.vx = math.abs(ball.vx)
    elseif ball.x >= SCREEN_W - BALL_SIZE then
        ball.x = SCREEN_W - BALL_SIZE
        ball.vx = -math.abs(ball.vx)
    end
    
    -- 顶部碰撞
    if ball.y <= 0 then
        ball.y = 0
        ball.vy = math.abs(ball.vy)
    end
    
    -- 底部掉落（球相对于 game_area 容器）
    if ball.y > GAME_AREA_H - 50 then
        lives = lives - 1
        log.info("BREAKOUT", "ball dropped", "lives", lives)
        update_ui()
        
        if lives <= 0 then
            game_state = "gameover"
            log.info("BREAKOUT", "game over, state set to gameover")
            if status_label then
                status_label:set_text("游戏结束！点击重新开始")
            end
        else
            game_state = "ready"
            reset_ball()
            paddle.x = (SCREEN_W - PADDLE_W) / 2
            if paddle.obj then
                paddle.obj:set_pos(math.floor(paddle.x), PADDLE_Y)
            end
            if status_label then
                status_label:set_text("点击发射球")
            end
        end
        return
    end
    
    -- 检测碰撞
    check_paddle_collision()
    check_brick_collision()
    
    -- 更新球UI
    if ball.obj then
        ball.obj:set_pos(math.floor(ball.x), math.floor(ball.y))
    end
end

-- 游戏主循环
local function game_loop()
    update_ball()
end

-- 移动挡板到指定位置（参考 airplane_battle）
local function move_paddle_to(x, offset_x)
    if game_state == "paused" then return end
    
    local new_x = x - offset_x
    -- log.info("BREAKOUT", "move_paddle_to", "x", x, "offset_x", offset_x, "new_x", new_x)
    paddle.x = clamp(new_x, 0, SCREEN_W - PADDLE_W)
    -- log.info("BREAKOUT", "move_paddle_to", "clamped_paddle.x", paddle.x)
    
    if paddle.obj then
        paddle.obj:set_pos(math.floor(paddle.x), PADDLE_Y)
    end
    
    -- 球跟随挡板（准备状态）
    if game_state == "ready" then
        ball.x = paddle.x + PADDLE_W / 2 - BALL_SIZE / 2
        if ball.obj then
            ball.obj:set_pos(math.floor(ball.x), math.floor(ball.y))
        end
    end
end

-- 处理触摸抬起
local function on_touch_up(track_id)
    reset_drag_state()
end

-- 创建UI
local function create_ui()
    main_container = airui.container({
        x = 0, y = 0,
        w = SCREEN_W, h = SCREEN_H,
        color = COLOR_BG,
        parent = airui.screen,
        scrollable = false
    })
    
    -- 顶部标题栏
    local header = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = SCREEN_W, h = HEADER_H,
        color = 0x16213e
    })
    
    -- 返回按钮
    airui.button({
        parent = header,
        x = 10, y = 10,
        w = 80, h = 40,
        text = "返回",
        font_size = 16,
        text_color = 0xfefefe,
        bg_color = 0x38bdf8,
        on_click = on_exit_btn_click
    })
    
    -- 标题
    airui.label({
        parent = header,
        x = 120, y = 10,
        w = 240, h = 40,
        text = "打砖块",
        font_size = 24,
        color = 0x38bdf8,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 顶部信息栏
    local info_bar = airui.container({
        parent = main_container,
        x = 0, y = HEADER_H,
        w = SCREEN_W, h = 50,
        color = 0x0f172a
    })
    
    score_label = airui.label({
        parent = info_bar,
        x = 20, y = 10,
        w = 120, h = 30,
        text = "分数: 0",
        font_size = 18,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_LEFT
    })
    
    level_label = airui.label({
        parent = info_bar,
        x = 180, y = 10,
        w = 120, h = 30,
        text = "关卡: 1",
        font_size = 18,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    lives_label = airui.label({
        parent = info_bar,
        x = 340, y = 10,
        w = 120, h = 30,
        text = "生命: 3",
        font_size = 18,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_RIGHT
    })
    
    -- 游戏区域
    game_area = airui.container({
        parent = main_container,
        x = 0, y = GAME_AREA_Y + 50,
        w = SCREEN_W, h = GAME_AREA_H - 50,
        color = COLOR_BG,
        scrollable = false
    })
    
    -- 状态标签
    status_label = airui.label({
        parent = game_area,
        x = 0, y = 620,
        w = SCREEN_W, h = 35,
        text = "点击发射球",
        font_size = 22,
        color = 0xfeca57,
        align = airui.TEXT_ALIGN_CENTER
    })
    
    -- 创建挡板
    paddle.obj = airui.button({
        parent = game_area,
        x = paddle.x, y = PADDLE_Y,
        w = PADDLE_W, h = PADDLE_H,
        text = "",
        style = {
            bg_color = COLOR_PADDLE,
            border_width = 0,
            radius = 8,
        },
        on_click = function() end
    })
    
    -- 创建球
    ball.obj = airui.button({
        parent = game_area,
        x = ball.x, y = ball.y,
        w = BALL_SIZE, h = BALL_SIZE,
        text = "",
        style = {
            bg_color = COLOR_BALL,
            border_width = 0,
            radius = BALL_SIZE / 2,
        },
        on_click = function() end
    })
    
    -- 创建砖块
    create_brick_ui()
end

-- 处理点击发射/重新开始
local function on_game_click()
    log.info("BREAKOUT", "on_game_click", "game_state", game_state)
    if game_state == "ready" then
        launch_ball()
    elseif game_state == "gameover" then
        log.info("BREAKOUT", "on_game_click", "calling reset_game")
        reset_game()
    elseif game_state == "victory" then
        -- 下一关
        level = level + 1
        game_state = "ready"
        init_bricks()
        reset_ball()
        create_brick_ui()
        if status_label then
            status_label:set_text("点击发射球")
        end
        update_ui()
    end
end

-- 注册触摸事件处理
local function register_touch_handler()
    log.info("BREAKOUT", "airui.TP_DOWN", airui.TP_DOWN, "airui.TP_HOLD", airui.TP_HOLD, "airui.TP_UP", airui.TP_UP)
    -- if tp then
    --     log.info("BREAKOUT", "tp.EVENT_DOWN", tp.EVENT_DOWN, "tp.EVENT_MOVE", tp.EVENT_MOVE, "tp.EVENT_UP", tp.EVENT_UP)
    -- end
    
    airui.touch_subscribe(function(state, x, y, track_id)
        -- log.info("BREAKOUT", "触摸事件", state, x, y, "track_id", track_id, "paddle.x", paddle.x)
        
        if not main_container or not (state and x and y) then
            return
        end

        local is_down = (airui.TP_DOWN and state == airui.TP_DOWN) or (tp and tp.EVENT_DOWN and state == tp.EVENT_DOWN) or (state == 1)
        local is_hold = (airui.TP_HOLD and state == airui.TP_HOLD) or (tp and tp.EVENT_MOVE and state == tp.EVENT_MOVE) or (state == 2)
        local is_up = (airui.TP_UP and state == airui.TP_UP) or (tp and tp.EVENT_UP and state == tp.EVENT_UP) or (state == 3)
        
        local game_area_start_y = GAME_AREA_Y + 50
        
        if is_down then
            if y >= game_area_start_y then
                touch_state.dragging = true
                touch_state.track_id = track_id
                touch_state.offset_x = x - paddle.x
                -- log.info("BREAKOUT", "按下", "x", x, "paddle.x", paddle.x, "offset_x", touch_state.offset_x)
                move_paddle_to(x, touch_state.offset_x)
            end
            on_game_click()
        elseif is_hold then
            if touch_state.dragging then
                -- log.info("BREAKOUT", "移动", "x", x, "offset_x", touch_state.offset_x)
                move_paddle_to(x, touch_state.offset_x)
            end
        elseif is_up then
            if touch_state.dragging then
                reset_drag_state()
            end
        end
    end)
end

-- 窗口创建回调
local function on_create()
    reset_runtime_state()
    init_bricks()
    create_ui()
    register_touch_handler()
    
    -- 启动游戏循环
    game_timer = sys.timerLoopStart(game_loop, 16) -- 约60FPS
end

-- 窗口销毁回调
local function on_destroy()
    if game_timer then
        sys.timerStop(game_timer)
        game_timer = nil
    end
    
    if airui and airui.touch_unsubscribe then
        airui.touch_unsubscribe()
    end
    
    clear_brick_ui()
    
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    
    game_area = nil
    score_label = nil
    lives_label = nil
    level_label = nil
    status_label = nil
    paddle.obj = nil
    ball.obj = nil
end

-- 重置运行时状态
function reset_runtime_state()
    win_id = nil
    main_container = nil
    game_area = nil
    score_label = nil
    lives_label = nil
    level_label = nil
    status_label = nil
    game_over_msg = nil
    game_timer = nil
    
    paddle = { x = (SCREEN_W - PADDLE_W) / 2, obj = nil }
    ball = { x = SCREEN_W / 2, y = PADDLE_Y - BALL_SIZE - 5, vx = 0, vy = 0, obj = nil }
    bricks = {}
    brick_objs = {}
    
    touch_state.dragging = false
    touch_state.track_id = nil
    touch_state.offset_x = 0
    
    game_state = "ready"
    score = 0
    lives = 3
    level = 1
end

-- 订阅打开窗口消息
local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    if win_id then
        return
    end
    
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

sys.subscribe("OPEN_BREAKOUT_WIN", open_handler)
