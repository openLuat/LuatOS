
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "little_flash demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- spi_id,pin_cs
local function little_flash_spi_pin()
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
    elseif rtos_bsp == "EC718P" then
        return 0,8
    else
        log.info("main", "bsp not support")
        return
    end
end

sys.taskInit(function()
    -- log.info("等5秒")
    sys.wait(1000)
    local spi_id,pin_cs = little_flash_spi_pin() 
    if not spi_id then
        while 1 do
            sys.wait(1000)
            log.info("main", "bsp not support yet")
        end
    end

    log.info("lf", "SPI", spi_id, "CS PIN", pin_cs)
    spi_flash = spi.deviceSetup(spi_id,pin_cs,0,0,8,20*1000*1000,spi.MSB,1,0)
    log.info("lf", "spi_flash", spi_flash)
    little_flash_device = lf.init(spi_flash)
    if little_flash_device then
        log.info("lf.init ok")
    else
        log.info("lf.init Error")
        return
    end

    if lf.mount then
        local ret = lf.mount(little_flash_device,"/little_flash")
        log.info("lf.mount", ret)
        if ret then
            log.info("little_flash", "挂载成功")
            log.info("fsstat", fs.fsstat("/little_flash"))
            
            -- 挂载成功后，可以像操作文件一样操作
            local f = io.open("/little_flash/test", "w")
            f:write(os.date())
            f:close()

            log.info("little_flash", io.readFile("/little_flash/test"))

            -- 文件追加
            os.remove("/little_flash/test2")
            io.writeFile("/little_flash/test2", "LuatOS")
            local f = io.open("/little_flash/test2", "a+")
            f:write(" - " .. os.date())
            f:close()

            log.info("little_flash", io.readFile("/little_flash/test2"))
        else
            log.info("little_flash", "挂载失败")
        end
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
