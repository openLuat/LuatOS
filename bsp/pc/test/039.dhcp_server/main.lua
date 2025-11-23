
sys = require("sys")

-- 参考地址
-- https://en.wikipedia.org/wiki/Dynamic_Host_Configuration_Protocol

function dhcp_decode(buff)
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
        local len = buff:read(1):byte()
        if tag == 0xFF or len == 0 then
            break
        end
        local data = buff:read(len)
        table.insert(opt, {tag, data})
        log.info("DHCP", "tag", tag, "data", data:toHex())
    end
    dst.opts = opt
    return dst
end

function dhcp_buff2ip(buff)
    return string.format("%d.%d.%d.%d", buff:byte(1), buff:byte(2), buff:byte(3), buff:byte(4))
end

function dhcp_print_pkg(pkg)
    log.info("DHCP", "XID",  pkg.xid:toHex())
    log.info("DHCP", "secs", pkg.secs)
    log.info("DHCP", "flags", pkg.flags)
    log.info("DHCP", "chaddr", pkg.chaddr:sub(1, pkg.hlen):toHex())
    log.info("DHCP", "yiaddr", dhcp_buff2ip(pkg.yiaddr))
    log.info("DHCP", "siaddr", dhcp_buff2ip(pkg.siaddr))
    log.info("DHCP", "giaddr", dhcp_buff2ip(pkg.giaddr))
    log.info("DHCP", "ciaddr", dhcp_buff2ip(pkg.ciaddr))
    log.info("DHCP", "magic", string.format("%08X", pkg.magic))
    for _, opt in pairs(pkg.opts) do
        if opt[1] == 53 then
            log.info("DHCP", "msgtype", opt[2]:byte())
        elseif opt[1] == 60 then
            log.info("DHCP", "auth", opt[2])
        elseif opt[1] == 57 then
            log.info("DHCP", "Maximum DHCP message size", opt[2]:byte() * 256 + opt[2]:byte(2))
        elseif opt[1] == 61 then
            log.info("DHCP", "Client-identifier", opt[2]:toHex())
        elseif opt[1] == 55 then
            log.info("DHCP", "Parameter request list", opt[2]:toHex())
        elseif opt[1] == 12 then
            log.info("DHCP", "Host name", opt[2])
        -- elseif opt[1] == 58 then
        --     log.info("DHCP", "Renewal (T1) time value", opt[2]:unpack(">I"))
        end
    end
end

function dhcp_encode(pkg, buff)
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

sys.taskInit(function ()
    local disc = "01010600BC7090C70002000000000000000000000000000000000000DE29876A8F6700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000638253633501013D0701DE29876A8F67390205DC3C0F616E64726F69642D646863702D31340C095869616F6D692D3132370C0103060F1A1C333A3B2B726CFF00"
    --            01010600BC7090C70002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000DE29876A8F6700000000000000000000638253633501013D0701DE29876A8F67390205DC3C0F616E64726F69642D646863702D31340C095869616F6D692D3132370C0103060F1A1C333A3B2B726CFF00
    local disc = "010106001E272667000F000000000000C0A80464C0A8040100000000DE29876A8F6700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000638253633501020104FFFFFF000304C0A804013304000029003604C0A804010604C0A80401FF00"
    disc = disc:fromHex()
    log.info("打印数据", disc:toHex())
    local buff = zbuff.create(#disc, disc)
    local dst = dhcp_decode(buff)
    -- log.info("打印数据", json.encode(dst or {}))
    if dst then
        dhcp_print_pkg(dst)
        local nbuff = zbuff.create(1024)
        dhcp_encode(dst, nbuff)
        log.info("大小对比", #disc, nbuff:used())
        log.info("内容对比", disc == nbuff:query())
        log.info("打印内容", nbuff:query():toHex())
    end
end)

sys.run()
