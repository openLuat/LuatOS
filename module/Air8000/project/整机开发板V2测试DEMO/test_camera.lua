
--[[
1. 本demo可直接在Air8000整机开发板上运行，如有需要请luat.taobao.com 购买
2. 演示摄像头拍照和回显，因为摄像头拍摄的视频，需要配合LCD 显示出来，因此该demo，需要配备LCD 
3. 注意在air8000引擎上，因为uart2 和GPS 共用，如果使能了GPS 则UART2 会被占用，此demo将无法使用
摄像头使用了如下管脚
[67, "CAM_SPI_CLK", " PIN67脚, 用作摄像头时钟"],
[66, "CAM_SPI_CS", " PIN66脚, 用作摄像头片选"],
[52, "GPIO153", " PIN52脚, 控制摄像头关闭"],
[53, "GPIO147", " PIN53脚, 控制摄像头电源"],
[98, "CAM_MCLK", " PIN98脚, 用于摄像头时钟"],x
[94, "UART2_TX", " PIN94脚,做UART2_TX用, 用作和GPS 通讯，在此demo，需要复用为摄像头管脚"],
[95, "UART2_RX", " PIN95脚,做UART2_RX用, 用作和GPS 通讯"],
LCD 使用了如下管脚：
[25, "LCD_CLK", " PIN25脚, LCD 时钟"],
[26, "LCD_CS", " PIN26脚, LCD 片选"],
[27, "LCD_RST", " PIN27脚, LCD 复位控制"],
[28, "LCD_SDA", " PIN28脚, LCD 数据传输"],
[29, "LCD_RS", " PIN29脚, LCD 的信号指令"],
[30, "GPIO2", " PIN30脚, QSPI 时候作为信号传输"],
[31, "GPIO1", " PIN31脚, QSPI 时候作为信号传输"],
[44, "WAKEUP0", " PIN44脚, 触摸屏中断脚"],  
[55, "GPIO141", " PIN55脚, 用于控制LCD 电源"],
[80, "I2C0_SCL", " PIN80脚, I2C0_SCL 触摸屏通信,摄像头复用"],
[81, "I2C0_SDA", " PIN81脚, I2C0_SDA 触摸屏通信,摄像头复用"]
4. 本程序使用逻辑：
4.1. 如果SCAN_MODE  设置为0 ，程序运行后，点击boot 键，将进行扫码测试，会将摄像头的数据显示再屏幕上，如果解析二维码或者条形码成功，将会答应在luatools 中
4.1.  如果SCAN_MODE  设置为0，程序运行后，点击boot 键，将进行拍照测试，并且保存在本地。
]]
local airCamera = require "airCamera"
local taskName = "task_camera_lcd_task"
local SCAN_MODE = 0 -- 写0演示扫码（使用摄像头对二维码、条形码或其他类型的图案进行扫描和识别）
local scan_pause = true -- 扫码启动与停止标志位
local getRawStart = false


------------------------------------
------------ 初始化 LCD ------------
------------------------------------
-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
local function lcd_pin()
    local rtos_bsp = rtos.bsp()
    if string.find(rtos_bsp,"air8000") then
        return lcd.HWID_0, 36, 0xff, 0xff, 0xff
    else
        log.info("main", "没找到合适的cat.1芯片",rtos_bsp)
        return
    end
end
local spi_id, pin_reset, pin_dc, pin_cs, bl = lcd_pin()
if spi_id ~= lcd.HWID_0 then
    spi_lcd = spi.deviceSetup(spi_id, pin_cs, 0, 0, 8, 20 * 1000 * 1000, spi.MSB, 1, 0)
    port = "device"
else
    port = spi_id
end

local function setup_lcd()
    pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
    gpio.setup(141, 1) -- GPIO141打开给lcd电源供电 
    lcd.init("st7796", {
        port = port,
        pin_dc = pin_dc,
        pin_pwr = bl,
        pin_rst = pin_reset,
        direction = 0,
        -- direction0 = 0x00,
        w = 320,
        h = 480,
        xoffset = 0,
        yoffset = 0,
        sleepcmd = 0x10,
        wakecmd = 0x11,
    })
end
------------------------------------
------------ 初始化 摄像头 ------------
------------------------------------
local  function setup_camera()
    local cspiId, i2cId = 1, 0 -- spi的id和摄像头的id    
    local camera_id
    gpio.setup(147,1)--GPIO147打开给camera_3.3V供电
    i2c.setup(i2cId, i2c.FAST) -- I2C1设置为快速模式，不开启上拉
    airCamera.camera_init("gc032a")  -- 初始化“gc032a” 摄像头
