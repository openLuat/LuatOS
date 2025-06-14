
local AirRus = {}

local sid = 0
local isquit = false
local dir = "left"

-- 全局设置
local windowWidth, windowHeight = 320, 480
local rows, cols = 20, 10
local blockSize = math.floor(windowHeight / rows)  -- 每个方块大小（16像素）
local boardLeft = (windowWidth - cols * blockSize) / 2  -- 将棋盘水平居中

local board = {}       -- 用二维数组表示棋盘（0=空，1=已占用）
local currentPiece     -- 当前下落的方块
local timer = 0        -- 计时器，用于控制下落速度
local dropInterval = 0.5 -- 每隔0.5秒下落一行

-- 定义各个俄罗斯方块（只含一种状态，通过旋转实现其它状态）
local tetrominoes = {
  { {1, 1, 1, 1} },                   -- I型
  { {1, 1}, {1, 1} },                -- O型
  { {0, 1, 0}, {1, 1, 1} },           -- T型
  { {1, 0, 0}, {1, 1, 1} },           -- L型
  { {0, 0, 1}, {1, 1, 1} },           -- 反L型
  { {1, 1, 0}, {0, 1, 1} },           -- S型
  { {0, 1, 1}, {1, 1, 0} }            -- Z型
}

-- 初始化棋盘：每个格子初始值为0
local function initBoard()
  board = {}
  for i = 1, rows do
    board[i] = {}
    for j = 1, cols do
      board[i][j] = 0
    end
  end
end

-- 产生一个新方块（复制随机选取的一个 tetromino）
local function newPiece()
  local index = math.random(#tetrominoes)
  local piece = {}
  
  log.info("new picce:" .. sid)

  piece.shape = {}
  for i = 1, #tetrominoes[index] do
    piece.shape[i] = {}
    for j = 1, #tetrominoes[index][i] do
      piece.shape[i][j] = tetrominoes[index][i][j]
    end
  end
  -- 设置初始位置，居中放置（棋盘左上角为坐标 (1,1)）
  piece.x = math.floor((cols - #piece.shape[1]) / 2) + 1
  piece.y = 1
  downlong = 5
  return piece
end

-- 顺时针旋转方块（返回新的矩阵）
local function rotateShape(shape)
  local newShape = {}
  local numRows = #shape
  local numCols = #shape[1]
  for i = 1, numCols do
    newShape[i] = {}
    for j = 1, numRows do
      newShape[i][j] = shape[numRows - j + 1][i]
    end
  end
  return newShape
end

-- 检查方块是否可以放在 (x, y) 位置（可传入自定义 shape 用于检测旋转后的位置）
local function isValidPosition(piece, x, y, shape)
  shape = shape or piece.shape
  for i = 1, #shape do
    for j = 1, #shape[i] do
      if shape[i][j] == 1 then
        local boardX = x + j - 1
        local boardY = y + i - 1
        if boardX < 1 or boardX > cols or boardY < 1 or boardY > rows then
          return false
        end
        if board[boardY][boardX] == 1 then
          return false
        end
      end
    end
  end
  return true
end

-- 将当前方块固定到棋盘上，并检查消行
local function lockPiece(piece)
  for i = 1, #piece.shape do
    for j = 1, #piece.shape[i] do
      if piece.shape[i][j] == 1 then
        local boardX = piece.x + j - 1
        local boardY = piece.y + i - 1
        board[boardY][boardX] = 1
      end
    end
  end
  -- 消除已填满的行
  for i = rows, 1, -1 do
    local full = true
    for j = 1, cols do
      if board[i][j] == 0 then
        full = false
        break
      end
    end
    if full then
      table.remove(board, i)
      local newRow = {}
      for j = 1, cols do newRow[j] = 0 end
      table.insert(board, 1, newRow)
    end
  end
  -- 生成新方块。如果新方块的位置无效，则退出游戏（失败）
  currentPiece = newPiece()
  if not isValidPosition(currentPiece, currentPiece.x, currentPiece.y) then
    isquit = true  -- 游戏结束
  end
end

-- 加载函数
function AirRus.initrus()
  isquit = false
  math.randomseed(os.time())
  initBoard()
  currentPiece = newPiece()
end

-- right: 短按boot, left:短按开机,up:长按boot，fast:长按开机，quit：超长按开机
function AirRus.keypressed(key)
  -- log.info("key : ", key)
  if key == "right" then
    if isValidPosition(currentPiece, currentPiece.x + 1, currentPiece.y) then
      currentPiece.x = currentPiece.x + 1
    end
    key = ""
  elseif key == "left" then
    if isValidPosition(currentPiece, currentPiece.x - 1, currentPiece.y) then
      currentPiece.x = currentPiece.x - 1
    end
    key = ""
  elseif key == "up" then
    local rotated = rotateShape(currentPiece.shape)
    if isValidPosition(currentPiece, currentPiece.x, currentPiece.y, rotated) then
      currentPiece.shape = rotated
    end
    key = ""
  elseif key == "fast" then
    downlong = 1
    key = ""
  end
end

function AirRus.updaterus()
    if isquit then
      AirRus.initrus()
      return
    end

    if isValidPosition(currentPiece, currentPiece.x, currentPiece.y + 1) then
        currentPiece.y = currentPiece.y + 1
       -- log.info(" y is:" .. currentPiece.y)
    else
        lockPiece(currentPiece)
        log.info(" lockpiece y is:" .. currentPiece.y)
    end
end

function AirRus.drawrus()
    local bkc = lcd.rgb565(0)
    local red1 = lcd.rgb565(0xFF0000)  --
    local blue1 = lcd.rgb565(0x0000FF)

    local redc = lcd.rgb565(0xFF0000)
    local fblk = lcd.rgb565(0x00FF00)
    local bblk = lcd.rgb565(0x0000FF)

    log.info(" color 565 is: ", redc, fblk,bblk)

    local fillcolor = 0
    local x1,x2,y1,y2

    lcd.clear(bkc)  -- 背景色深灰
    -- 绘制棋盘中的固定方块
    for i = 1, rows do
      for j = 1, cols do
        if board[i][j] == 1 then
          fillcolor = fblk
        else
          fillcolor = bblk
        end

        x1 = boardLeft + (j - 1) * blockSize
        y1 =  (i - 1) * blockSize
        x2 = x1 + blockSize - 1
        y2 = y1 + blockSize - 1
        lcd.fill(x1, y1, x2,y2, fillcolor)
        lcd.drawRectangle(x1, y1, x2,y2, bkc)
        -- log.info("fill block:" .. fillcolor .. "x1:" .. x1  .. ", y1:" .. y1 .. ", x2:" .. x2 .. ", y2:" .. y2)
      end
    end
    
    -- 绘制当前下落的方块（红色）
    --lcd.setColor(bkc, redc)
    fillcolor = redc
    for i = 1, #currentPiece.shape do
      for j = 1, #currentPiece.shape[i] do
        if currentPiece.shape[i][j] == 1 then
          local gridX = currentPiece.x + j - 1
          local gridY = currentPiece.y + i - 1
          x1 = boardLeft + (gridX - 1) * blockSize
          y1 = (gridY - 1) * blockSize
          x2 = x1 + blockSize - 1
          y2 = y1 + blockSize - 1
          lcd.fill(x1, y1, x2,y2, fillcolor)
          lcd.drawRectangle(x1, y1, x2,y2, bkc)
          -- log.info("fill red block:" .. fillcolor .. "x1:" .. x1  .. ", y1:" .. y1 .. ", x2:" .. x2 .. ", y2:" .. y2)
        end
      end
    end  
    --lcd.flush()
end

return AirRus