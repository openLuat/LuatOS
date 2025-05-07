--- 模块功能：lcddemo
-- @module lcd
-- @author Dozingfiretruck
-- @release 2021.01.25

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lcddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")


local sid = 0
local isquit = false

pm.ioVol(pm.IOVOL_ALL_GPIO, 3300) -- 设置GPIO电平


--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

local lcd_use_buff = false  -- 是否使用缓冲模式, 提升绘图效率，占用更大内存


local rtos_bsp = rtos.bsp()
local chip_type = hmeta.chip()
-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
function lcd_pin()
    log.info("rtos_bsp", rtos_bsp, "chip_type", chip_type)
    if rtos_bsp == "AIR101" then
        return 0,pin.PB03,pin.PB01,pin.PB04,pin.PB00
    elseif rtos_bsp == "AIR103" then
        return 0,pin.PB03,pin.PB01,pin.PB04,pin.PB00
    elseif rtos_bsp == "AIR105" then
        return 5,pin.PC12,pin.PE08,pin.PC14,pin.PE09
    elseif rtos_bsp == "ESP32C3" then
        return 2,10,6,7,11
    elseif rtos_bsp == "ESP32S3" then
        return 2,16,15,14,13
    elseif rtos_bsp == "EC618" then
        return 0,1,10,8,22
    elseif string.find(rtos_bsp,"EC718") or string.find(chip_type,"EC718") then
        return lcd.HWID_0,36,0xff,0xff,25 -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
    elseif string.find(rtos_bsp,"Air8101") then
        lcd_use_buff = true -- RGB仅支持buff缓冲模式
        return lcd.RGB,36,0xff,0xff,25
    else
        log.info("main", "bsp not support")
        return
    end
end

local spi_id,pin_reset,pin_dc,pin_cs,bl = lcd_pin() 

if spi_id ~= lcd.HWID_0 and spi_id ~= lcd.RGB then
    spi_lcd = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,0)
    port = "device"
else
    port = spi_id
end

if spi_id == lcd.RGB then
    lcd.init("h050iwv",
            {port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,
            direction = 0,w = 800,h = 480,xoffset = 0,yoffset = 0})
    
    -- lcd.init("hx8282",
    --         {port = port,pin_pwr = bl, pin_rst = pin_reset,
    --         direction = 0,w = 1024,h = 600,xoffset = 0,yoffset = 0})

    -- lcd.init("nv3052c",
    --         {port = port,pin_pwr = bl, pin_rst = pin_reset,
    --         direction = 0,w = 720,h = 1280,xoffset = 0,yoffset = 0})

    -- lcd.init("st7701sn",
    --         {port = port,pin_pwr = bl, pin_rst = pin_reset,
    --         direction = 0,w = 480,h = 854,xoffset = 0,yoffset = 0})

    -- lcd.init("st7701s",
    --         {port = port,pin_pwr = bl, pin_rst = pin_reset,
    --         direction = 0,w = 480,h = 480,xoffset = 0,yoffset = 0})

    -- lcd.init("custom",
    --         {port = port,hbp = 46, hspw = 2, hfp = 48,vbp = 24, vspw = 2, vfp = 24,
    --         bus_speed = 60*1000*1000,
    --         direction = 0,w = 800,h = 480,xoffset = 0,yoffset = 0})

