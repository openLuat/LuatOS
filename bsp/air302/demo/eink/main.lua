
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "einkdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

--[[
本DEMO需要V0005或2020-12-14及之后的源码才支持
]]

--[[
显示屏为佳显 1.54寸,200x200,快刷屏
硬件接线
显示屏SPI          --> Air302 SPI
显示屏 Pin_BUSY        (GPIO18)
显示屏 Pin_RES         (GPIO7)
显示屏 Pin_DC          (GPIO9)
显示屏 Pin_CS          (GPIO16)
]]

function eink154_update()

    eink.clear()

    eink.print(16, 16, os.date(), 0, 12)
    eink.print(16, 32, "LuatOS",  0, 12)
    --eink.print(16, 48, "English - Chinese",  0, 16)

    eink.printcn(16, 64, "中华人民共和国", 0, 16)
    eink.printcn(16, 64+16, "中English混排", 0, 16)
    eink.printcn(16, 64+32, "中日きんぎょ混排", 0, 16)
    eink.printcn(16, 64+16+32, "中俄советский", 0, 16)

    eink.printcn(16, 128, "物联网", 0, 24)
    eink.printcn(16, 128+24, "好记星", 0, 24)
    eink.printcn(16, 128+24+24, "嫦娥五号 いっぽん", 0, 24)

    log.debug("before show")

    -- 刷屏幕
    eink.show()
end



sys.taskInit(function()

    log.info("eink", "begin setup")
    -- 初始化必要的参数
    eink.setup(1, 0)
    -- 设置视窗大小
    eink.setWin(200, 200, 0)
    log.info("eink", "end setup")

    -- 稍微等一会,免得墨水屏没初始化完成
    sys.wait(1000)
    while 1 do
        log.info("e-paper 1.54", "Testing Go\r\n")
        eink154_update()
        log.info("e-paper 1.54", "Testing End\r\n")

        sys.wait(3000) -- 3秒刷新一次
    end
end)

sys.run()
