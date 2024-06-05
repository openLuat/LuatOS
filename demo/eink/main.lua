
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "einkdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

--[[

注意,使用前先看本注释每一句话！！！！！！！
注意,使用前先看本注释每一句话！！！！！！！
注意,使用前先看本注释每一句话！！！！！！！

注意:具体硬件接线参考下方eink_pin 函数的gpio定义,
eink_pin函数会返回对应bsp的 spi_id,pin_reset,pin_dc,pin_cs,pin_busy 值,下方函数有注释
spi_id对应引脚参考对应芯片/模组手册,使用开发板的话看开发板原理图

举例AIR101：
AIR101就看bsp判断分支 rtos_bsp == "AIR101"
返回的 0,pin.PB03,pin.PB01,pin.PB04,pin.PB00 依次为 spi_id,pin_reset,pin_dc,pin_cs,pin_busy
spi_id为0就看芯片手册spi0引脚定义，即 SCLK=PB02, MOSI=PB05, MISO=PB03 因为只需要输出所以不需要miso引脚,miso引脚用作了pin_reset
所以AIR101接线为 Pin_RSCL:PB02, Pin_RSDA:PB05, Pin_RES:PB03, Pin_DC:PB01, Pin_CS:PB04, Pin_BUSY:PB00

再举例EC618：
EC618就看bsp判断分支 rtos_bsp == "EC618"
返回的 0,1,10,8,22 依次为 spi_id,pin_reset,pin_dc,pin_cs,pin_busy
spi_id为0就看芯片手册spi0引脚定义，即 SCLK=GPIO11, MOSI=GPIO9, MISO=GPIO10 因为只需要输出所以不需要miso引脚,miso引脚用作了pin_dc
所以EC618接线为 Pin_RSCL:GPIO11, Pin_RSDA:GPIO9, Pin_RES:GPIO1, Pin_DC:GPIO10, Pin_CS:GPIO8, Pin_BUSY:GPIO22


本demo为 1.54寸v2,200x200 屏幕，实际使用什么屏幕自己看自己的屏幕规格，
不是一样的尺寸就随便用，后缀的 v1 v2 v3 abcd 都有区别并不通用否则不同驱动就没意义了

注意,使用前先看本注释！！！！！！！
注意,使用前先看本注释！！！！！！！
注意,使用前先看本注释！！！！！！！

]]


local rtos_bsp = rtos.bsp()

-- spi_id,pin_reset,pin_dc,pin_cs,pin_busy
function eink_pin()     
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
    elseif rtos_bsp == "EC718P" then
        return 0,10,14,8,15
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

-- 2022.12.02后编译的固件推荐使用以下方法
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
