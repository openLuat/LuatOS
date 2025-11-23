_G.sys = require("sys")
require "sysplus"

log.info("socket.ip", socket.localIP())

sys.taskInit(function()
    sys.wait(100)
    while 1 do
        log.info("创建 netc")
        local running = true
        local rxbuff = zbuff.create(1024)
        local netc = socket.create(nil, function(sc, event)
            log.info("socket", sc, event)
            if event == socket.EVENT then
                while 1 do
                    local ok, len = socket.rx(sc)
                    if not ok then
                        log.info("socket", "服务器断开了连接")
                        running = false
                        break
                    end
                    if len == 0 then
                        break
                    end
                    log.info("socket", "待读取数据长度", len)
                    ok, len = socket.rx(sc, rxbuff, nil, 4) -- 特意每次只读取4字节
                    if ok then
                        if len == 0 then
                            break
                        end
                        log.info("socket", "读到数据", rxbuff:query())
                        rxbuff:del()
                    else
                        log.info("socket", "服务器断开了连接")
                        running = false
                        break
                    end
                end
            end
        end)
        log.info("netc", netc)
        socket.config(netc)
        socket.debug(netc, true)
        socket.connect(netc, "112.125.89.8", 45040)

        while running do
            sys.wait(100)
        end
        log.info("连接中断, 关闭资源")
        socket.close(netc)
        socket.release(netc)
        sys.wait(5000)
    end
    log.info("全部结束")
end)

sys.run()
