--[[
@module pacman_game_win
@summary 吃豆人游戏窗口模块
@version 1.0
@date    2026.03.31
@author  朱天华
]]

local win_id = nil
local main_container = nil

local CELL_SIZE = 25
local MAP_W = 19
local MAP_H = 19

local WALL = 0
local DOT = 1
local EMPTY = 2

local map = {}
local dotsLeft = 0
local score = 0
local gameOver = false
local gameWin = false

local pacman = {
    gridX = 2,
    gridY = 2,
    direction = 'right',
    nextDir = 'right',
    moveTimer = nil,
    isMoving = false
}

local score_label = nil
local dots_label = nil
local status_label = nil
local game_timer = nil

local wall_images = {}
local dot_images = {}
local pacman_img = nil

local function isWall(gx, gy)
    if gx < 1 or gx > MAP_W or gy < 1 or gy > MAP_H then
        return true
    end
    return map[gy][gx] == WALL
end

local function generateMap()
    local newMap = {}
    for i = 1, MAP_H do
        newMap[i] = {}
        for j = 1, MAP_W do
            newMap[i][j] = EMPTY
        end
    end

    for i = 1, MAP_H do
        newMap[i][1] = WALL
        newMap[i][MAP_W] = WALL
    end

    for j = 1, MAP_W do
        newMap[1][j] = WALL
        newMap[MAP_H][j] = WALL
    end

    for i = 5, 14, 5 do
        for j = 6, 13, 4 do
            if newMap[i][j] ~= WALL then
                newMap[i][j] = WALL
            end
        end
    end
    for j = 7, 12, 5 do
        for i = 4, 15, 4 do
            if newMap[i][j] ~= WALL then
                newMap[i][j] = WALL
            end
        end
    end

    newMap[10][10] = WALL
    newMap[10][11] = WALL
    newMap[11][10] = WALL

    newMap[2][2] = EMPTY
    newMap[2][3] = EMPTY
    newMap[3][2] = EMPTY

    local dotCount = 0
    for i = 1, MAP_H do
        for j = 1, MAP_W do
            if newMap[i][j] == EMPTY and not (i == 2 and j == 2) then
                newMap[i][j] = DOT
                dotCount = dotCount + 1
            end
        end
    end

    return { map = newMap, dots = dotCount }
end

local function createWallContainers()
    local offsetX = math.floor((480 - MAP_W * CELL_SIZE) / 2)
    local offsetY = math.floor((480 - MAP_H * CELL_SIZE) / 2)

    for row = 1, MAP_H do
        wall_images[row] = {}
        dot_images[row] = {}
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
            elseif map[row][col] == DOT then
                local dot = airui.container({
                    parent = game_area,
                    x = math.floor(x + CELL_SIZE / 2 - 2),
                    y = math.floor(y + CELL_SIZE / 2 - 2),
                    w = 4,
                    h = 4,
                    color = 0xF8F3C6,
                    radius = 2
                })
                dot_images[row][col] = dot
            end
        end
    end
end

local function removeAllContainers()
    for row = 1, MAP_H do
        if wall_images[row] then
            for col = 1, MAP_W do
                if wall_images[row][col] then
                    wall_images[row][col]:destroy()
                    wall_images[row][col] = nil
                end
            end
        end
        if dot_images[row] then
            for col = 1, MAP_W do
                if dot_images[row][col] then
                    dot_images[row][col]:destroy()
                    dot_images[row][col] = nil
                end
            end
        end
    end
    wall_images = {}
    dot_images = {}

    if pacman_img then
        pacman_img:destroy()
        pacman_img = nil
    end
end

local function resetGame()
    removeAllContainers()

    local mapData = generateMap()
    map = mapData.map
    dotsLeft = mapData.dots
    score = 0
    gameOver = false
    gameWin = false

    createWallContainers()

    local offsetX = (480 - MAP_W * CELL_SIZE) / 2
    local offsetY = (480 - MAP_H * CELL_SIZE) / 2
    pacman.gridX = 2
    pacman.gridY = 2

    pacman_img = airui.container({
        parent = game_area,
        x = math.floor(offsetX + (pacman.gridX - 1) * CELL_SIZE + 3),
        y = math.floor(offsetY + (pacman.gridY - 1) * CELL_SIZE + 3),
        w = CELL_SIZE - 6,
        h = CELL_SIZE - 6,
        color = 0xFFD966,
        radius = 9
    })

    if score_label then
        score_label:set_text("0")
    end
    if dots_label then
        dots_label:set_text(tostring(dotsLeft))
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
    if dots_label then
        dots_label:set_text(tostring(dotsLeft))
    end
end

local function eatDotAt(gridX, gridY)
    if gridX < 1 or gridX > MAP_W or gridY < 1 or gridY > MAP_H then
        return
    end
    if map[gridY][gridX] == DOT then
        map[gridY][gridX] = EMPTY
        dotsLeft = dotsLeft - 1
        score = score + 10

        if dot_images[gridY] and dot_images[gridY][gridX] then
            dot_images[gridY][gridX]:destroy()
            dot_images[gridY][gridX] = nil
        end

        updateUI()

        if dotsLeft == 0 and not gameOver then
            gameWin = true
            gameOver = true
            if status_label then
                status_label:set_text("胜利!")
                status_label:set_color(0xAAFFAA)
            end
        end
    end
