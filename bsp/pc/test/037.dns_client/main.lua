
_G.sys = require("sys")
require "sysplus"

function make_dns_query(txid, domain, txbuff)
    txbuff:seek(0)
    txbuff:pack("H", txid) -- 传输ID
    txbuff:write("\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00") -- 标志位
    local pos = 1
    domain = domain .. "."
    for i = 1, #domain, 1 do
        if domain:byte(i) == 0x2E then
            local n = i - pos
            txbuff:pack("bA", n, domain:sub(pos, i - 1))
            -- log.info("分解域名", n, domain:sub(pos, i - 1), domain:sub(pos, i-1))
            pos = i + 1
        end
        -- log.info("domain", domain:sub(i, 1))
    end
    -- txbuff:write(domain) -- 填充域名
    txbuff:write("\x00") -- 需要加个结尾
    txbuff:write("\x00\x01\0x00\x01") -- 填充类型和类
end

local function decode_dns_resp(rxbuff)
    local used = rxbuff:used()
    -- 前2个字节的TX ID,暂不校验
    if rxbuff[2] & 0x80 == 0 then
        log.warn("dns", "并非dns响应")
        return
    end
    if rxbuff[3] & 0x04 ~= 0 then
        log.warn("dns", "是dns响应,但有错误")
        return
    end
    -- 看看查询值是不是0x00 0x01
    if rxbuff[4] ~= 0x00 or rxbuff[5] ~= 0x01 then
        log.warn("dns", "是dns响应,但查询数量不是1,肯定非法")
        return
    end
    -- 普通响应有多少呢
    -- local Ns = rxbuff[8] * 256 + rxbuff[9]
    -- if Ns > 0 then
    --     log.info("dns", "有普通响应", Ns)
    -- end
    -- 先把域名解析出来
    local pos = 12
    local domain = ""
    while rxbuff[pos] ~= 0 do
        local n = rxbuff[pos]
        -- log.info("dns", "找到一段dns域名片段", n)
        domain = domain .. rxbuff:toStr(pos + 1, n) .. "."
        pos = pos + n + 1
    end
    domain = domain:sub(1, #domain - 1)
    log.info("dns", "解析域名", domain)
    pos = pos + 1 + 4 -- 跳过\0和后面的查询类型
    -- 响应有多少呢
    local ARRs = rxbuff[6] * 256 + rxbuff[7]
    if ARRs == 0 then
        log.info("dns", "有响应,但无结果", ARRs)
        return
    end
    for i = 1, ARRs, 1 do
        -- log.info("dns", "第N条记录", i)
        -- 首先是域名
        local n = rxbuff[pos]
        -- log.info("dns", "域名的首段长度", string.format("%02X", n))
        if n & 0xC0 == 0xC0 then
            -- 属于引用长度, 支持解析, 否则就不支持解析咯
            pos = pos + 2
            -- 跳过TYPE和CLASS, 还有长度, 反正都一样
            local tp = rxbuff[pos] * 256 + rxbuff[pos+1]
            -- log.info("dns", "TYPE", tp)
            pos = pos + 2
            local cl = rxbuff[pos] * 256 + rxbuff[pos+1]
            -- log.info("dns", "CLASS", cl)
            pos = pos + 2
            local ttl = (rxbuff[pos] * 256 + rxbuff[pos+1]) * (256 * 256) + rxbuff[pos + 2] * 256 + rxbuff[pos+3]
            -- log.info("dns", "TTL", ttl)
            pos = pos + 4
            local len = rxbuff[pos] * 256 + rxbuff[pos+1]
            -- log.info("dns", "LEN", len)
            pos = pos + 2
            if len == 4 then
                -- 4字节IP
                local ip1,ip2,ip3,ip4 = rxbuff[pos], rxbuff[pos+1], rxbuff[pos+2], rxbuff[pos+3]
                local ip = string.format("%d.%d.%d.%d", ip1, ip2, ip3, ip4)
                log.info("dns", "IP", ip)
                -- return {ip=ip,ttl=ttl}
            end
            pos = pos + len
        else
            log.info("dns", "出现了其他域名", "跳过解析")
        end
    end
end

sys.taskInit(function()
    sys.wait(100)
    log.info("创建 udp netc")
    local running = true
    local rxbuff = zbuff.create(2048)
    local netc = socket.create(nil, function(sc, event)
        -- log.info("udp", sc, string.format("%08X", event))
        if event == socket.EVENT then
            local ok, len, remote_ip, remote_port = socket.rx(sc, rxbuff)
            if ok then
                -- log.info("remote_ip", remote_ip and remote_ip:toHex())
                if remote_ip and #remote_ip == 5 then
                    local ip1,ip2,ip3,ip4 = remote_ip:byte(2),remote_ip:byte(3),remote_ip:byte(4),remote_ip:byte(5)
                    remote_ip = string.format("%d.%d.%d.%d", ip1, ip2, ip3, ip4)
                else
                    remote_ip = nil
                end
                -- log.info("socket", "读到数据", rxbuff:query():toHex(), remote_ip, remote_port)
                decode_dns_resp(rxbuff)
                rxbuff:del()
            else
                log.info("socket", "服务器断开了连接")
                running = false
            end
        else
            -- log.info("udp", "其他事件")
        end
    end)
    log.info("netc", netc)
    socket.config(netc, nil, true)
    -- socket.debug(netc, true)
    log.info("执行连接", ("."):toHex())
    local ok = socket.connect(netc, "223.5.5.5", 53)
    log.info("socket connect", ok)

    sys.wait(100)

    local txbuff = zbuff.create(1024)
    local txid = 1
    -- while running do
    --     -- log.info("发送数据查询数据")
    --     local domain = string.format("%d.air32.cn", txid)
    --     make_dns_query(txid, domain, txbuff)
    --     log.info("发起DNS查询", txbuff:query():toHex())
    --     socket.tx(netc, txbuff)
    --     sys.wait(2000)
    --     txid = txid + 1
    -- end
    make_dns_query(txid, "air32.cn", txbuff)
    socket.tx(netc, txbuff)
    sys.wait(500)

    make_dns_query(txid, "www.baidu.com", txbuff)
    socket.tx(netc, txbuff)
    sys.wait(500)

    make_dns_query(txid, "iot.openluat.com", txbuff)
    socket.tx(netc, txbuff)
    sys.wait(500)

    make_dns_query(txid, "air724ug.cn", txbuff)
    socket.tx(netc, txbuff)
    sys.wait(500)

    make_dns_query(txid, "aliyun.com", txbuff)
    socket.tx(netc, txbuff)
    sys.wait(500)

    -- 加几个肯定不合法的域名

    make_dns_query(txid, "air.cnttt", txbuff)
    socket.tx(netc, txbuff)
    sys.wait(500)

    make_dns_query(txid, "zzz.cnzzz", txbuff)
    socket.tx(netc, txbuff)
    sys.wait(500)


    sys.wait(100000000)

    log.info("连接中断, 关闭资源")
    socket.close(netc)
    socket.release(netc)
    log.info("全部结束")
end)

sys.run()
