--[[
@module greedy_snake_win
@summary 贪吃蛇游戏窗口模块
@version 1.0.0
@date    2026.04.09
@author  郭幸福
]]

local win_id = nil
local main_container = nil
local game_area = nil

local CELL_SIZE = 25
local MAP_W = 19
local MAP_H = 19

local WALL = 0
local FOOD = 1
local EMPTY = 2

local map = {}
local score = 0
local gameOver = false
-- 统一游戏速度，移除难度模式
local game_speed = 1000 -- 固定游戏速度（毫秒）


local snake = {
    body = {{x=10, y=10}, {x=9, y=10}, {x=8, y=10}},
    direction = 'right',
    nextDir = 'right',
    moveTimer = nil,
    isMoving = false
}

local score_label = nil
local status_label = nil
local game_timer = nil
local food_position = nil

local wall_images = {}
local food_image = nil
local snake_images = {}

local function isWall(gx, gy)
    if gx < 1 or gx > MAP_W or gy < 1 or gy > MAP_H then
        return true
    end
    return map[gy][gx] == WALL
end

local function isSnake(gx, gy)
    for _, segment in ipairs(snake.body) do
        if segment.x == gx and segment.y == gy then
            return true
        end
    end
    return false
end

local function generateMap()
    local newMap = {}
    for i = 1, MAP_H do
        newMap[i] = {}
        for j = 1, MAP_W do
            newMap[i][j] = EMPTY
        end
    end

    -- 创建边界墙
    for i = 1, MAP_H do
        newMap[i][1] = WALL
        newMap[i][MAP_W] = WALL
    end

    for j = 1, MAP_W do
        newMap[1][j] = WALL
        newMap[MAP_H][j] = WALL
    end

    return newMap
end

