
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ftpdemo"
VERSION = "1.0.0"

--[[
本demo需要ftp库, 大部分能联网的设备都具有这个库
ftp也是内置库, 无需require
]]


sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    
    if wlan and wlan.connect then
        -- wifi 联网, 支持Air8101
        
        local ssid = "luatos1234"
        local password = "12341234"
         
        
        log.info("wifi", ssid, password)
        
        wlan.init()
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        local result, data = sys.waitUntil("IP_READY", 30000)
        log.info("wlan", "IP_READY", result, data)
        device_id = wlan.getMac()
        -- TODO 获取mac地址作为device_id
    
    end
    

    -- -- 打印一下支持的加密套件, 通常来说, 固件已包含常见的99%的加密套件
    -- if crypto.cipher_suites then
    --     log.info("cipher", "suites", json.encode(crypto.cipher_suites()))
    -- end
    while true do
        sys.wait(1000)
        log.info("ftp 启动")
        log.info("ftp Air8101 Start ...")

        
        --print(ftp.debug(on))

        print(ftp.login(nil,"121.43.224.154",21,"ftp_user","3QujbiMG").wait())
    
        --空操作，防止连接断掉
        print(ftp.command("NOOP").wait())

        --报告远程系统的操作系统类型
        print(ftp.command("SYST").wait())

        --设置 FTP 数据传输类型
        print(ftp.command("TYPE I").wait())
        
        -- 显示当前工作目录名
        print(ftp.command("PWD").wait())
        
        --创建目录
        print(ftp.command("MKD QWER").wait())
        
        --改变当前工作目录
        print(ftp.command("CWD /QWER").wait())

        -- 返回上一层目录
        print(ftp.command("CDUP").wait())
        
        -- 删除目录
        print(ftp.command("RMD QWER").wait())

        -- 获取当前工作目录下的文件名列表
        print(ftp.command("LIST").wait())

        -- 向文件写一段测试数据，打印日志检查是否一致
        -- io.writeFile("/12222.txt", "23noianfdiasfhnpqw39fhawe;fuibnnpw3fheaios;fna;osfhisao;fadsfl")
        -- print(ftp.push("/12222.txt","/12222.txt").wait())
        
        --FTP 文件下载 本地文件名1222.txt, 服务器端文件名1222.txt
        print(ftp.pull("/122224.txt","/122224.txt").wait())

        --读取文件 并打印输入文件内容数据
        local f = io.open("/122224.txt", "r")
        if f then
            local data = f:read("*a")
            f:close()
            log.info("fs", "writed data", data)
        else
            log.info("fs", "open file for read failed")
        end

        --删除FTP服务器端文件
        print(ftp.command("DELE /12222.txt").wait())
        
        
        --FTP上传文件 本地文件名122224.txt, 服务器端文件名12222.txt
        print(ftp.push("/122224.txt","/12222.txt").wait())

        --关闭FTP连接
        print(ftp.close().wait())


        log.info("meminfo", rtos.meminfo("sys"))
        sys.wait(15000)
    end


end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
