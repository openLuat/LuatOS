
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "einkdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

--[[
显示屏为合宙 1.54寸v2,200x200,快刷屏
硬件接线
显示屏SPI   -->  Air101 SPI0    Air780E SPI0
Pin_RSCL        (PB2)           (GPIO11)
Pin_RSDA        (PB5)           (GPIO9)
Pin_RES         (PB3)           (GPIO1)
Pin_DC          (PB1)           (GPIO10)
Pin_CS          (PB4)           (GPIO8)
Pin_BUSY        (PB0)           (GPIO22)
]]


local rtos_bsp = rtos.bsp()

-- spi_id,pin_reset,pin_dc,pin_cs,pin_busy,mode
function eink_pin()     
    if rtos_bsp == "AIR101" then
        return 0,pin.PB03,pin.PB01,pin.PB04,pin.PB00
    elseif rtos_bsp == "AIR103" then
        return 0,pin.PB03,pin.PB01,pin.PB04,pin.PB00
    elseif rtos_bsp == "AIR105" then
        return 5,pin.PC12,pin.PE08,pin.PC14,pin.PE09
    elseif rtos_bsp == "ESP32C3" then
        return 2,10,9,7,11
    elseif rtos_bsp == "ESP32S3" then
        return 2,16,15,14,13
    elseif rtos_bsp == "EC618" then
        return 0,1,10,8,22
    else
        log.info("main", "bsp not support")
        return
    end
end

sys.taskInit(function()
    local spi_id,pin_reset,pin_dc,pin_cs,pin_busy,mode = eink_pin() 
    if spi_id then
        eink.model(eink.MODEL_1in54)
        spi.setup(spi_id,nil,0,0,8,20*1000*1000)
        eink.setup(mode, spi_id,pin_busy,pin_reset,pin_dc,pin_cs)
        eink.setWin(200, 200, 0)
        --稍微等一会,免得墨水屏没初始化完成
        sys.wait(100)
        log.info("e-paper 1.54", "Testing Go")
        eink.clear()
        --画几条线一个圆
        eink.circle(50, 100, 40)
        eink.line(100, 20, 105, 180)
        eink.line(100, 100, 180, 20)
        eink.line(100, 100, 180, 180)
        eink.show()
        log.info("e-paper 1.54", "Testing End")
    end
end)

-- 2022.12.02后编译的618 105固件推荐使用以下方法
-- local sysplus = require("sysplus")
-- sys.taskInit(function()
--     local spi_id,pin_reset,pin_dc,pin_cs,pin_busy,mode = eink_pin() 
--     if spi_id then
--         eink.async(1)
--         spi_eink = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,0)
--         eink.init(eink.MODEL_1in54,
--                 {port = "device",pin_dc = pin_dc, pin_busy = pin_busy,pin_rst = pin_reset},
--                 spi_eink)
--         eink.setWin(200, 200, 0)
--         sys.wait(100)
    
--         log.info("e-paper 1.54", "Testing Go")
--         eink.clear().wait()
--         eink.print(30, 20, "LuatOS-AIR780E",0x00)
    
--         eink.show().wait()
--         log.info("e-paper 1.54", "Testing End")
--     end
-- end)


sys.run()
