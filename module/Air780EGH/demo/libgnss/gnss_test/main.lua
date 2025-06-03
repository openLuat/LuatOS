
PROJECT = "air780egh_gnss"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")

-- mobile.flymode(0,true)
if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
log.info("main", "air780egh_gnss")


mcu.hardfault(0)    --死机后停机，一般用于调试状态
require("uart1_780egh")

function test_gnss()
    log.debug("提醒", "室内无GNSS信号,定位不会成功, 要到空旷的室外,起码要看得到天空")
    pm.power(pm.GPS, true)
    uart.setup(2,115200)
end
sys.taskInit(test_gnss)


uart.on(2, "receive", function(id, len)
    local s = ""
    repeat
        s = uart.read(id, 2048)
        if #s > 0 then -- #s 是取字符串的长度
            -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            log.info("uart2", "receive", id, #s, s)
            uart.write(1, s)
        end
    until s == ""
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
