-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "keyboarddemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end


sys.taskInit(function ()
    sys.wait(1000)
    keyboard.init(0, 0x1F, 0x14)
    sys.subscribe("KB_INC", function(port, data, state)
        -- port 当前固定为0, 可以无视
        -- data, 需要配合init的map进行解析
        -- state, 1 为按下, 0 为 释放
        log.info("keyboard", port, data, state)
    end)
    while true do
        sys.wait(1000)
        log.info("gpio", "Go Go Go", "https//wiki.luatos.com", rtos.bsp())
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
