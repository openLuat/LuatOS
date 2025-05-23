-- sys库是标配
_G.sys = require("sys")

-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

gpio.setup(29, 1) -- 1.3硬件版本 GPIO29打开给lcd电源供电

local blk = gpio.setup(30, 1) -- 1.3改版 增加的LCD背光脚,高电平关闭背光,电平开启背光

-- local TP_POWER = gpio.setup(31,1) --1.4祝哥说让打开的

local rtos_bsp = rtos.bsp()
-- local chip_type = hmeta.chip()
-- 根据不同的BSP返回不同的值
-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
local function lcd_pin()
    local rtos_bsp = rtos.bsp()
    if string.find(rtos_bsp, "780EPM") then
        return lcd.HWID_0, 36, 0xff, 0xff, 25 -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
    else
        log.info("main", "你用的不是780EPM,请更换demo测试", rtos_bsp)
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
    wakecmd = 0x11
})

-- 不在内置驱动的, 看demo/lcd_custom

sys.taskInit(function()
    -- 开启缓冲区, 刷屏速度回加快, 但也消耗2倍屏幕分辨率的内存
    -- lcd.setupBuff()          -- 使用lua内存
    -- lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
    -- lcd.autoFlush(false)
    log.info("打开背光", blk(0))
    -- while 1 do
    --     lcd.clear() --全局刷屏
    --     log.info("wiki API 文档", "https://wiki.luatos.com/api/lcd.html")
    --     if lcd.showImage then
    --         -- 注意, jpg需要是常规格式, 不能是渐进式JPG
    --         -- 如果无法解码, 可以用画图工具另存为,新文件就能解码了
    --     --以左上角第一个像素点为原点向右为X轴向下为Y轴，以(40,0)坐标点为图片的第一个像素点，显示该图片
    --         lcd.showImage(40, 0, "/luadb/logo.jpg")
    --         sys.wait(100)
    --     end
    --     --以左上角第一个像素点为原点,向右为X轴向下为Y轴，在(20,20)和(150,20)两个坐标点之间画一条线
    --     -- log.info("lcd.drawLine", lcd.drawLine(20, 20, 150, 20, 0x001F))
    --     --以左上角第一个像素点为原点,向右为X轴向下为Y轴，在(20,40)和(120,70)两个坐标点之间绘制一个框
    --     -- log.info("lcd.drawRectangle", lcd.drawRectangle(20, 40, 120, 70, 0xF800))
    --     --以左上角第一个像素点为原点,向右为X轴向下为Y轴，(50,60)坐标点为圆心，画一个半径为20个像素点的圆
    --     -- log.info("lcd.drawCircle", lcd.drawCircle(50, 60, 20, 0x0CE0))
    --     lcd.flush() --清除屏幕缓冲区，不填默认全局清除
    --     sys.wait(1000)
    -- end

    if tp then
        log.info("有TP接口")
        local function tp_callBack(tp_device,tp_data)
            log.info("tp_device and tp_data ",tp_device,tp_data)
            sys.publish("TP",tp_device,tp_data)
        end
        -- 根据具体设计修改配置
        -- 硬件i2c参考
        tp_device = tp.init("gt911",{port=1,pin_rst = 0xff,pin_int = 28,w = 320,h = 480},tp_callBack)
        
        -- 软件i2c 参考
        -- softI2C = i2c.createSoft(8, 5)
        -- tp_device =  tp.init("gt911",{port=softI2C,pin_rst = 9,pin_int = 6,w = 320,h = 480},tp_callBack)
        if tp_device then
            print(tp_device)
            sys.taskInit(function()
                while 1 do 
                    local result, tp_device, tp_data = sys.waitUntil("TP")
                    if result then
                        log.info("画点",lcd.drawPoint(tp_data[1].x, tp_data[1].y, 0xF800))
                        if lcd_use_buff then
                            log.info("清屏",lcd.flush())
                        end
                    end
                end
            end)
        end
    else
        log.info("没有TP接口")
    end
    log.info("line 110")
end)
