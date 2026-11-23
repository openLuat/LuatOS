--[[
@module  board
@summary EVB_Air8101 V3.0 开发板板级驱动：上电时序 + RGB 屏初始化 + GT911 触摸 + 摄像头供电
@version 1.1
@date    2026.11.18
@usage
  本文件只描述"开发板硬件怎么接的、怎么初始化"，不含业务逻辑，便于换板 / 换屏时只改这一处。

  默认参数对应 EVB_Air8101 V3.0 开发板 + 10.1 寸 1024x600 RGB 屏（AirLCD_1100，JD9165BA）+ GT911：
    LCD   : RGB 接口，pin_rst = GPIO5，背光 pin_pwr = GPIO8，屏供电 LCD_EN = GPIO55
    TP    : GT911，软件 I2C SCL = GPIO38 / SDA = GPIO39，TP_RST = GPIO28，TP_INT = GPIO7
    UVC   : 摄像头供电 UVC_EN = GPIO29（驱动前必须断电复位）
  换屏时只改 board.LCD 里的 model / w / h（触摸的 w/h 会跟随 lcd.getSize() 自动变）。

  注意：
  1. Air8101 的硬件 I2C1 默认落在 GPIO0/GPIO1（这两个脚在开发板上是 UART1），
     pins.setup 切不过来，所以触摸走 i2c.createSoft(38, 39) 软件 I2C；
  2. 屏幕方向如果上下颠倒，把 board.LCD.direction 改为 2 即可（本板 AirLCD_1100 实测 0 就是正的），
     tp.init 会跟随 lcd 的 direction 一起旋转触摸坐标，不用再单独换算。
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
    -- "UVC"：AirCAMERA_1030 / 1031 / 1032 / 1033 / 1034，插 USB-A
    -- "DVP"：AirCAMERA_1020，接 24PIN FPC
    type      = "UVC",

    uvc_en    = 29,         -- UVC_EN 摄像头供电（必须先断电再上电）
    usb_port  = 1,          -- USB 端口号 1~4
    uvc_reset_ms   = 200,   -- 断电复位时间
    uvc_startup_ms = 3000,  -- 等 AirCAMERA_1034 上电稳定后再枚举

    -- 按顺序尝试，首个收到 JPEG 的档位生效。第三项可指定首帧等待毫秒数。
    -- AirCAMERA_1034 + V2022_104 真机记录：
    --   960x480 ✅  800x480 ✅  864x480 ✅  480x320 ✅
    --   320x240 在细节丰富的画面下可用，固件会丢弃不超过 5120 字节的 MJPEG 帧。
    --   640x480 / 640x360 / 1280x720 ❌ 1034 不支持这三档。
    -- 顺序：960 宽在 1024 的屏上左右只留 32px 黑边，解码开销与 800 相近，故优先 960。
    sensor_list = {
        { 960, 480 },
        { 800, 480 },
        { 864, 480 },
        { 480, 320 },
        { 320, 240 },
        { 640, 360, 15000 },  -- AirCAMERA_1032 原生 MJPEG 小分辨率
        { 1280, 720, 15000 }, -- AirCAMERA_1032 MJPEG 720p
    },

    dvp_i2c_id = 1,         -- DVP 摄像头使用的 I2C 编号
    dvp_w      = 1280,
    dvp_h      = 720,
}

board.SD = {
    en = 50,                -- SD_EN，TF 卡供电使能
}

-- AirCAMERA_1034 的人脸模组走 UART1。使用其他摄像头时可以将 board.FACE 设为 nil。
board.FACE = {
    uart_id = 1,
    timeout = 20,           -- 单次录入或验证超时（秒）
}

-- 开机自动进入实时预览（默认开）。UVC 会在显示初始化之前先尝试首选分辨率。
-- 想保留"手动点开始预览"的流程，改成 false。
board.AUTO_PREVIEW = true

-- 预览帧间隔（毫秒）。本板每次 lcd.flush() 都是整屏拷贝（约 35ms，无 vsync 同步），
-- 刷得越勤、闪得越明显：250 ≈ 4fps（默认），400 ≈ 2.5fps（更稳但更卡）。
board.PREVIEW_INTERVAL = 200

-- 热插拔兜底：本固件的 UVC 在"开机后才插上"时连不上（实测重试+USB 主机复位都失败），
-- 但"开机时摄像头在位"是可靠的。所以自动重试全失败后，重启一次走开机路径；
-- 用 fskv 标记保证只重启一次，避免没插摄像头时来回重启。
board.AUTO_REBOOT_ON_CAM_FAIL = true


-- 中文字体（可选）：
--   V2022_Air8101_104 固件只带 ASCII 位图字体 font_opposansm12，没有中文位图字体，
--   也没有编入内置 TTF（hzfont 的内置字库未编译）。想显示中文，需要把 TTF 烧进脚本区，
--   这里按顺序找第一个存在的文件；都找不到就自动退回 ASCII 文案，界面照样能用。
board.FONT = {
    paths = {
        "/MiSans_gb2312.ttf",              -- 与 AirUI demo 用的是同一份（脚本区根目录）
        "/luadb/MiSans_gb2312.ttf",
        "/luadb/NotoSansSC_subset.ttf",
    },
    cache = 512,                           -- 字形缓存条数（128/256/512/1024/2048）
}

-- ============================ 内部状态 ============================
local lcd_inited = false
local tp_dev = nil
local W, H = board.LCD.w, board.LCD.h

-- ============================ 上电时序 ============================
--[[
开发板上电：屏幕供电使能拉高（LCD 复位由 lcd.init 的 pin_rst 控制）。
必须在协程内调用（内部有 sys.wait）。

@api board.power_on()
@return nil
]]
function board.power_on()
    if board.LCD.en then
        gpio.setup(board.LCD.en, 1, gpio.PULLUP)
        sys.wait(20)
        log.info("board", "LCD_EN 上电, GPIO", board.LCD.en)
    end
end

--[[
初始化 RGB 屏并开启绘图缓冲区。

开启缓冲区（lcd.setupBuff）后，lcd 库只把"本次绘制涉及的屏幕行"刷到屏上（partial flush），
这正是本 demo 能在摄像头硬件预览画面上叠加 UI 的前提：只刷标题栏/按钮条，画面中间不被覆盖。

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
        log.warn("board", "绘图缓冲区申请失败，屏幕可能无输出")
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
