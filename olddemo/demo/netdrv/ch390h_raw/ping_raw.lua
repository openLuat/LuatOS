--[[
ping_raw.lua
手工 ARP + ICMP echo 实现 ping 网关

注意:
  本 demo 故意不使用 netdrv.ping, 而是通过
    netdrv.send_raw(id, netdrv.CH_HW, zbuff)
  把手工构造的 ARP / ICMP 包发到物理层, 通过
    netdrv.on(id, netdrv.EVT_PKG, cb, { layer = "hw" })
  拦截对端的回应包.

演示步骤 (静态 IP):
  1) netdrv.ipv4() 设置静态 IP / 掩码 / 网关
  2) 手工构造 ARP request (Ethernet + ARP), 通过 send_raw(CH_HW) 广播
  3) on(EVT_PKG, layer="hw") 捕获网关 ARP reply, 提取网关 MAC
  4) 手工构造 ICMP echo request (Ethernet + IP + ICMP),
     dst MAC = 上面拿到的网关 MAC
  5) on(EVT_PKG, layer="hw") 捕获 ICMP echo reply, 计算 RTT
  6) 周期性重复, 输出统计

报文格式 (从内到外):
  ICMP (8 + payload) -> IP (20) -> Ethernet (14)   -- ICMP echo
  ARP (28)          -> Ethernet (14)               -- ARP request/reply

依赖 (boot 期 loadedlibs, 无需 require):
  netdrv, zbuff, socket, sys
]]

local TAG = "ping_raw"
local ADAPTER = socket.LWIP_ETH

-- ============================================================
-- IP 配置: 直接用 raw_dhcp 拿到的, 不自定义
-- ============================================================
-- 自定义 IP 会导致网关 ARP cache 重学, 期间丢包.
-- 用 DHCP 拿到的 IP, 网关 cache 一直是有效的.

-- ping 参数
-- ICMP id / IP id 都必须每次请求唯一 (固定值会被部分路由器按 IP id 去重).
-- ICMP_ID_BASE 用 mcu.ticks() 取本 session 的低 16 位作起点, 每次 ping 自增;
-- IP id 用独立的 pkt_ip_id 计数器, 每发一包 +1.
local ICMP_ID_BASE  = (mcu.ticks() & 0xFFFF)   -- session 起点
local ICMP_PAYLOAD  = "LuatOS-raw-ping"        -- 16 字节
local PING_INTERVAL = 500                     -- ms
local ARP_TIMEOUT   = 3000                     -- ms
local ICMP_TIMEOUT  = 3000                     -- ms
local PING_COUNT    = 16                        -- 总次数
local ARP_RETRIES   = 3                        -- ARP 请求重试次数

-- 实际生效的 IP 配置 (从 raw_dhcp 拿到的)
local MY_IP
local MY_MASK
local MY_GW

-- ============================================================
-- 工具
-- ============================================================

local function ts() return os.date("%H:%M:%S", os.time()) end