end

local function canMoveTo(gridX, gridY, dir)
    local nx, ny = gridX, gridY
    if dir == 'up' then
        ny = ny - 1
    elseif dir == 'down' then
        ny = ny + 1
    elseif dir == 'left' then
        nx = nx - 1
    elseif dir == 'right' then
        nx = nx + 1
    else
        return false
    end
    return not isWall(nx, ny)
end

local function movePacmanOneStep()
    if gameOver or pacman.isMoving then
        return
    end

    local nextX = pacman.gridX
    local nextY = pacman.gridY

    if pacman.direction == 'up' then
        nextY = nextY - 1
    elseif pacman.direction == 'down' then
        nextY = nextY + 1
    elseif pacman.direction == 'left' then
        nextX = nextX - 1
    elseif pacman.direction == 'right' then
        nextX = nextX + 1
    end

    if not isWall(nextX, nextY) then
        pacman.gridX = nextX
        pacman.gridY = nextY
        eatDotAt(pacman.gridX, pacman.gridY)

        if pacman_img then
            pacman_img:destroy()
            pacman_img = nil
        end

        local offsetX = (480 - MAP_W * CELL_SIZE) / 2
        local offsetY = (480 - MAP_H * CELL_SIZE) / 2
        pacman_img = airui.container({
            parent = game_area,
            x = math.floor(offsetX + (pacman.gridX - 1) * CELL_SIZE + 3),
            y = math.floor(offsetY + (pacman.gridY - 1) * CELL_SIZE + 3),
            w = CELL_SIZE - 6,
            h = CELL_SIZE - 6,
            color = 0xFFD966,
            radius = 9
        })
    else
        pacman.direction = pacman.nextDir
    end
end

local function onDirectionBtnClick(dir)
    if gameOver and gameWin then
        resetGame()
        return
    end
    pacman.direction = dir
    pacman.nextDir = dir
    
    if not pacman.isMoving then
        local testX = pacman.gridX
        local testY = pacman.gridY
        if dir == 'up' then testY = testY - 1
        elseif dir == 'down' then testY = testY + 1
        elseif dir == 'left' then testX = testX - 1
        elseif dir == 'right' then testX = testX + 1
        end

        if not isWall(testX, testY) then
            movePacmanOneStep()
        end
    end
end

local function onResetBtnClick()
    resetGame()
end

local function onExitBtnClick()
    if win_id then
        exwin.close(win_id)
    end
end

local function create_ui()
    log.info("pacman_game_win create_ui")

    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = 480,
        h = 800,
        color = 0x000000
    })

    local game_area = airui.container({
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

    local dots_container = airui.container({
        parent = info_panel,
        x = 160,
        y = 10,
        w = 160,
        h = 30,
        color = 0x010018
    })
    airui.label({
        parent = dots_container,
        x = 5,
        y = 3,
        w = 85,
        h = 24,
        text = "剩余豆子:",
        font_size = 18,
        color = 0xAAAACC,
        align = airui.TEXT_ALIGN_LEFT
    })
    dots_label = airui.label({
        parent = dots_container,
        x = 90,
        y = 3,
        w = 55,
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

    local dpad_container = airui.container({
        parent = main_container,
        x = 115,
        y = 545,
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
    
    game_timer = sys.timerLoopStart(function()
        if not gameOver then
            local nextX = pacman.gridX
            local nextY = pacman.gridY
            if pacman.direction == 'up' then nextY = nextY - 1
            elseif pacman.direction == 'down' then nextY = nextY + 1
            elseif pacman.direction == 'left' then nextX = nextX - 1
            elseif pacman.direction == 'right' then nextX = nextX + 1
            end
            
            if not isWall(nextX, nextY) then
                pacman.gridX = nextX
                pacman.gridY = nextY
                eatDotAt(pacman.gridX, pacman.gridY)

                if pacman_img then
                    pacman_img:destroy()
                    pacman_img = nil
                end

                local offsetX = (480 - MAP_W * CELL_SIZE) / 2
                local offsetY = (480 - MAP_H * CELL_SIZE) / 2
                pacman_img = airui.container({
                    parent = game_area,
                    x = math.floor(offsetX + (pacman.gridX - 1) * CELL_SIZE + 3),
                    y = math.floor(offsetY + (pacman.gridY - 1) * CELL_SIZE + 3),
                    w = CELL_SIZE - 6,
                    h = CELL_SIZE - 6,
                    color = 0xFFD966,
                    radius = 9
                })
            else
                pacman.direction = pacman.nextDir
            end
        end
    end, 300)
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if game_timer then
        sys.timerStop(game_timer)
        game_timer = nil
    end
    removeAllContainers()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    win_id = nil
    score_label = nil
    dots_label = nil
    status_label = nil
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

sys.subscribe("OPEN_PACMAN_GAME_WIN", open_handler)