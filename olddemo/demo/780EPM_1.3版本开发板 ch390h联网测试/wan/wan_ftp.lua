


sys.taskInit(function()

    sys.waitUntil("CH390_IP_READY")
    log.info("CH390 联网成功，开始测试")
    socket.dft(socket.LWIP_ETH)
    -- 如果自带的DNS不好用，可以用下面的公用DNS,但是一定是要在CH390联网成功后使用
    -- socket.setDNS(socket.LWIP_ETH,1,"223.5.5.5")	
    -- socket.setDNS(nil,1,"114.114.114.114")

    while true do
        sys.wait(1000)
        log.info("ftp 启动")
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

        io.writeFile("/1222.txt", "23noianfdiasfhnpqw39fhawe;fuibnnpw3fheaios;fna;osfhisao;fadsfl")
        print(ftp.push("/1222.txt","/12222.txt").wait())
        
        print(ftp.pull("/122224.txt","/122224.txt").wait())

        local f = io.open("/122224.txt", "r")
        if f then
            local data = f:read("*a")
            f:close()
            log.info("fs", "writed data", data)
        else
            log.info("fs", "open file for read failed")
        end

        print(ftp.command("DELE /12222.txt").wait())
        print(ftp.push("/122224.txt","/12222.txt").wait())
        print(ftp.close().wait())
        log.info("meminfo", rtos.meminfo("sys"))
        sys.wait(15000)
    end


end)
