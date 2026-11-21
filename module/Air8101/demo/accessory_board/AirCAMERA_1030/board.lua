--[[
@module  board
@summary Air8101B V3.0 的 LCD、触摸和 USB 摄像头配置
@version 001.999.000
@date    2026.11.21
@usage
在此处配置 AirLCD_1100 的 RGB 时序、GT911 触摸接线和 AirCAMERA_1030 的 USB 端口。
]]

local board = {}

-- ============================ 硬件配置 ============================
board.LCD = {
    -- AirLCD_1100（10.1 寸 1024x600，JD9165BA）在 8101 上用 hx8282 这套 RGB 时序驱动，
    -- 与 module/Air8101/project/Air8101B_dev_board 的 10 寸配置保持一致；
    -- 换 5 寸 AirLCD_1050/H050IWV 时改成 "h050iwv" / 800 / 480。
    model     = "hx8282",
    w         = 1024,
    h         = 600,
    direction = 0,          -- 0:0° 1:90° 2:180° 3:270°
    xoffset   = 0,
    yoffset   = 0,
    pin_rst   = 5,          -- LCD_RST
    pin_pwr   = 8,          -- 背光 PWM1/BL
    en        = 55,         -- LCD_EN 屏幕供电使能
}

board.TP = {
    model = "gt911",
    scl   = 38,             -- I2C1_SCL（软件 I2C）
    sda   = 39,             -- I2C1_SDA
    rst   = 28,             -- TP_RST
    int   = 7,              -- TP_INT
    delay = nil,            -- 软件 I2C 半周期延时(us)，杜邦线长/干扰大时调 10~20
}

board.CAM = {
    usb_port = 1,
    uvc_en = 29,            -- 开发板的 USB 摄像头供电使能脚。
    startup_ms = 3000,      -- 上电后等待摄像头启动，再打开 USB。
    first_frame_ms = 10000, -- 每次打开摄像头时单次等待首帧的上限。
    -- 第一档用于自动预览，其余档位按底部 RES 按钮循环切换。
    modes = {
        { w = 640, h = 360 },
        { w = 640, h = 480 },
        { w = 800, h = 600 },
        { w = 1024, h = 768 },
        { w = 1280, h = 720 },
        { w = 1280, h = 800 },
        { w = 1280, h = 1024 },
        { w = 160, h = 120 },
        { w = 320, h = 240 },
        { w = 352, h = 288 },
        -- 当前测试的 V2023 106 固件尚未修复此档位。1080p 抓帧后会出现 DMA2D 转换报错和看门狗重启。
        { w = 1920, h = 1080 },
    },
}

local lcd_inited = false
local tp_dev
local W, H = board.LCD.w, board.LCD.h

function board.power_on()
    if board.LCD.en then
        gpio.setup(board.LCD.en, 1, gpio.PULLUP)
        sys.wait(20)
        log.info("board", "LCD_EN 上电, GPIO", board.LCD.en)
    end
end

--[[
初始化 RGB 屏并开启绘图缓冲区。

软件预览将 JPEG 解码成 RGB565，先绘制画面和界面栏，再一次性刷新到 LCD。

@api board.lcd_init()
@return boolean 成功返回 true
]]
function board.lcd_init()
    if lcd_inited then return true end
    if not lcd then
        log.error("board", "固件未包含 lcd 核心库")
        return false
    end

    local c = board.LCD
    local ok = lcd.init(c.model, {
        port      = lcd.RGB,
        pin_rst   = c.pin_rst,
        pin_pwr   = c.pin_pwr,
        direction = c.direction,
        w         = c.w,
        h         = c.h,
        xoffset   = c.xoffset,
        yoffset   = c.yoffset,
    })
    log.info("board", "lcd.init", c.model, ok)
    if not ok then
        return false
    end

    -- 必须有帧缓冲：本板的 RGB 控制器靠它出图，直写模式（不开 setupBuff）实测黑屏。
    local buff_ok = lcd.setupBuff(nil, true)
    lcd.autoFlush(false)
    log.info("board", "lcd.setupBuff", buff_ok)
    if not buff_ok then
        log.error("board", "LCD 绘图缓冲区申请失败")
        return false
    end

    -- 背光（部分屏需要显式拉高背光脚）
    if c.pin_pwr then
        gpio.setup(c.pin_pwr, 1)
    end

    W, H = lcd.getSize()
    lcd_inited = true
    log.info("board", "LCD 就绪", W, H)
    return true
end

--[[
初始化 GT911 触摸，事件通过 callback 抛出。

@api board.tp_init(cb)
@function cb 触摸回调，签名 cb(event, x, y)，event 取 tp.EVENT_DOWN / tp.EVENT_MOVE / tp.EVENT_UP
@return boolean 成功返回 true
]]
function board.tp_init(cb)
    if tp_dev then return true end
    if not tp then
        log.error("board", "固件未包含 tp 核心库")
        return false
    end

    local c = board.TP
    local port = i2c.createSoft(c.scl, c.sda, c.delay)
    if type(port) ~= "userdata" then
        log.error("board", "i2c.createSoft 失败, SCL", c.scl, "SDA", c.sda)
        return false
    end

    tp_dev = tp.init(c.model, {
        port      = port,
        pin_rst   = c.rst,
        pin_int   = c.int,
        w         = W,
        h         = H,
        direction = board.LCD.direction,  -- 跟随屏幕方向，触摸坐标自动旋转
    }, function(_, data)
        local d = data and data[1]
        if not d then return end
        if cb then cb(d.event, d.x, d.y) end
    end)

    log.info("board", "tp.init", c.model, tp_dev and "ok" or "fail")
    return tp_dev ~= nil
end

--[[
屏幕逻辑尺寸。
@api board.size()
@return number, number 宽, 高
]]
function board.size()
    return W, H
end

return board
