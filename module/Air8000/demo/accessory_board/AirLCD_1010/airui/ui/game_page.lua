--[[
@module  game_page
@summary 俄罗斯方块游戏演示页面
@version 1.0
@date    2026.02.05
@author  江访
@usage
本文件是俄罗斯方块游戏的演示页面。
]]

local game_page = {}

-- 屏幕与棋盘参数（适配480*320竖屏）
local SCREEN_W, SCREEN_H = 320, 480 -- 竖屏：320宽，480高
local GRID_W, GRID_H = 10, 15       -- 调整为10列15行以适应竖屏
local CELL_SIZE = 20                -- 每格像素大小（20px）
local BOARD_W = GRID_W * CELL_SIZE
local BOARD_H = GRID_H * CELL_SIZE
local BOARD_X = (SCREEN_W - BOARD_W) // 2 -- 水平居中
local BOARD_Y = 100                        -- 棋盘左上角Y坐标

-- 7 种俄罗斯方块颜色（RGB565格式）
local COLORS = {
    0x07FF, -- I (青色)
    0x001F, -- J (蓝色)
    0xFD20, -- L (橙色)
    0xFFE0, -- O (黄色)
    0x07E0, -- S (绿色)
    0x8010, -- T (紫色)
    0xF800, -- Z (红色)
}

-- 7 种形状（1 表示方块）
local SHAPES = {
    { { 1, 1, 1, 1 } },           -- I
    { { 1, 0, 0 },   { 1, 1, 1 } }, -- J
    { { 0, 0, 1 },   { 1, 1, 1 } }, -- L
    { { 1, 1 },      { 1, 1 } },  -- O
    { { 0, 1, 1 },   { 1, 1, 0 } }, -- S
    { { 0, 1, 0 },   { 1, 1, 1 } }, -- T
    { { 1, 1, 0 },   { 0, 1, 1 } }, -- Z
}

-- 游戏状态
local grid     -- grid[y][x] = nil 或 颜色下标
local curPiece -- {x, y, shape, color}
local score = 0
local gameOver = false
local gameTimer = nil

-- UI 控件
local main_container
local scoreLabel
local statusLabel
local leftBtn, rightBtn, rotateBtn, downBtn, restartBtn

----------------------------------------------------------------
-- 工具函数：网格与方块
----------------------------------------------------------------
local function initGrid()
    grid = {}
    for y = 1, GRID_H do
        grid[y] = {}
        for x = 1, GRID_W do
            grid[y][x] = nil
        end
    end
end

local function rotateShape(shape)
    local h, w = #shape, #shape[1]
    local res = {}
    for x = 1, w do
        res[x] = {}
        for y = 1, h do
            res[x][y] = shape[h - y + 1][x]
        end
    end
    return res
end

