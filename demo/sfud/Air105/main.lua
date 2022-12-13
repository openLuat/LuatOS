
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sfuddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

sys = require("sys")

--添加硬狗防止程序卡死
wdt.init(9000)--初始化watchdog设置为9s
sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗

sys.taskInit(function()
    local spi_flash = spi.deviceSetup(1,pin.PA07,0,0,8,10*1000*1000,spi.MSB,1,0)--PA7
    local ret = sfud.init(spi_flash)
    if ret then
        log.info("sfud.init ok")
    else
        log.info("sfud.init Error")
        return
    enderaseWrite
    log.info("sfud.getDeviceNum",sfud.getDeviceNum())
    local sfud_device = sfud.getDeviceTable()
    log.info("sfud.eraseWrite",sfud.eraseWrite(sfud_device,1024,"sfud"))
    log.info("sfud.read",sfud.read(sfud_device,1024,4))
    log.info("sfud.mount",sfud.mount(sfud_device,"/sfud"))
    log.info("fsstat", fs.fsstat("/sfud"))
    while 1 do
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