local function mac_str_to_bytes(mac_str)
    -- 兼容多种格式: "AABBCCDDEEFF" / "AA:BB:CC:DD:EE:FF" / "AA-BB-CC-DD-EE-FF"
    local s = mac_str:gsub("[:-]", ""):upper()
    if #s ~= 12 then return nil end
    local b = {}
    for i = 1, 12, 2 do
        b[#b+1] = tonumber(s:sub(i, i+1), 16)
    end
    if not (b[1] and b[2] and b[3] and b[4] and b[5] and b[6]) then
        return nil
    end
    return string.char(b[1], b[2], b[3], b[4], b[5], b[6])
end

local function bytes_to_mac(s, off)
    off = off or 1
    return string.format("%02X:%02X:%02X:%02X:%02X:%02X",
        s:byte(off),   s:byte(off+1), s:byte(off+2),
        s:byte(off+3), s:byte(off+4), s:byte(off+5))
end

local function ip_to_bytes(ip)
    local a, b, c, d = ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")
    return string.char(tonumber(a), tonumber(b), tonumber(c), tonumber(d))
end

local function ip_from_bytes(b, off)
    off = off or 1
    return string.format("%d.%d.%d.%d",
        b:byte(off), b:byte(off+1), b:byte(off+2), b:byte(off+3))
end

-- RFC 1071: 16-bit 大端累加 + 回卷 + 取反
local function checksum16(s, off, len)
    off = off or 1
    len = len or #s
    local last = math.min(off + len - 1, #s)
    local sum = 0
    local i = off
    while i + 1 <= last do
        sum = sum + s:byte(i) * 256 + s:byte(i + 1)
        i = i + 2
    end
    if i <= last then
        sum = sum + s:byte(i) * 256
    end
    while sum >= 0x10000 do
        sum = (sum & 0xFFFF) + (sum >> 16)
    end
    return (~sum) & 0xFFFF
end

-- ============================================================
-- 构造 ARP request (Ethernet + ARP)
-- ============================================================

local function build_arp_request(local_mac_b, local_ip, target_ip)
    local eth_hdr = string.char(
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF) ..
        local_mac_b ..
        string.char(0x08, 0x06)
    local arp = string.char(
        0x00, 0x01,                              -- HTYPE = Ethernet
        0x08, 0x00,                              -- PTYPE = IPv4
        0x06,                                    -- HLEN
        0x04,                                    -- PLEN
        0x00, 0x01) ..                           -- OPER = request
        local_mac_b ..
        ip_to_bytes(local_ip) ..
        string.char(0, 0, 0, 0, 0, 0) ..         -- THA = unknown
        ip_to_bytes(target_ip)
    return eth_hdr .. arp
end

-- ============================================================
-- 构造 ICMP echo request (Ethernet + IP + ICMP)
-- ============================================================

-- 全局 IP 标识计数器 (每发一包自增, 防止路由器按 IP id 去重)
local pkt_ip_id = (mcu.ticks() & 0xFFFF)

local function build_icmp_echo_request(local_mac_b, local_ip,
                                       dst_mac_b, dst_ip,
                                       icmp_id, icmp_seq, payload)
    pkt_ip_id = (pkt_ip_id + 1) & 0xFFFF
    local ip_id = pkt_ip_id

    local icmp_hdr_nochk = string.char(
        0x08, 0x00,                              -- type=8 (echo req), code=0
        0x00, 0x00,                              -- checksum placeholder
        (icmp_id  >> 8) & 0xFF, icmp_id  & 0xFF,
        (icmp_seq >> 8) & 0xFF, icmp_seq & 0xFF) ..
        payload
    local icmp_csum = checksum16(icmp_hdr_nochk)
    local icmp = string.sub(icmp_hdr_nochk, 1, 2) ..
                 string.char((icmp_csum >> 8) & 0xFF, icmp_csum & 0xFF) ..
                 string.sub(icmp_hdr_nochk, 5)

    local ip_total = 20 + #icmp
    local ip_hdr_nochk = string.char(
        0x45, 0x00,
        (ip_total >> 8) & 0xFF, ip_total & 0xFF,
        (ip_id >> 8) & 0xFF, ip_id & 0xFF,       -- identification (独立于 ICMP id)
        0x40, 0x00,                              -- flags=DF, frag off=0
        64,                                      -- TTL
        0x01,                                    -- protocol = ICMP
        0x00, 0x00) ..                           -- checksum placeholder
        ip_to_bytes(local_ip) ..
        ip_to_bytes(dst_ip)
    local ip_csum = checksum16(ip_hdr_nochk)
    local ip_hdr = string.sub(ip_hdr_nochk, 1, 10) ..
                   string.char((ip_csum >> 8) & 0xFF, ip_csum & 0xFF) ..
                   string.sub(ip_hdr_nochk, 13, 20)

    local eth_hdr = dst_mac_b .. local_mac_b .. string.char(0x08, 0x00)
    return eth_hdr .. ip_hdr .. icmp
end

-- ============================================================
-- 解析接收到的 ARP 包 (reply only)
-- ============================================================

local function parse_arp_reply(zb)
    if zb:used() < 14 + 28 then return nil end
    local s = zb:toStr()
    local ethtype = s:byte(13) * 256 + s:byte(14)
    if ethtype ~= 0x0806 then return nil end          -- 仅 ARP
    local oper = s:byte(21) * 256 + s:byte(22)
    if oper ~= 2 then return nil end                  -- 仅 reply
    local spa = ip_from_bytes(s, 29)                  -- sender protocol addr
    local sha = bytes_to_mac(s, 23)                   -- sender hardware addr
    return { spa = spa, sha = sha }
end

-- ============================================================
-- 解析接收到的 ICMP echo reply
-- ============================================================

local function parse_icmp_reply(zb)
    if zb:used() < 14 + 20 + 8 then return nil end
    local s = zb:toStr()
    local ethtype = s:byte(13) * 256 + s:byte(14)
    if ethtype ~= 0x0800 then return nil end          -- 仅 IPv4
    local proto = s:byte(24)
    if proto ~= 1 then return nil end                 -- 仅 ICMP
    local icmp_off = 34                               -- 14 + 20
    local typ = s:byte(icmp_off + 1)
    if typ ~= 0 then return nil end                   -- 仅 echo reply (type=0)
    local id  = s:byte(icmp_off + 5) * 256 + s:byte(icmp_off + 6)
    local seq = s:byte(icmp_off + 7) * 256 + s:byte(icmp_off + 8)
    local src_ip = ip_from_bytes(s, 27)               -- IP src @ bytes 27..30
    return { type = typ, id = id, seq = seq, src_ip = src_ip }
end

-- ============================================================
-- 共享: 包拦截回调 (ARP reply + ICMP reply 共用)
-- ============================================================

local pending_arp_mac       -- 期望 ARP reply -> 网关 MAC 字符串
local pending_icmp_id       -- 期望 ICMP reply -> 本次请求的 ICMP id (per-iter 唯一)
local pending_icmp_seq      -- 期望 ICMP reply -> seq
local pending_icmp_reply    -- 收到的 ICMP reply 数据
local late_reply_log        -- 给超时后到达的 reply 打日志 (调试用)
local rx_count              -- 本次 ICMP 等待期间, 总 RX 包数 (含 ARP/其他)
local rx_non_icmp           -- 本次 ICMP 等待期间, 非 ICMP echo reply 的包数

local my_mac_b              -- 我们的 MAC (6 字节, 提前从 netdrv.mac 读)
local my_mac_s              -- 我们的 MAC 字符串

local TOPIC_ARP  = "ping_raw_arp"
local TOPIC_ICMP = "ping_raw_icmp"

-- 前向声明: send_frame 在 on_pkg 之后定义, 但 on_pkg 里要调用,
-- 必须先声明 local, 否则 Lua 会把它当 global 解析
local send_frame

-- 构造 ARP reply (Ethernet + ARP)
-- 收到 ARP request "who has MY_IP?", 如果是问我们, 直接构造 reply 发回去
local function build_arp_reply(sender_mac_b, sender_ip, target_ip)
    -- Ethernet: dst = sender, src = us, type = ARP
    local eth = sender_mac_b .. my_mac_b .. string.char(0x08, 0x06)
    -- ARP reply: SHA=us, SPA=our IP, THA=sender, TPA=sender IP
    local arp = string.char(
        0x00, 0x01,                              -- HTYPE = Ethernet
        0x08, 0x00,                              -- PTYPE = IPv4
        0x06, 0x04,                              -- HLEN, PLEN
        0x00, 0x02) ..                           -- OPER = reply
        my_mac_b ..
        ip_to_bytes(target_ip) ..
        sender_mac_b ..
        ip_to_bytes(sender_ip)
    return eth .. arp
end

local function on_pkg(id, layer, zb)
    if layer ~= netdrv.CH_HW then return end
    if id ~= ADAPTER then return end

    rx_count = (rx_count or 0) + 1

    -- 1) 解析: ARP 包还是 IPv4 包
    if zb:used() < 14 + 28 then return end
    local s = zb:toStr()
    local ethtype = s:byte(13) * 256 + s:byte(14)

    if ethtype == 0x0806 then
        -- ARP 包
        local oper = s:byte(21) * 256 + s:byte(22)
        local spa  = ip_from_bytes(s, 29)   -- sender protocol addr
        local sha  = s:sub(7, 12)           -- sender hardware addr (6 bytes)
        local tpa  = ip_from_bytes(s, 39)   -- target protocol addr

        -- 2a) 如果是 ARP request, 且问的是我们的 IP, 立刻手工回 ARP reply
        if oper == 1 and MY_IP and tpa == MY_IP then
            log.info(TAG, string.format("RX ARP req who-has %s tell %s -> 回 ARP reply",
                tpa, spa))
            local reply = build_arp_reply(sha, spa, MY_IP)
            send_frame(reply, "ARP reply (手工)")
        end

        -- 2b) 如果是 ARP reply, 且发送者是网关, 用于解析网关 MAC
        if oper == 2 and pending_arp_mac == nil and MY_GW and spa == MY_GW then
            log.info(TAG, string.format("RX ARP reply: %s is-at %s", spa, bytes_to_mac(s, 7)))
            pending_arp_mac = bytes_to_mac(s, 7)
            sys.publish(TOPIC_ARP)
        end
        return
    end

    if ethtype ~= 0x0800 then return end   -- 只关心 IPv4

    -- 3) IPv4 包: 试 ICMP echo reply
    local icmp = parse_icmp_reply(zb)
    if not icmp then return end

    if pending_icmp_seq and icmp.id == pending_icmp_id and icmp.seq == pending_icmp_seq then
        log.info(TAG, string.format("RX ICMP echo reply: id=0x%X seq=%d from %s",
            icmp.id, icmp.seq, icmp.src_ip))
        pending_icmp_reply = icmp
        sys.publish(TOPIC_ICMP)
        return
    end

    -- 没匹配上, 记下来供 task 端检查
    late_reply_log = string.format("id=0x%X seq=%d from=%s (want id=0x%X seq=%d)",
        icmp.id, icmp.seq, icmp.src_ip,
        pending_icmp_id or -1, pending_icmp_seq or -1)
