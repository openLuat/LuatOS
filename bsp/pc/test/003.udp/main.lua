
_G.sys = require("sys")
require "sysplus"

sys.taskInit(function()
    sys.wait(100)
    log.info("创建 udp netc")
    local running = true
    local rxbuff = zbuff.create(1024)
    local netc = socket.create(nil, function(sc, event)
        log.info("udp", sc, string.format("%08X", event))
        if event == socket.EVENT then
            local ok, len, remote_ip, remote_port = socket.rx(sc, rxbuff)
            if ok then
                log.info("remote_ip", remote_ip and remote_ip:toHex())
                if remote_ip and #remote_ip == 5 then
                    local ip1,ip2,ip3,ip4 = remote_ip:byte(2),remote_ip:byte(3),remote_ip:byte(4),remote_ip:byte(5)
                    remote_ip = string.format("%d.%d.%d.%d", ip1, ip2, ip3, ip4)
                else
                    remote_ip = nil
                end
                log.info("socket", "读到数据", rxbuff:query(), remote_ip, remote_port)
                rxbuff:del()
            else
                log.info("socket", "服务器断开了连接")
                running = false
            end
        else
            log.info("udp", "其他事件")
        end
    end)
    log.info("netc", netc)
    socket.config(netc, nil, true)
    -- socket.debug(netc, true)
    log.info("执行连接")
    local ok = socket.connect(netc, "112.125.89.8", 42909)
    log.info("socket connect", ok)

    sys.wait(100)

    -- socket.tx(netc, "ABC", "112.125.89.8", 45022)
    socket.tx(netc, "ABC1234567890")

    while running do
        sys.wait(100)
    end
    log.info("连接中断, 关闭资源")
    socket.close(netc)
    socket.release(netc)
    log.info("全部结束")
end)

sys.run()
