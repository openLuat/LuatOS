
local dhcpsrv = {}

local udpsrv = require("udpsrv")

local TAG = "dhcpsrv"

----
-- 参考地址
-- https://en.wikipedia.org/wiki/Dynamic_Host_Configuration_Protocol

local function dhcp_decode(buff)
    -- buff:seek(0)
    local dst = {}
    -- 开始解析dhcp
    dst.op = buff[0]
    dst.htype = buff[1]
    dst.hlen = buff[2]
    dst.hops = buff[3]
    buff:seek(4)
    dst.xid = buff:read(4)

    _, dst.secs = buff:unpack(">H")
    _, dst.flags = buff:unpack(">H")
    dst.ciaddr = buff:read(4)
    dst.yiaddr = buff:read(4)
    dst.siaddr = buff:read(4)
    dst.giaddr = buff:read(4)
    dst.chaddr = buff:read(16)

    -- 跳过192字节
    buff:seek(192, zbuff.SEEK_CUR)

    -- 解析magic
    _, dst.magic = buff:unpack(">I")

    -- 解析option
    local opt = {}
    while buff:len() > buff:used() do
        local tag = buff:read(1):byte()
        if tag ~= 0 then
            local len = buff:read(1):byte()
            if tag == 0xFF or len == 0 then
                break
            end
            local data = buff:read(len)
            if tag == 53 then
                -- 53: DHCP Message Type
                dst.msgtype = data:byte()
            end
            table.insert(opt, {tag, data})
            -- log.info(TAG, "tag", tag, "data", data:toHex())
        end
    end
    if dst.msgtype == nil then
        return -- 没有解析到msgtype，直接返回
    end
    dst.opts = opt
    return dst
end

local function dhcp_buff2ip(buff)
    return string.format("%d.%d.%d.%d", buff:byte(1), buff:byte(2), buff:byte(3), buff:byte(4))
end

local function dhcp_print_pkg(pkg)
    log.info(TAG, "XID",  pkg.xid:toHex())
    log.info(TAG, "secs", pkg.secs)
    log.info(TAG, "flags", pkg.flags)
    log.info(TAG, "chaddr", pkg.chaddr:sub(1, pkg.hlen):toHex())
    log.info(TAG, "yiaddr", dhcp_buff2ip(pkg.yiaddr))
    log.info(TAG, "siaddr", dhcp_buff2ip(pkg.siaddr))
    log.info(TAG, "giaddr", dhcp_buff2ip(pkg.giaddr))
    log.info(TAG, "ciaddr", dhcp_buff2ip(pkg.ciaddr))
    log.info(TAG, "magic", string.format("%08X", pkg.magic))
    for _, opt in pairs(pkg.opts) do
        if opt[1] == 53 then
            log.info(TAG, "msgtype", opt[2]:byte())
        elseif opt[1] == 60 then
            log.info(TAG, "auth", opt[2])
        elseif opt[1] == 57 then
            log.info(TAG, "Maximum DHCP message size", opt[2]:byte() * 256 + opt[2]:byte(2))
        elseif opt[1] == 61 then
            log.info(TAG, "Client-identifier", opt[2]:toHex())
        elseif opt[1] == 55 then
            log.info(TAG, "Parameter request list", opt[2]:toHex())
        elseif opt[1] == 12 then
            log.info(TAG, "Host name", opt[2])
        -- elseif opt[1] == 58 then
        --     log.info(TAG, "Renewal (T1) time value", opt[2]:unpack(">I"))
        end
    end
end

