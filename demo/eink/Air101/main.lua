
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "einkdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

--[[
显示屏为佳显 1.54寸v2,200x200,快刷屏
硬件接线
显示屏SPI          --> Air101 SPI0

SPI0
SPI0_SCK               (PB2)
SPI0_MISO              (PB3)
SPI0_MOSI              (PB5)

显示屏 Pin_BUSY        (PB0)
显示屏 Pin_RES         (PB3)
显示屏 Pin_DC          (PB1)
显示屏 Pin_CS          (PB4)
]]

-- 全刷模式
sys.taskInit(function()
    eink.model(eink.MODEL_1in54)
    eink.setup(0, 0,pin.PB00,pin.PB03,pin.PB01,pin.PB04)
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
end)

-- 快刷模式，使用本模式刷新时极快，但大概率会有残留：
--[[
sys.taskInit(function()
    eink.model(eink.MODEL_1in54)
    eink.setup(1, 0,pin.PB00,pin.PB03,pin.PB01,pin.PB04)
    --初始化时配置局部刷新
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
    eink.show(nil,nil,true)
    --直接刷上去，不清屏
    log.info("e-paper 1.54", "Testing End")
end)
]]

sys.run()
