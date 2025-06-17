
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
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持
        local ssid = "luatos1234"
        local password = "12341234"
        log.info("wifi", ssid, password)
        -- TODO 改成esptouch配网
        -- LED = gpio.setup(12, 0, gpio.PULLUP)
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
        -- LED = gpio.setup(62, 0, gpio.PULLUP)
        sys.wait(1000)
        -- TODO 获取mac地址作为device_id
    elseif mobile then
        -- Air780E/Air600E系列
        --mobile.simid(2)
        -- LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
        sys.waitUntil("IP_READY", 30000)
    end

    -- -- 打印一下支持的加密套件, 通常来说, 固件已包含常见的99%的加密套件
    -- if crypto.cipher_suites then
    --     log.info("cipher", "suites", json.encode(crypto.cipher_suites()))
    -- end
    while true do
        sys.wait(1000)
        log.info("ftp测试启动=====================")
        log.info("登录", ftp.login(nil,"121.43.224.154",21,"ftp_user","3QujbiMG").wait())
    
        log.info("执行NOOP", ftp.command("NOOP").wait())
        log.info("执行SYST", ftp.command("SYST").wait())

        log.info("执行TYPE I", ftp.command("TYPE I").wait())
        log.info("执行PWD", ftp.command("PWD").wait())
        log.info("执行MKD QWER", ftp.command("MKD QWER").wait())
        log.info("执行CWD /QWER", ftp.command("CWD /QWER").wait())

        log.info("执行CDUP", ftp.command("CDUP").wait())
        log.info("执行RMD QWER", ftp.command("RMD QWER").wait())

        log.info("执行LIST", ftp.command("LIST").wait())

        -- io.writeFile("/1222.txt", "23noianfdiasfhnpqw39fhawe;fuibnnpw3fheaios;fna;osfhisao;fadsfl")
        -- log.info("", ftp.push("/1222.txt","/12222.txt").wait())
        
        log.info("执行下载指令", ftp.pull("/122224.txt","/122224.txt").wait())

        local f = io.open("/122224.txt", "r")
        if f then
            local data = f:read("*a")
            f:close()
            log.info("fs", "writed data", data)
        else
            log.info("fs", "open file for read failed")
        end

        log.info("执行删除指令", "删除/12222.txt")
        local result = ftp.command("DELE /12222.txt").wait()
        log.info("执行结果", result)
        log.info("执行上传指令", "/122224.txt")
        io.writeFile("/122224.txt", "23noianfdiasfhnpqw39fhawe;fuibnnpw3fheaios;fna;osfhisao;fadsfl")
        local result = ftp.push("/122224.txt","/12222.txt").wait()
        log.info("执行结果", result)
        log.info("关闭ftp")
        local result = ftp.close().wait()
        log.info("执行结果", result)
        log.info("meminfo", rtos.meminfo("sys"))
        log.info("测试结束,等15秒====================")
        sys.wait(15000)
    end


end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
