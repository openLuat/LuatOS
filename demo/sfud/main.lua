
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sfuddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- spi_id,pin_cs
local function sfud_spi_pin()
    local rtos_bsp = rtos.bsp()
    if rtos_bsp == "AIR101" then
        return 0,pin.PB04
    elseif rtos_bsp == "AIR103" then
        return 0,pin.PB04
    elseif rtos_bsp == "AIR105" then
        return 5,pin.PC14
    elseif rtos_bsp == "ESP32C3" then
        return 2,7
    elseif rtos_bsp == "ESP32S3" then
        return 2,14
    elseif rtos_bsp == "EC618" then
        return 0,8
    else
        log.info("main", "bsp not support")
        return
    end
end

sys.taskInit(function()
    local spi_id,pin_cs = sfud_spi_pin() 
    if not spi_id then
        while 1 do
            sys.wait(1000)
            log.info("main", "bsp not support yet")
        end
    end

    spi_flash = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,0)
    local ret = sfud.init(spi_flash)
    if ret then
        log.info("sfud.init ok")
    else
        log.info("sfud.init Error")
        return
    end
    log.info("sfud.getDeviceNum",sfud.getDeviceNum())
    local sfud_device = sfud.getDeviceTable()
    log.info("sfud.eraseWrite",sfud.eraseWrite(sfud_device,1024,"sfud"))
    log.info("sfud.read",sfud.read(sfud_device,1024,4))
    log.info("sfud.mount",sfud.mount(sfud_device,"/sfud"))
    log.info("fsstat", fs.fsstat("/sfud"))
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