end

-- send_frame: 真正定义 (前向声明见 on_pkg 之前)
function send_frame(frame_bytes, label)
    local zb = zbuff.create(#frame_bytes, 0)
    zb:write(frame_bytes)
    local sent = netdrv.send_raw(ADAPTER, netdrv.CH_HW, zb)
    if sent then
        log.info(TAG, string.format("TX %s 已发送 %d 字节", label, sent))
        return true
    else
        log.error(TAG, "TX " .. label .. " send_raw 失败")
        return false
    end
end

-- ============================================================
-- 主流程
-- ============================================================

sys.taskInit(function()
    sys.waitUntil("RAW_DHCP_DONE", 60000)
    sys.wait(2000)   -- 等网络稳定

    -- 直接用 DHCP 拿到的 IP, 不自定义. 自定义 IP 会让网关 ARP cache 重学,
    -- 期间丢包, 导致 #4 等后续 ping 失败.
    local dhcp_result = _G.RAW_DHCP_RESULT
    if dhcp_result and dhcp_result.ip then
        MY_IP   = dhcp_result.ip
        MY_MASK = dhcp_result.mask or "255.255.255.0"
        MY_GW   = dhcp_result.gw   or dhcp_result.ip
        log.info(TAG, string.format("使用 DHCP IP: ip=%s mask=%s gw=%s",
            MY_IP, MY_MASK, MY_GW))
    else
        log.error(TAG, "raw_dhcp 未成功, 无 IP 可用, 中止 ping_raw")
        return
    end

    log.info(TAG, "============================================")
    log.info(TAG, " ping_raw 开始 (DHCP IP + ARP + ICMP 手工 ping)")
    log.info(TAG, "============================================")

    -- 1) 读取 MAC (供后续手工 ARP reply 使用)
    my_mac_s = netdrv.mac(ADAPTER)
    my_mac_b = mac_str_to_bytes(my_mac_s)
    log.info(TAG, string.format("[1/4] 本机 MAC = %s (IP=%s, GW=%s)",
        my_mac_s, MY_IP, MY_GW))

    -- 2) 注册包拦截 (HW 入口被动观察, 同时在 callback 里手工回 ARP)
    log.info(TAG, "[2/4] netdrv.on(EVT_PKG, layer=hw) + 手工 ARP reply")
    local ok = netdrv.on(ADAPTER, netdrv.EVT_PKG, on_pkg, { layer = "hw" })
    if not ok then
        log.error(TAG, "      ✗ netdrv.on 注册失败, 中止")
        return
    end
    log.info(TAG, "      ✓ 已注册 ARP / ICMP 拦截 + ARP 自动回复")

    -- 3) ARP 解析网关 MAC
    log.info(TAG, string.format("[3/4] ARP request -> %s", MY_GW))
    local arp_frame = build_arp_request(my_mac_b, MY_IP, MY_GW)
    local gw_mac_b = nil
    local gw_mac_s = nil
    for retry = 1, ARP_RETRIES do
        pending_arp_mac = nil
        send_frame(arp_frame, "ARP req")
        local deadline = mcu.ticks() + ARP_TIMEOUT
        while not pending_arp_mac do
            if mcu.ticks() >= deadline then break end
            local remain = deadline - mcu.ticks()
            if remain > 200 then remain = 200 end
            if remain < 1 then remain = 1 end
            sys.waitUntil(TOPIC_ARP, remain)
        end
        if pending_arp_mac then
            gw_mac_s = pending_arp_mac
            gw_mac_b = mac_str_to_bytes(gw_mac_s)
            break
        end
        log.warn(TAG, string.format("ARP 第 %d 次超时, 重发", retry))
    end

    if not gw_mac_b then
        log.error(TAG, "ARP 多次重试仍无回应, 中止 ping_raw")
        netdrv.on(ADAPTER, netdrv.EVT_PKG, nil)
        return
    end
    log.info(TAG, string.format("      ✓ 网关 MAC = %s", gw_mac_s))

    -- 4) 周期性 ICMP echo
    log.info(TAG, string.format("[4/4] ICMP echo request -> %s x %d 次",
        MY_GW, PING_COUNT))
    local succ, fail = 0, 0
    local total_rtt = 0
    local min_rtt = math.huge
    local max_rtt = 0

    for i = 1, PING_COUNT do
        -- 每次请求用独立的 ICMP id (session 起点 + i), 防止路由器按 id 去重丢包
        local this_icmp_id = (ICMP_ID_BASE + i) & 0xFFFF
        pending_icmp_id  = this_icmp_id
        pending_icmp_seq = i
        pending_icmp_reply = nil
        late_reply_log   = nil
        rx_count         = 0
        rx_non_icmp      = 0

        local req_frame = build_icmp_echo_request(
            my_mac_b, MY_IP,
            gw_mac_b, MY_GW,
            this_icmp_id, i, ICMP_PAYLOAD)

        local replied = false
        local total_attempts = 0
        -- 单次 ping 也允许重试 (路由器对陌生 id 的首个包可能丢)
        local PING_RETRIES = 3
        for attempt = 1, PING_RETRIES do
            pending_icmp_reply = nil
            late_reply_log     = nil
            rx_count           = 0
            rx_non_icmp        = 0
            total_attempts = attempt
            local t0 = mcu.ticks()
            send_frame(req_frame, string.format("ICMP req #%d id=0x%X (尝试 %d/%d)",
                i, this_icmp_id, attempt, PING_RETRIES))

            local deadline = t0 + ICMP_TIMEOUT
            while not replied do
                if pending_icmp_reply and pending_icmp_reply.seq == i then
                    local t1 = mcu.ticks()
                    local rtt = t1 - t0
                    log.info(TAG, string.format("      ✓ #%d reply id=0x%X seq=%d from %s rtt=%dms [%s]",
                        i, pending_icmp_reply.id, pending_icmp_reply.seq, pending_icmp_reply.src_ip, rtt, ts()))
                    succ = succ + 1
                    total_rtt = total_rtt + rtt
                    if rtt < min_rtt then min_rtt = rtt end
                    if rtt > max_rtt then max_rtt = rtt end
                    replied = true
                    break
                end
                if mcu.ticks() >= deadline then break end
                local remain = deadline - mcu.ticks()
                if remain > 100 then remain = 100 end
                if remain < 1 then remain = 1 end
                sys.waitUntil(TOPIC_ICMP, remain)
            end
            if replied then break end
            if late_reply_log then
                log.warn(TAG, string.format("      ↻ #%d 第 %d 次超时但收到错配 ICMP reply: %s (rx_count=%d, non_icmp=%d)",
                    i, attempt, late_reply_log, rx_count, rx_non_icmp))
                late_reply_log = nil
            else
                log.warn(TAG, string.format("      ↻ #%d 第 %d 次未收到 reply (timeout=%dms, rx_count=%d)",
                    i, attempt, ICMP_TIMEOUT, rx_count))
            end
            sys.wait(100)  -- 重发前稍等
        end
        if not replied then
            log.warn(TAG, string.format("      ✗ #%d 最终失败 (%d 次尝试均超时, 累计 rx_count=%d)",
                i, total_attempts, rx_count))
            fail = fail + 1
        end

        if i < PING_COUNT then
            sys.wait(PING_INTERVAL)
        end
    end

    log.info(TAG, "--------------------------------------------")
    if succ > 0 then
        log.info(TAG, string.format(" 统计: 发送=%d 成功=%d 失败=%d 平均 RTT=%dms min=%dms max=%dms",
            PING_COUNT, succ, fail, total_rtt // succ, min_rtt, max_rtt))
    else
        log.info(TAG, string.format(" 统计: 发送=%d 成功=%d 失败=%d (全部超时)",
            PING_COUNT, succ, fail))
    end
    log.info(TAG, "--------------------------------------------")

    netdrv.on(ADAPTER, netdrv.EVT_PKG, nil)
    log.info(TAG, "已关闭包拦截")

    sys.publish("PING_RAW_DONE")
end)
