
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ftpdemo"
VERSION = "1.0.0"

--[[
本demo需要ftp库, 大部分能联网的设备都具有这个库
ftp也是内置库, 无需require
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用ftp库需要下列语句]]
_G.sysplus = require("sysplus")

sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if rtos.bsp():startsWith("ESP32") then
        -- wifi 联网, ESP32系列均支持
        local ssid = "uiot"
        local password = "12345678"
        log.info("wifi", ssid, password)
        -- TODO 改成esptouch配网
        LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        local result, data = sys.waitUntil("IP_READY", 30000)
        log.info("wlan", "IP_READY", result, data)
        device_id = wlan.getMac()
    elseif rtos.bsp() == "AIR105" then
        -- w5500 以太网, 当前仅Air105支持
        -- w5500.init(spi.SPI_2, 24000000, pin.PB03, pin.PC00, pin.PC03)
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        log.info("auto mac", w5500.getMac():toHex())
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
        LED = gpio.setup(62, 0, gpio.PULLUP)
        sys.wait(1000)
        -- TODO 获取mac地址作为device_id
    elseif rtos.bsp() == "EC618" then
        -- Air780E/Air600E系列
        --mobile.simid(2)
        LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
        sys.waitUntil("IP_READY", 30000)
    end

    -- -- 打印一下支持的加密套件, 通常来说, 固件已包含常见的99%的加密套件
    -- if crypto.cipher_suites then
    --     log.info("cipher", "suites", json.encode(crypto.cipher_suites()))
    -- end
    while true do
        print(ftp.login(nil,"121.43.224.154",21,"ftp_user","3QujbiMG").wait())
    
        print(ftp.command("NOOP").wait())
        print(ftp.command("SYST").wait())

        print(ftp.command("TYPE I").wait())
        print(ftp.command("PWD").wait())
        print(ftp.command("MKD QWER").wait())
        print(ftp.command("CWD /QWER").wait())

        print(ftp.command("CDUP").wait())
        print(ftp.command("RMD QWER").wait())

        print(ftp.command("LIST").wait())
        
        print(ftp.pull("/1222.txt","/1222.txt").wait())

        local f = io.open("/1222.txt", "r")
        if f then
            local data = f:read("*a")
            f:close()
            log.info("fs", "writed data", data)
        else
            log.info("fs", "open file for read failed")
        end

        print(ftp.command("DELE /12222.txt").wait())
        print(ftp.push("/1222.txt","/12222.txt").wait())
        print(ftp.close().wait())
        log.info("meminfo", rtos.meminfo("sys"))
        sys.wait(15000)
    end


end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
