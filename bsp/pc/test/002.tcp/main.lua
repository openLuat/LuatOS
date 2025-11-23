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
                local ok = socket.rx(sc, rxbuff)
                if ok then
                    log.info("socket", "读到数据", rxbuff:query())
                    rxbuff:del()
                else
                    log.info("socket", "服务器断开了连接")
                    running = false
                end
            end
        end)
        log.info("netc", netc)
        socket.config(netc)
        socket.debug(netc, true)
        socket.connect(netc, "112.125.89.8", 41506)

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