local function dhcp_encode(pkg, buff)
    -- 合成DHCP包
    buff:seek(0)
    buff[0] = pkg.op
    buff[1] = pkg.htype
    buff[2] = pkg.hlen
    buff[3] = pkg.hops
    buff:seek(4)
    -- 写入XID
    buff:write(pkg.xid)
    -- 几个重要的参数
    buff:pack(">H", pkg.secs)
    buff:pack(">H", pkg.flags)
    buff:write(pkg.ciaddr)
    buff:write(pkg.yiaddr)
    buff:write(pkg.siaddr)
    buff:write(pkg.giaddr)
    -- 写入MAC地址
    buff:write(pkg.chaddr)
    -- 跳过192字节
    buff:seek(192, zbuff.SEEK_CUR)
    -- 写入magic
    buff:pack(">I", pkg.magic)
    -- 写入option
    for _, opt in pairs(pkg.opts) do
        buff:write(opt[1])
        buff:write(#opt[2])
        buff:write(opt[2])
    end
    buff:write(0xFF, 0x00)
end

----

local function dhcp_send_x(srv, pkg, client, msgtype)
    local buff = zbuff.create(300)
    pkg.op = 2
    pkg.ciaddr = "\0\0\0\0"
    pkg.yiaddr = string.char(srv.opts.gw[1], srv.opts.gw[2], srv.opts.gw[3], client.ip)
    pkg.siaddr = string.char(srv.opts.gw[1], srv.opts.gw[2], srv.opts.gw[3], srv.opts.gw[4])
    pkg.giaddr = "\0\0\0\0"
    pkg.secs = 0

    pkg.opts = {} -- 复位option
    table.insert(pkg.opts, {53, string.char(msgtype)})
    table.insert(pkg.opts, {1, string.char(srv.opts.mark[1], srv.opts.mark[2], srv.opts.mark[3], srv.opts.mark[4])})
    table.insert(pkg.opts, {3, string.char(srv.opts.gw[1], srv.opts.gw[2], srv.opts.gw[3], srv.opts.gw[4])})
    table.insert(pkg.opts, {51, "\x00\x00\x1E\x00"}) -- 7200秒, 大概
    table.insert(pkg.opts, {54, string.char(srv.opts.gw[1], srv.opts.gw[2], srv.opts.gw[3], srv.opts.gw[4])})
    table.insert(pkg.opts, {6, string.char(223, 5, 5, 5)})
    table.insert(pkg.opts, {6, string.char(119, 29, 29, 29)})
    table.insert(pkg.opts, {6, string.char(srv.opts.gw[1], srv.opts.gw[2], srv.opts.gw[3], srv.opts.gw[4])})

    dhcp_encode(pkg, buff)

    local dst = "255.255.255.255"
    if 4 == msgtype then
        dst = string.format("%d.%d.%d.%d", srv.opts.gw[1], srv.opts.gw[2], srv.opts.gw[3], client.ip)
    end
    -- log.info(TAG, "发送", msgtype, dst, buff:query():toHex())
    srv.udp:send(buff, dst, 68)
end

local function dhcp_send_offer(srv, pkg, client)
    dhcp_send_x(srv, pkg, client, 2)
end

local function dhcp_send_ack(srv, pkg, client)
    dhcp_send_x(srv, pkg, client, 5)
end

local function dhcp_send_nack(srv, pkg, client)
    dhcp_send_x(srv, pkg, client, 6)
end

local function dhcp_handle_discover(srv, pkg)
    local mac = pkg.chaddr:sub(1, pkg.hlen)
    -- 看看是不是已经分配了ip
    for _, client in pairs(srv.clients) do
        if client.mac == mac then
            log.info(TAG, "发现已经分配的mac地址, send offer")
            dhcp_send_offer(srv, pkg, client)
            return
        end
    end
    -- TODO 清理已经过期的IP分配记录
    -- 分配一个新的ip
    if #srv.clients >= (srv.opts.ip_end - srv.opts.ip_start) then
        log.info(TAG, "没有可分配的ip了")
        return
    end
    local ip = nil
    for i = srv.opts.ip_start, srv.opts.ip_end, 1 do
        if srv.clients[i] == nil then
            ip = i
            break
        end
    end
    if ip == nil then
        log.info(TAG, "没有可分配的ip了")
        return
    end
    log.info(TAG, "分配ip", mac:toHex(), string.format("%d.%d.%d.%d", srv.opts.gw[1], srv.opts.gw[2], srv.opts.gw[3], ip))
    local client = {
        mac = mac,
        ip = ip,
        tm = mcu.ticks() // mcu.hz(),
        stat = 1
    }
    srv.clients[ip] = client
    log.info(TAG, "send offer")
    dhcp_send_offer(srv, pkg, client)
end

local function dhcp_handle_request(srv, pkg)
    local mac = pkg.chaddr:sub(1, pkg.hlen)
    -- 看看是不是已经分配了ip
    for _, client in pairs(srv.clients) do
        if client.mac == mac then
            log.info(TAG, "request,发现已经分配的mac地址, send ack")
            client.tm = mcu.ticks() // mcu.hz()
            stat = 3
            dhcp_send_ack(srv, pkg, client)
            return
        end
    end
    -- 没有找到, 那应该返回NACK
    log.info(TAG, "request,没有分配的mac地址, send nack")
    dhcp_send_nack(srv, pkg, {ip=pkg.yiaddr:byte(1)})
end

local function dhcp_pkg_handle(srv, pkg)
    -- 进行基本的检查
    if pkg.magic ~= 0x63825363 then
        log.warn(TAG, "dhcp数据包的magic不对劲,忽略该数据包", pkg.magic)
        return
    end
    if pkg.op ~= 1 then
        log.info(TAG, "op不对,忽略该数据包", pkg.op)
        return
    end
    if pkg.htype ~= 1 or pkg.hlen ~= 6 then
        log.warn(TAG, "htype/hlen 不认识, 忽略该数据包")
        return
    end
    -- 看看是不是能处理的类型, 当前只处理discover/request
    if pkg.msgtype == 1 or pkg.msgtype == 3 then
    else
        log.warn(TAG, "msgtype不是discover/request, 忽略该数据包", pkg.msgtype)
        return
    end
    -- 检查一下mac地址是否合法
    local mac = pkg.chaddr:sub(1, pkg.hlen)
    if mac == "\0\0\0\0\0\0" or mac == "\xFF\xFF\xFF\xFF\xFF\xFF" then
        log.warn(TAG, "mac地址为空, 忽略该数据包")
        return
    end

    -- 处理discover包
    if pkg.msgtype == 1 then
        log.info(TAG, "是discover包")
        dhcp_handle_discover(srv, pkg)
    elseif pkg.msgtype == 3 then
        log.info(TAG, "是request包")
        dhcp_handle_request(srv, pkg)
    end
    -- TODO 处理结束, 打印一下客户的列表?
end

local function dhcp_task(srv)
    while 1 do
        -- log.info("ulwip", "等待DHCP数据")
        local result, data = sys.waitUntil(srv.udp_topic, 1000)
        if result then
            -- log.info("ulwip", "收到dhcp数据包", data:toHex())
            -- 解析DHCP数据包
            local pkg = dhcp_decode(zbuff.create(#data, data))
            if pkg then
                -- dhcp_print_pkg(pkg)
                dhcp_pkg_handle(srv, pkg)
            end
        end
    end
end
function dhcpsrv.create(opts)
    local srv = {}
    if not opts then
        opts = {}
    end
    srv.udp_topic = "dhcpd_inc"
    -- 补充参数
    if not opts.mark then
        opts.mark = {255, 255, 255, 0}
    end
    if not opts.gw then
        opts.gw = {192, 168, 4, 1}
    end
    if not opts.dns then
        opts.dns = opts.gw
    end
    if not opts.ip_start then
        opts.ip_start = 100
    end
    if not opts.ip_end then
        opts.ip_end = 200
    end

    srv.clients = {}
    srv.opts = opts

    srv.udp = udpsrv.create(67, srv.udp_topic, opts.adapter)
    srv.task = sys.taskInit(dhcp_task, srv)
    return srv
end


return dhcpsrv