local function generateFood()
    local emptyPositions = {}
    for i = 2, MAP_H - 1 do
        for j = 2, MAP_W - 1 do
            if map[i][j] == EMPTY and not isSnake(j, i) then
                table.insert(emptyPositions, {x=j, y=i})
            end
        end
    end
    
    if #emptyPositions > 0 then
        local pos = emptyPositions[math.random(1, #emptyPositions)]
        map[pos.y][pos.x] = FOOD
        return pos
    end
    return nil
end

local function createWallContainers()
    if not game_area then return end
    local offsetX = math.floor((480 - MAP_W * CELL_SIZE) / 2)
    local offsetY = math.floor((480 - MAP_H * CELL_SIZE) / 2)

    for row = 1, MAP_H do
        wall_images[row] = {}
        for col = 1, MAP_W do
            local x = offsetX + (col - 1) * CELL_SIZE
            local y = offsetY + (row - 1) * CELL_SIZE

            if map[row][col] == WALL then
                local wall = airui.container({
                    parent = game_area,
                    x = x,
                    y = y,
                    w = CELL_SIZE - 1,
                    h = CELL_SIZE - 1,
                    color = 0x2A2F5A
                })
                wall_images[row][col] = wall
            end
        end
    end
end

local function removeAllContainers()
    -- 移除墙
    for row = 1, MAP_H do
        if wall_images[row] then
            for col = 1, MAP_W do
                if wall_images[row][col] then
                    wall_images[row][col]:destroy()
                    wall_images[row][col] = nil
                end
            end
        end
    end
    wall_images = {}

    -- 移除食物
    if food_image then
        food_image:destroy()
        food_image = nil
    end

    -- 移除蛇
    for _, image in ipairs(snake_images) do
        if image then
            image:destroy()
        end
    end
    snake_images = {}
end

local function resetGame()
    removeAllContainers()

    map = generateMap()
    score = 0
    gameOver = false

    -- 重置蛇的位置
    snake.body = {{x=10, y=10}, {x=9, y=10}, {x=8, y=10}}
    snake.direction = 'right'
    snake.nextDir = 'right'

    if game_area then
        createWallContainers()

        -- 生成食物
        food_position = generateFood()

        -- 绘制蛇
        local offsetX = (480 - MAP_W * CELL_SIZE) / 2
        local offsetY = (480 - MAP_H * CELL_SIZE) / 2
        for _, segment in ipairs(snake.body) do
            local snake_part = airui.container({
                parent = game_area,
                x = math.floor(offsetX + (segment.x - 1) * CELL_SIZE + 2),
                y = math.floor(offsetY + (segment.y - 1) * CELL_SIZE + 2),
                w = CELL_SIZE - 4,
                h = CELL_SIZE - 4,
                color = 0x4CAF50,
                radius = 5
            })
            table.insert(snake_images, snake_part)
        end

        -- 绘制食物
        if food_position then
            food_image = airui.container({
                parent = game_area,
                x = math.floor(offsetX + (food_position.x - 1) * CELL_SIZE + 5),
                y = math.floor(offsetY + (food_position.y - 1) * CELL_SIZE + 5),
                w = CELL_SIZE - 10,
                h = CELL_SIZE - 10,
                color = 0xFF5722,
                radius = 5
            })
        end
    end

    if score_label then
        score_label:set_text("0")
    end
    if status_label then
        status_label:set_text("游戏中")
        status_label:set_color(0xF9D371)
    end
end

local function updateUI()
    if score_label then
        score_label:set_text(tostring(score))
    end
end

local function checkCollision()
    local head = snake.body[1]
    
    -- 检查是否撞墙
    if isWall(head.x, head.y) then
        return true
    end
    
    -- 检查是否撞到自己
    for i = 2, #snake.body do
        if snake.body[i].x == head.x and snake.body[i].y == head.y then
            return true
        end
    end
    
    return false
end

local function eatFood()
    local head = snake.body[1]
    if head.x == food_position.x and head.y == food_position.y then
        -- 增加分数
        score = score + 10
        
        -- 增加蛇的长度
        local tail = {x=snake.body[#snake.body].x, y=snake.body[#snake.body].y}
        table.insert(snake.body, tail)
        
        -- 重新生成食物
        map[food_position.y][food_position.x] = EMPTY
        food_position = generateFood()
        
        -- 更新UI
        updateUI()
        
        return true
    end
    return false
end

local function moveSnake()
    if gameOver or not game_area then
        return
    end

    -- 更新方向
    snake.direction = snake.nextDir
    
    -- 移动蛇头
    local head = {x=snake.body[1].x, y=snake.body[1].y}
    if snake.direction == 'up' then
        head.y = head.y - 1
    elseif snake.direction == 'down' then
        head.y = head.y + 1
    elseif snake.direction == 'left' then
        head.x = head.x - 1
    elseif snake.direction == 'right' then
        head.x = head.x + 1
    end
    
    -- 检查碰撞
    if checkCollision() then
        gameOver = true
        if status_label then
            status_label:set_text("游戏结束")
            status_label:set_color(0xFF5722)
        end
        return
    end
    
    -- 移动蛇身
    table.insert(snake.body, 1, head)
    if not eatFood() then
        table.remove(snake.body)
    end
    
    -- 更新UI
    removeAllContainers()
    createWallContainers()
    
    -- 绘制蛇
    local offsetX = (480 - MAP_W * CELL_SIZE) / 2
    local offsetY = (480 - MAP_H * CELL_SIZE) / 2
    for _, segment in ipairs(snake.body) do
        local snake_part = airui.container({
            parent = game_area,
            x = math.floor(offsetX + (segment.x - 1) * CELL_SIZE + 2),
            y = math.floor(offsetY + (segment.y - 1) * CELL_SIZE + 2),
            w = CELL_SIZE - 4,
            h = CELL_SIZE - 4,
            color = 0x4CAF50,
            radius = 5
        })
        table.insert(snake_images, snake_part)
    end
    
    -- 绘制食物
    if food_position then
        food_image = airui.container({
            parent = game_area,
            x = math.floor(offsetX + (food_position.x - 1) * CELL_SIZE + 5),
            y = math.floor(offsetY + (food_position.y - 1) * CELL_SIZE + 5),
            w = CELL_SIZE - 10,
            h = CELL_SIZE - 10,
            color = 0xFF5722,
            radius = 5
        })
    end
end

local function onDirectionBtnClick(dir)
    if gameOver then
        resetGame()
        return
    end
    
    -- 防止蛇直接反向移动
    if (dir == 'up' and snake.direction ~= 'down') or
       (dir == 'down' and snake.direction ~= 'up') or
       (dir == 'left' and snake.direction ~= 'right') or
       (dir == 'right' and snake.direction ~= 'left') then
        snake.nextDir = dir
    end
end

local function onResetBtnClick()
    resetGame()
end

local function onExitBtnClick()
    if win_id then
        log.info("main", "退出应用")
        exwin.close(win_id)
    end
end

local function create_ui()
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0x000000
    })

    game_area = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 480,
        color = 0x010115
    })

    local info_panel = airui.container({
        parent = main_container,
        x = 8,
        y = 488,
        w = 464,
        h = 50,
        color = 0x1A1F2F
    })

    local score_container = airui.container({
        parent = info_panel,
        x = 10,
        y = 10,
        w = 140,
        h = 30,
        color = 0x010018
    })
    airui.label({
        parent = score_container,
        x = 5,
        y = 3,
        w = 55,
        h = 24,
        text = "分数:",
        font_size = 18,
        color = 0xAAAACC,
        align = airui.TEXT_ALIGN_LEFT
    })
    score_label = airui.label({
        parent = score_container,
        x = 60,
        y = 3,
        w = 70,
        h = 24,
        text = "0",
        font_size = 18,
        color = 0xFFDE7A,
        align = airui.TEXT_ALIGN_LEFT
    })

    status_label = airui.label({
        parent = info_panel,
        x = 310,
        y = 13,
        w = 140,
        h = 24,
        text = "游戏中",
        font_size = 18,
        color = 0xF9D371,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 移除难度模式选择容器


    local dpad_container = airui.container({
        parent = main_container,
        x = 115,
        y = 550,
        w = 250,
        h = 170,
        color = 0x0F1222
    })

    airui.button({
        parent = dpad_container,
        x = 97,
        y = 5,
        w = 55,
        h = 55,
        text = "上",
        font_size = 28,
        text_color = 0xF9D371,
        bg_color = 0x1A1F2F,
        on_click = function()
            onDirectionBtnClick('up')
        end
    })

    airui.button({
        parent = dpad_container,
        x = 10,
        y = 60,
        w = 55,
        h = 55,
        text = "左",
        font_size = 28,
        text_color = 0xF9D371,
        bg_color = 0x1A1F2F,
        on_click = function()
            onDirectionBtnClick('left')
        end
    })

    airui.button({
        parent = dpad_container,
        x = 185,
        y = 60,
        w = 55,
        h = 55,
        text = "右",
        font_size = 28,
        text_color = 0xF9D371,
        bg_color = 0x1A1F2F,
        on_click = function()
            onDirectionBtnClick('right')
        end
    })

    airui.button({
        parent = dpad_container,
        x = 97,
        y = 110,
        w = 55,
        h = 55,
        text = "下",
        font_size = 28,
        text_color = 0xF9D371,
        bg_color = 0x1A1F2F,
        on_click = function()
            onDirectionBtnClick('down')
        end
    })

    local action_container = airui.container({
        parent = main_container,
        x = 40,
        y = 740,
        w = 400,
        h = 50,
        color = 0x1A1F2F
    })

    airui.button({
        parent = action_container,
        x = 10,
        y = 5,
        w = 150,
        h = 40,
        text = "重置",
        font_size = 20,
        text_color = 0xF9D371,
        bg_color = 0x1A1F2F,
        on_click = onResetBtnClick
    })

    airui.button({
        parent = action_container,
        x = 240,
        y = 5,
        w = 150,
        h = 40,
        text = "退出",
        font_size = 20,
        text_color = 0xF9D371,
        bg_color = 0x1A1F2F,
        on_click = onExitBtnClick
    })

    resetGame()

    if game_timer then
        sys.timerStop(game_timer)
    end
    
    -- 使用固定游戏速度
    game_timer = sys.timerLoopStart(function()
        if not gameOver then
            moveSnake()
        end
    end, game_speed)

end

local function on_create()
    create_ui()
end

local function on_destroy()
    log.info("greedy_snake", "销毁贪吃蛇游戏窗口")
    -- 停止定时器
    if game_timer then
        sys.timerStop(game_timer)
        game_timer = nil
    end
    -- 移除所有UI容器
    removeAllContainers()
    -- 销毁主容器
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    -- 重置所有状态变量
    win_id = nil
    score_label = nil
    status_label = nil
    food_position = nil
    game_area = nil
    map = {}
    score = 0
    gameOver = false
    snake = {}
    wall_images = {}
    food_image = nil
    snake_images = {}
    log.info("greedy_snake", "窗口销毁完成")
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = on_get_focus,
        on_lose_focus = on_lose_focus,
    })
end

-- 订阅事件
local function subscribe_events()
    -- 确保只订阅一次
    local success, err = pcall(function()
        sys.unsubscribe("OPEN_GREEDY_SNAKE_WIN", open_handler)
    end)
    success, err = pcall(function()
        sys.subscribe("OPEN_GREEDY_SNAKE_WIN", open_handler)
    end)
    if success then
        log.info("greedy_snake", "事件订阅成功")
    else
        log.info("greedy_snake", "事件订阅失败:", err)
    end
end

-- 初始化时订阅事件
subscribe_events()