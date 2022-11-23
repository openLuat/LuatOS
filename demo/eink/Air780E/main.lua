
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "einkdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

--[[
-- 接法示例, 以Air780E开发板为例
管脚       Air780E管脚
GND          GND
VCC          3.3V
SCL          (GPIO11)
SDA          (GPIO9)
RES          (GPIO1)
DC           (GPIO10)
CS           (GPIO8)
BUSY         (GPIO22)
]]

-- 全刷模式
sys.taskInit(function()
    eink.model(eink.MODEL_1in54)
    eink.setup(0, 0,22,1,10,8)
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
    eink.setup(1, 0,22,1,10,8)
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