local function newPiece()
    local idx = math.random(1, #SHAPES)
    local shp = SHAPES[idx]
    local pw  = #shp[1]
    local px  = math.floor(GRID_W / 2) - math.floor(pw / 2) + 1
    curPiece  = {
        x = px,
        y = 1,
        shape = shp,
        color = idx,
    }
end

local function eachBlock(piece, cb)
    local shape = piece.shape
    for j = 1, #shape do
        for i = 1, #shape[j] do
            if shape[j][i] == 1 then
                cb(piece.x + i - 1, piece.y + j - 1)
            end
        end
    end
end

local function validPosition(piece)
    local ok = true
    eachBlock(piece, function(x, y)
        if x < 1 or x > GRID_W or y < 1 or y > GRID_H then
            ok = false
            return
        end
        if grid[y][x] ~= nil then
            ok = false
            return
        end
    end)
    return ok
end

local function mergePiece()
    if not curPiece then return end
    eachBlock(curPiece, function(x, y)
        if y >= 1 and y <= GRID_H and x >= 1 and x <= GRID_W then
            grid[y][x] = curPiece.color
        end
    end)
end

-- 返回本次消掉的行数
local function clearLines()
    local cleared = 0
    for y = GRID_H, 1, -1 do
        local full = true
        for x = 1, GRID_W do
            if grid[y][x] == nil then
                full = false
                break
            end
        end
        if full then
            cleared = cleared + 1
            -- 下移
            for yy = y, 2, -1 do
                grid[yy] = grid[yy - 1]
            end
            local row = {}
            for x = 1, GRID_W do row[x] = nil end
            grid[1] = row
            y = y + 1
        end
    end
    if cleared > 0 then
        score = score + cleared * 100
    end
    return cleared
end

----------------------------------------------------------------
-- 绘制函数：使用lcd.fill绘制棋盘
----------------------------------------------------------------
local function drawCell(x, y, color)
    local cx = BOARD_X + (x - 1) * CELL_SIZE
    local cy = BOARD_Y + (y - 1) * CELL_SIZE
    lcd.fill(cx, cy, cx + CELL_SIZE - 2, cy + CELL_SIZE - 2, color)
end

local function drawBoard()
    -- 绘制棋盘背景
    lcd.fill(BOARD_X, BOARD_Y, BOARD_X + BOARD_W - 1, BOARD_Y + BOARD_H - 1, 0x1082) -- 深灰色背景

    -- 绘制固定的方块
    for y = 1, GRID_H do
        for x = 1, GRID_W do
            local fixed = grid[y][x]
            if fixed then
                drawCell(x, y, COLORS[fixed])
            else
                -- 绘制空单元格（带边框效果）
                local cx = BOARD_X + (x - 1) * CELL_SIZE
                local cy = BOARD_Y + (y - 1) * CELL_SIZE
                lcd.fill(cx, cy, cx + CELL_SIZE - 2, cy + CELL_SIZE - 2, 0x0841)         -- 更深的灰色
                lcd.fill(cx + 1, cy + 1, cx + CELL_SIZE - 3, cy + CELL_SIZE - 3, 0x18C3) -- 浅灰色内框
            end
        end
    end

    -- 绘制当前方块
    if curPiece then
        eachBlock(curPiece, function(x, y)
            if y >= 1 and y <= GRID_H and x >= 1 and x <= GRID_W then
                drawCell(x, y, COLORS[curPiece.color])
            end
        end)
    end

    -- 绘制棋盘边框
    lcd.fill(BOARD_X - 2, BOARD_Y - 2, BOARD_X + BOARD_W + 1, BOARD_Y - 1, 0xFFFF)                 -- 上边框
    lcd.fill(BOARD_X - 2, BOARD_Y + BOARD_H, BOARD_X + BOARD_W + 1, BOARD_Y + BOARD_H + 1, 0xFFFF) -- 下边框
    lcd.fill(BOARD_X - 2, BOARD_Y - 2, BOARD_X - 1, BOARD_Y + BOARD_H + 1, 0xFFFF)                 -- 左边框
    lcd.fill(BOARD_X + BOARD_W, BOARD_Y - 2, BOARD_X + BOARD_W + 1, BOARD_Y + BOARD_H + 1, 0xFFFF) -- 右边框
end

----------------------------------------------------------------
-- UI更新函数
----------------------------------------------------------------
local function updateScoreLabel()
    if scoreLabel then
        scoreLabel:set_text("分数: " .. tostring(score))
    end
end

local function updateStatusLabel(extra)
    if not statusLabel then return end
    if gameOver then
        statusLabel:set_text("游戏结束! 点击重新开始")
    else
        if extra and extra ~= "" then
            statusLabel:set_text("俄罗斯方块 | " .. extra)
        else
            statusLabel:set_text("俄罗斯方块 | 使用按钮游玩")
        end
    end
end

local function redrawAll(extraStatus)
    updateScoreLabel()
    updateStatusLabel(extraStatus)
    drawBoard()
end

----------------------------------------------------------------
-- 控制逻辑
----------------------------------------------------------------
local function stepDown()
    if gameOver or not curPiece then return end
    local test = {
        x = curPiece.x,
        y = curPiece.y + 1,
        shape = curPiece.shape,
        color = curPiece.color,
    }
    if validPosition(test) then
        curPiece = test
        redrawAll()
        return
    end

    -- 碰到底或碰到已固定方块
    mergePiece()
    local cleared = clearLines()
    newPiece()
    if not validPosition(curPiece) then
        gameOver = true
        redrawAll("游戏结束!")
        if gameTimer then
            sys.timerStop(gameTimer)
            gameTimer = nil
        end
    else
        if cleared > 0 then
            redrawAll("消除了 " .. cleared .. " 行!")
        else
            redrawAll()
        end
    end
end

local function moveLeft()
    if gameOver or not curPiece then return end
    local test = {
        x = curPiece.x - 1,
        y = curPiece.y,
        shape = curPiece.shape,
        color = curPiece.color,
    }
    if validPosition(test) then
        curPiece = test
        redrawAll()
    end
end

local function moveRight()
    if gameOver or not curPiece then return end
    local test = {
        x = curPiece.x + 1,
        y = curPiece.y,
        shape = curPiece.shape,
        color = curPiece.color,
    }
    if validPosition(test) then
        curPiece = test
        redrawAll()
    end
end

local function softDrop()
    if gameOver or not curPiece then return end
    local test = {
        x = curPiece.x,
        y = curPiece.y + 1,
        shape = curPiece.shape,
        color = curPiece.color,
    }
    if validPosition(test) then
        curPiece = test
        redrawAll()
    end
end

local function rotatePiece()
    if gameOver or not curPiece then return end
    local newShape = rotateShape(curPiece.shape)
    local test = {
        x = curPiece.x,
        y = curPiece.y,
        shape = newShape,
        color = curPiece.color,
    }
    if validPosition(test) then
        curPiece = test
        redrawAll("旋转")
    end
end

local function restartGame()
    if gameTimer then
        sys.timerStop(gameTimer)
    end
    
    score = 0
    gameOver = false
    initGrid()
    newPiece()
    redrawAll("重新开始，分数: 0")
    
    -- 重新启动定时器
    gameTimer = sys.timerLoopStart(stepDown, 400)
end

----------------------------------------------------------------
-- 创建游戏UI
----------------------------------------------------------------
function game_page.create_ui()
    -- 创建主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = SCREEN_H,
        color = 0x0000, -- 黑色背景
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = SCREEN_W,
        h = 50,
        color = 0x1E3A8A, -- 深蓝色
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
          x = 250,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function()
            game_page.cleanup()
            go_back()
        end
    })

    -- 游戏标题
    airui.label({
        parent = title_bar,
        text = "俄罗斯方块",
        x = 80,
        y = 15,
        w = 160,
        h = 20,
    })

    -- 分数标签
    scoreLabel = airui.label({
        parent = main_container,
        text = "分数: 0",
        x = 220,
        y = 70,
        w = 150,
        h = 20,
    })

    -- 状态标签
    statusLabel = airui.label({
        parent = main_container,
        text = "俄罗斯方块 | 使用按钮游玩",
        x = 10,
        y = 70,
        w = SCREEN_W - 20,
        h = 20,
    })

    -- 控制按钮区域
    local btnY = BOARD_Y + BOARD_H + 10
    local btnW, btnH, gap = 70, 30, 10

    -- 计算按钮起始X坐标（居中显示）
    local totalBtnWidth = btnW * 3 + gap * 2 -- 第一行3个按钮
    local btnStartX = (SCREEN_W - totalBtnWidth) // 2

    -- 第一行按钮
    leftBtn = airui.button({
        parent   = main_container,
        x        = btnStartX,
        y        = btnY,
        w        = btnW,
        h        = btnH,
        text     = "左移",
        on_click = function() moveLeft() end,
    })

    rightBtn = airui.button({
        parent   = main_container,
        x        = btnStartX + btnW + gap,
        y        = btnY,
        w        = btnW,
        h        = btnH,
        text     = "右移",
        on_click = function() moveRight() end,
    })

    rotateBtn = airui.button({
        parent   = main_container,
        x        = btnStartX + 2 * (btnW + gap),
        y        = btnY,
        w        = btnW,
        h        = btnH,
        text     = "旋转",
        on_click = function() rotatePiece() end,
    })

    -- 第二行按钮
    btnY = btnY + btnH + gap

    downBtn = airui.button({
        parent   = main_container,
        x        = btnStartX,
        y        = btnY,
        w        = btnW * 2 + gap, -- 稍宽一点
        h        = btnH,
        text     = "下落",
        on_click = function() softDrop() end,
    })

    restartBtn = airui.button({
        parent   = main_container,
        x        = btnStartX + btnW * 2 + gap * 2,
        y        = btnY,
        w        = btnW,
        h        = btnH,
        text     = "重新开始",
        on_click = function() restartGame() end,
    })
end

----------------------------------------------------------------
-- 页面生命周期函数
----------------------------------------------------------------
function game_page.init(params)
    math.randomseed(os.time())
    
    -- 初始化游戏状态
    initGrid()
    newPiece()
    
    -- 创建UI
    game_page.create_ui()
    
    -- 初始绘制
    redrawAll("准备开始!")
    
    -- 启动定时器
    gameTimer = sys.timerLoopStart(stepDown, 400)
end

function game_page.cleanup()
    -- 停止定时器
    if gameTimer then
        sys.timerStop(gameTimer)
        gameTimer = nil
    end
    
    -- 清理UI
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    
    -- 重置游戏状态
    grid = nil
    curPiece = nil
    score = 0
    gameOver = false
    
    leftBtn = nil
    rightBtn = nil
    rotateBtn = nil
    downBtn = nil
    restartBtn = nil
    scoreLabel = nil
    statusLabel = nil
end

return game_page