end
------------------------------------
------------ 初始化 GPIO0(BOOT 键) ,用于控制摄像头------------
------------------------------------
local function press_key()
    log.info("boot press")
    sys.publish("PRESS", true)
end

local  function setup_powerkey()
    gpio.setup(0, press_key, gpio.PULLDOWN, gpio.RISING)
    gpio.debounce(0, 100, 1)
end

------------------------------------
----------- 摄像头回调 --------------
------------------------------------
local function camera_callback(id, str)
    if type(str) == 'string' then -- 如果是扫码模式（使用摄像头对二维码、条形码或其他类型的图案进行扫描和识别）
        log.info("扫码结果", str)
    elseif str == false then -- 如果摄像头没有正常工作
        log.error("摄像头没有数据")
    else -- 如果摄像头正常工作，并且不是扫码模式
        log.info("摄像头数据", str)
        sys.publish("capture done", true)
    end
end


local rawbuff, err
if RAW_MODE ~= 1 then
    -- 如果 RAW_MODE 不等于 1，创建一个大小为 60KB 的缓冲区
    rawbuff, err = zbuff.create(60 * 1024, 0, zbuff.HEAP_AUTO)
else
    -- 如果 RAW_MODE 等于 1
    rawbuff, err = zbuff.create(640 * 480 * 2, 0, zbuff.HEAP_AUTO) -- 创建一个大小为 640x480 像素，每个像素占用 2 字节的缓冲区，适用于 gc032a 摄像头
    -- local rawbuff = zbuff.create(240 * 320 * 2, zbuff.HEAP_AUTO)  -- 创建一个大小为 240x320 像素，每个像素占用 2 字节的缓冲区，适用于 bf302a 摄像头
end
if rawbuff == nil then
    log.info(err)
end

local function camera_lcd_task()
    setup_powerkey() -- 初始化powerkey 按键
    setup_lcd()    -- 初始化LCD
    setup_camera()    -- 初始化camera
    camera.on(0, "scanned", camera_callback)  -- 摄像头回调注册
    camera.stop(camera_id) -- 暂停摄像头捕获数据。仅停止了图像捕获，未影响预览功能。
    camera.preview(camera_id, true) -- 打开LCD预览功能（直接将摄像头数据输出到LCD）
    log.info("按下boot开始测试")
    -- 总内存大小,单位字节;当前已使用的内存大小,单位字节;历史最高已使用的内存大小,单位字节
    while 1 do
        result, data = sys.waitUntil("PRESS", 30 * 1000) -- 等待 "PRESS" 事件 30 秒（等待boot按键被按下）
        if result == true and data == true then -- 如果 30 秒内检测到 "PRESS" 事件往下执行
            if SCAN_MODE == 1 then
                if scan_pause then
                    log.info("启动扫码")
                    -- camera_id = gc0310Init(cspiId,i2cId,25500000,SCAN_MODE,SCAN_MODE)
                    camera.start(camera_id)
                    scan_pause = false
                    sys.wait(200)
                else
                    log.info("停止扫码")
                    -- camera.close(camera_id)	--完全关闭摄像头才用这个
                    camera.stop(camera_id)
                    scan_pause = true
                    sys.wait(200)
                end
                log.info(rtos.meminfo("sys"))
                log.info(rtos.meminfo("psram"))
            else -- 拍照模式
                log.debug("摄像头拍照")
                -- camera_id = gc0310Init(cspiId,i2cId,25500000,SCAN_MODE,SCAN_MODE)
                -- 将摄像头拍照的数据存入 "/testCamera.jpg" 文件中
                -- jpeg压缩质量1最差，占用空间小，3最高，占用空间大，2和3需要非常多非常多的psram,尽量不要用
                camera.capture(camera_id, "/testCamera.jpg", 1) -- 2和3需要非常多非常多的psram,尽量不要用
                result, data = sys.waitUntil("capture done", 30000)
                -- log.info(rawbuff:used())
                -- camera.close(camera_id)	--完全关闭摄像头才用这个
                camera.stop(camera_id) -- 暂停摄像头捕获数据。仅停止了图像捕获，未影响预览功能。
                -- rawbuff:resize(60 * 1024)
                -- log.info(rtos.meminfo("sys"))
                -- log.info(rtos.meminfo("psram"))
            end

        end
    end
end


sysplus.taskInitEx(camera_lcd_task, taskName)   

