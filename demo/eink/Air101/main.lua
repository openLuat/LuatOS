
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

显示屏 Pin_BUSY        (PB1)
显示屏 Pin_RES         (PA1)
显示屏 Pin_DC          (PA4)
显示屏 Pin_CS          (PB4)
]]

function eink154_update()

    eink.clear()

    eink.print(16, 16, os.date(), 0, eink.font_opposansm12)
    eink.print(16, 32, "LuatOS",  0, eink.font_opposansm12)

    eink.print(16, 64, "中华人民共和国", 0, eink.font_opposansm16_chinese)

    log.debug("before show")

    -- 刷屏幕
    eink.show()
end

sys.taskInit(function()
    eink.model(eink.MODEL_1in54_V2)
    eink.setup(1, 0,17,1,4,20)
    -- eink.setup(1, 0,pin.PB01,pin.PA01,pin.PA04,pin.PB04)-- v0006及以后版本可用pin方式
    eink.setWin(200, 200, 0)
    log.info("eink", "end setup")
    -- 稍微等一会,免得墨水屏没初始化完成
    sys.wait(1000)
    while 1 do
        log.info("e-paper 1.54", "Testing Go\r\n")
        eink154_update()
        log.info("e-paper 1.54", "Testing End\r\n")
        sys.wait(5000) -- 3秒刷新一次
    end
end)

sys.run()