else
    --[[ 此为合宙售卖的1.8寸TFT LCD LCD 分辨率:128X160 屏幕ic:st7735 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.19.6c2275a1Pa8F9o&id=560176729178]]
    -- lcd.init("st7735",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 128,h = 160,xoffset = 0,yoffset = 0},spi_lcd)
    
    -- [[ 此为合宙售卖的0.96寸TFT LCD LCD 分辨率:160X80 屏幕ic:st7735s 购买地址:https://item.taobao.com/item.htm?id=661054472686]]
    -- lcd.init("st7735v",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 1,w = 160,h = 80,xoffset = 0,yoffset = 24},spi_lcd)
    
    -- [[ 此为合宙售卖的ec718系列专用硬件双data驱动TFT LCD LCD 分辨率:320x480 屏幕ic:nv3037 购买地址:https://item.taobao.com/item.htm?id=764253232987&skuId=5258482696347&spm=a1z10.1-c-s.w4004-24087038454.8.64961170w5EdoA]]
    -- lcd.init("nv3037",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 320,h = 480,xoffset = 0,yoffset = 0,interface_mode=lcd.DATA_2_LANE},spi_lcd)
    
    -- lcd.init("st7789",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd)
	-- [[ QSPI接口无RAM屏幕，必须开启lcd_use_buff ]]

    local i2cid = 0
    local tp_rst = 34
    local tp_irq = 29

    -- [[ 此为合宙售卖的0.96寸TFT LCD LCD 分辨率:320X480 屏幕ic:st7789 购买地址:https://item.taobao.com/item.htm?id=660699522796&skuId=4798808989403&spm=a1z10.1-c-s.w4004-24087038454.8.64961170w5EdoA]]
    -- i2c.setup(1, i2c.FAST)
    
    -- lcd.init("jd9261t_inited",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 480,h = 480,xoffset = 0,yoffset = 0,interface_mode=lcd.QSPI_MODE,bus_speed=60000000,flush_rate=658,vbp=19,vfp=108,vs=2,tp_i2c_id=0,tp_pin_rst=31,tp_pin_irq=gpio.CHG_DET,tp_driver=1},spi_lcd)
    lcd.init("jd9261t_inited",{port = port,pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 480,h = 480,xoffset = 0,yoffset = 0,interface_mode=lcd.QSPI_MODE,bus_speed=60000000,flush_rate=658,vbp=19,vfp=108,vs=2},spi_lcd)
    lcd_use_buff = true
end

--如果显示颜色相反，请解开下面一行的注释，关闭反色
--lcd.invoff()

-- 不在内置驱动的, 看demo/lcd_custom





-- 全局设置
local windowWidth, windowHeight = 480, 480
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
local function initrus()
  math.randomseed(os.time())
  initBoard()
  currentPiece = newPiece()
end

-- 仅允许三种按键：左（移动）、右（移动）和上（旋转）
local function keypressed(key)
  if key == "left" then
    if isValidPosition(currentPiece, currentPiece.x - 1, currentPiece.y) then
      currentPiece.x = currentPiece.x - 1
    end
  elseif key == "right" then
    if isValidPosition(currentPiece, currentPiece.x + 1, currentPiece.y) then
      currentPiece.x = currentPiece.x + 1
    end
  elseif key == "up" then
    local rotated = rotateShape(currentPiece.shape)
    if isValidPosition(currentPiece, currentPiece.x, currentPiece.y, rotated) then
      currentPiece.shape = rotated
    end
  end
end
initrus()

local function updaterus()
  if isValidPosition(currentPiece, currentPiece.x, currentPiece.y + 1) then
      currentPiece.y = currentPiece.y + 1
      log.info(" y is:" .. currentPiece.y)
  else
      lockPiece(currentPiece)
      log.info(" lockpiece y is:" .. currentPiece.y)
  end
end

local function drawrus()
  local bkc = lcd.rgb565(0)
  --local fblk = lcd.rgb565(0xD0D0D0)
  --local bblk = lcd.rgb565(0x505050)
  local fblk = lcd.rgb565(0x00FF00)
  local bblk = lcd.rgb565(0x0000FF)
  local redc = lcd.rgb565(0xFF0000)
  bkc = 0x00
  fblk = 0x07E0
  bblk = 0x001F
  redc = 0xF800
  local fillcolor = 0
  local x1,x2,y1,y2

  lcd.clear(bkc)  -- 背景色深灰
  -- 绘制棋盘中的固定方块
  for i = 1, rows do
    for j = 1, cols do
      if board[i][j] == 1 then
        --lcd.setColor(bkc, fblk)  -- 固定方块用较亮的灰色
        fillcolor = fblk
      else
        --lcd.setColor(bkc, bblk)  -- 空白格用暗灰色做背景
        fillcolor = bblk
      end

      x1 = boardLeft + (j - 1) * blockSize
      y1 =  (i - 1) * blockSize
      x2 = x1 + blockSize - 1
      y2 = y1 + blockSize - 1
      lcd.fill(x1, y1, x2,y2, fillcolor)
      lcd.drawRectangle(x1, y1, x2,y2, bkc)
      log.info("fill block:" .. fillcolor .. "x1:" .. x1  .. ", y1:" .. y1 .. ", x2:" .. x2 .. ", y2:" .. y2)
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
        log.info("fill red block:" .. fillcolor .. "x1:" .. x1  .. ", y1:" .. y1 .. ", x2:" .. x2 .. ", y2:" .. y2)
      end
    end
  end  
  lcd.flush()
end



sys.taskInit(function()
    -- 开启缓冲区, 刷屏速度回加快, 但也消耗2倍屏幕分辨率的内存
    if lcd_use_buff then
        lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
        -- lcd.setupBuff()       -- 使用lua内存, 只需要选一种
        lcd.autoFlush(false)
    end

    -- while 1 do 
        -- lcd.clear()
        -- log.info("wiki", "https://wiki.luatos.com/api/lcd.html")
        -- -- API 文档 https://wiki.luatos.com/api/lcd.html
        -- -- if lcd.showImage then
        --     -- 注意, jpg需要是常规格式, 不能是渐进式JPG
        --     -- 如果无法解码, 可以用画图工具另存为,新文件就能解码了
        -- lcd.showImage(40,0,"/luadb/logo.jpg")
        -- sys.wait(100)
        -- -- end
        -- log.info("lcd.drawLine", lcd.drawLine(20,20,150,20,0x001F))
        -- log.info("lcd.drawRectangle", lcd.drawRectangle(20,40,120,70,0xF800))
        -- log.info("lcd.drawCircle", lcd.drawCircle(50,50,20,0x0CE0))

        -- if lcd_use_buff then
        --     lcd.flush()
        -- end
        lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
        lcd.autoFlush(false)
    
        while 1 do
            lcd.clear()
        --    log.info("合宙 780EPM LCD:" .. sid)
            sid = sid + 1
    
            keypressed()
            
            updaterus()
    
            if isquit then
                break
            end
    
            drawrus()
    
            sys.wait(500)
        end
        -- sys.wait(5000)
    -- end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- 游戏常量
