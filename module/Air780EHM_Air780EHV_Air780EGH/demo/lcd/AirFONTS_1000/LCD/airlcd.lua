-- airlcd.lua
--[[
LCD显示屏驱动模块
核心功能：
1. 支持多种型号LCD的初始化配置
2. 提供统一的LCD初始化接口
3. 特殊型号特殊处理的初始化流程

支持的LCD型号：
- AirLCD_1000: 320x480, ST7796控制器
- AirLCD_1001: 320x480, ST7796控制器
- AirLCD_1002: 480x480, R395435T01控制器
- co5300: 480x466, 自定义初始化流程

对外接口：
1. lcd_init(sn): 初始化指定型号的LCD
   - sn: LCD型号字符串

注意：SPI引脚、供电引脚、RST引脚都需要与实际接线端口进行匹配
]]

local airLCD = {}

-- 必须在task里用,自发光屏幕不需要背光控制
function co5300_init(lcd_cfg)
    lcd.qspi(0x02, 0x32, 0x12)
    lcd.init("user", lcd_cfg)
    gpio.set(lcd_cfg.pin_rst, 0)
    sys.wait(300)
    gpio.set(lcd_cfg.pin_rst, 1)
    sys.wait(200)
    lcd.cmd(0xfe, 0x00)
    lcd.cmd(0xc4, 0x80)
    lcd.cmd(0x3a, 0x55)
    lcd.cmd(0x35, 0x00)
    lcd.cmd(0x53, 0x20)
    lcd.cmd(0x51, 0x7a)
    lcd.cmd(0x63, 0xaa)
    lcd.cmd(0x36, 0x00) --方向
    lcd.wakeup()
    sys.wait(200)
    lcd.cmd(0x29)
end

function airLCD.lcd_init(sn)
    local width, height, lcd_ic

    if sn == "AirLCD_1000" then
        width = 320
        height = 480
        lcd_ic = "st7796"
    elseif sn == "AirLCD_1001" then
        width = 480  --横屏尺寸
        height = 320
        lcd_ic = "st7796"
    elseif  sn == "AirLCD_1002" then
        width = 480
        height = 480
        lcd_ic = "R395435T01"
    elseif sn == "co5300" then  -- 新增co5300支持
        width = 480
        height = 466
        lcd_ic = "user"
    else
        log.info("lcd", "没有找到合适的LCD")
        return
    end

    -- 公共初始化参数
    local lcd_param = {
        port = lcd.HWID_0,      -- 使用的spi id 号
        --pin_dc = -1,            -- QSPI模式不需要DC引脚
        --pin_rst = 36,           -- 复位引脚
        pin_dc = 0xff,            -- 命令选择硬件，不设置
        pin_rst = 36,             -- 屏幕reset 管脚  
        direction = 270,            -- 屏幕方向，横屏
        w = width,                -- 屏幕宽度
        h = height,               -- 屏幕高度
        xoffset = 0,              -- X轴偏移像素
        yoffset = 0,              -- Y轴偏移像素
        sleepcmd = 0x10,          -- LCD睡眠命令
        wakecmd = 0x11,           -- LCD唤醒命令
    }

    -- 如果是co5300添加QSPI专用参数
    if sn == "co5300" then
        lcd_param.interface_mode = lcd.QSPI_MODE
        lcd_param.bus_speed = 60000000  -- 60MHz
        lcd_param.rb_swap = true
        lcd_param.pin_pwr = -1         -- 自发光屏不需要背光控制
        lcd_param.pin_dc = -1
        lcd_param.pin_rst = 36  --Air780EGH核心板是36，Air8000核心板是2
        gpio.setup(17, 0, gpio.PULLUP)-- CO5300电源
        sys.wait(100)
        gpio.setup(17, 1, gpio.PULLUP)
        sys.wait(1000)
    elseif sn == "AirLCD_1001" then
        lcd_param.pin_dc = 0xff
        lcd_param.pin_rst = 2
        gpio.setup(164, 1, gpio.PULLUP)
        gpio.setup(141, 1, gpio.PULLUP)
        sys.wait(1000)
        lcd.init(lcd_ic, lcd_param)
    end

    -- 特殊初始化流程
    if sn == "co5300" then
        co5300_init(lcd_param)
    else
        lcd.init(lcd_ic, lcd_param)
    end

    -- 公用设置
    lcd.setupBuff(nil, true)
    lcd.autoFlush(false)
    lcd.user_done()
    lcd.clear()
    lcd.flush()

end

return airLCD