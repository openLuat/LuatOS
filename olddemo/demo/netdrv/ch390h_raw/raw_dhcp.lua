--[[
raw_dhcp.lua
手工 DHCP 客户端 (不依赖系统 DHCP 客户端)

数据流:
  - 发送: netdrv.send_raw(id, netdrv.CH_HW, zbuff) -> ch390h SPI -> 网线
  - 接收: netdrv.on(id, netdrv.EVT_PKG, cb, {layer="hw"}) <- 网线 -> ch390h SPI
          (layer="hw" 是被动观察: 回调拿到包副本, NAPT/LWIP 流程照常继续)

DHCP 4 步握手:
  1. DISCOVER (broadcast)    -- 我们构造发出
  2. OFFER    (server -> us) -- 从网线收到, 层 hw 拦截
  3. REQUEST  (broadcast)    -- 我们构造发出,带上 server id + requested ip
  4. ACK      (server -> us) -- 从网线收到, 层 hw 拦截

报文格式 (从内到外):
  DHCP (300 字节) -> UDP (8 字节) -> IP (20 字节) -> Ethernet (14 字节)

状态机:
  IDLE -> WAIT_OFFER -> WAIT_ACK -> DONE

依赖 (boot 期 loadedlibs, 无需 require):
  netdrv, zbuff, socket, sys

内部同步:
  使用 sys.publish/subscribe + sys.waitUntil 在包拦截回调和主任务间通信.
  关键: 包可能在 sys.waitUntil 调用前就到, 所以必须用一个状态变量 + 短轮询
  waitUntil 的方式避免丢信号.
]]

local TAG = "raw_dhcp"
local ADAPTER = socket.LWIP_ETH

-- ============================================================
-- DHCP 协议常量
-- ============================================================

local DHCP_OP_REQUEST = 1
local DHCP_OP_REPLY   = 2
local DHCP_HTYPE_ETH  = 1
local DHCP_HLEN_ETH   = 6
local DHCP_MAGIC      = string.char(0x63, 0x82, 0x53, 0x63)

local DHCP_DISCOVER = 1
local DHCP_OFFER    = 2
local DHCP_REQUEST  = 3
local DHCP_DECLINE  = 4
local DHCP_ACK      = 5
local DHCP_NAK      = 6

local DHCP_MSG_NAME = {
    [1]="DISCOVER", [2]="OFFER",   [3]="REQUEST", [4]="DECLINE",
    [5]="ACK",      [6]="NAK",     [7]="RELEASE", [8]="INFORM",
}

-- ============================================================
-- 工具函数
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

local function ip_from_bytes(b, off)
    off = off or 1
    return string.format("%d.%d.%d.%d",
        b:byte(off), b:byte(off+1), b:byte(off+2), b:byte(off+3))
end

-- ============================================================
-- DHCP options 构造 / 解析
-- ============================================================

local function opt_u8(code, val)
    return string.char(code, 1, val & 0xFF)
end

local function opt_u32(code, val)
    return string.char(code, 4,
        (val >> 24) & 0xFF, (val >> 16) & 0xFF,
        (val >> 8)  & 0xFF,  val        & 0xFF)
end

local function opt_ip(code, ip)
    local a, b, c, d = ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")
    return string.char(code, 4, tonumber(a), tonumber(b), tonumber(c), tonumber(d))
end

-- 解析 DHCP options, 返回 { [code] = value_string, msg_type = number }
local function parse_dhcp_options(opts_str)
    local r = {}
    local i = 1
    local n = #opts_str
    while i < n do
        local code = opts_str:byte(i)
        if code == 0xFF then break end
        if code == 0x00 then
            i = i + 1
        else
            local len = opts_str:byte(i + 1)
            if i + 1 + len > n then break end
            local val = opts_str:sub(i + 2, i + 1 + len)
            r[code] = val
            if code == 53 and len == 1 then
                r.msg_type = val:byte(1)
            end
            i = i + 2 + len
        end
    end
    return r
end

-- ============================================================
-- DHCP body 构造 (BOOTP 236 + magic 4 + options)
-- ============================================================

local function build_dhcp_body(op, xid, chaddr, opts_body)
    if #chaddr < 16 then
        chaddr = chaddr .. string.rep("\0", 16 - #chaddr)
    end
    local pkt = {
        string.char(op),                              --  1: op
        string.char(DHCP_HTYPE_ETH),                  --  2: htype
        string.char(DHCP_HLEN_ETH),                   --  3: hlen
        string.char(0),                               --  4: hops
        string.char(                                  --  5-8: xid
            (xid >> 24) & 0xFF,
            (xid >> 16) & 0xFF,
            (xid >> 8)  & 0xFF,
             xid        & 0xFF),
        string.char(0, 0),                            --  9-10: secs
        string.char(0x80, 0x00),                      -- 11-12: flags (broadcast)
        string.char(0, 0, 0, 0),                      -- 13-16: ciaddr
        string.char(0, 0, 0, 0),                      -- 17-20: yiaddr
        string.char(0, 0, 0, 0),                      -- 21-24: siaddr
        string.char(0, 0, 0, 0),                      -- 25-28: giaddr
        chaddr,                                       -- 29-44: chaddr (16 bytes)
        string.rep("\0", 64),                         -- 45-108: sname
        string.rep("\0", 128),                        -- 109-236: file
        DHCP_MAGIC,                                   -- 237-240: magic cookie
    }
    local body = table.concat(pkt) .. opts_body
    if #body < 300 then
        body = body .. string.rep("\0", 300 - #body)
    end
    return body
end

-- ============================================================
-- 构造完整 DHCP 帧 (Ethernet + IP + UDP + DHCP)
-- ============================================================

local function build_dhcp_frame(local_mac, msg_type, xid, chaddr,
                                requested_ip, server_id)
    local opts = {}
    table.insert(opts, opt_u8(53, msg_type))            -- DHCP Message Type
    table.insert(opts, opt_u32(55,                       -- Parameter Request List bitmask
        (1 << 1) | (1 << 3) | (1 << 6) |
        (1 << 15) | (1 << 28) | (1 << 51) |
        (1 << 58) | (1 << 59)))
    if requested_ip then
        table.insert(opts, opt_ip(50, requested_ip))
    end
    if server_id then
        table.insert(opts, opt_ip(54, server_id))
    end
    table.insert(opts, string.char(0xFF))                -- END
    local opts_body = table.concat(opts)

    local dhcp_body = build_dhcp_body(
        DHCP_OP_REQUEST, xid, chaddr, opts_body)

    local udp_len = 8 + #dhcp_body
    local udp_hdr = string.char(
        0, 68,                                         -- src port 68
        0, 67,                                         -- dst port 67
        (udp_len >> 8) & 0xFF, udp_len & 0xFF,         -- length
        0, 0)                                          -- checksum (0 = disabled)

    local ip_total = 20 + udp_len
    local ip_hdr_nochk = string.char(
        0x45, 0x00,
        (ip_total >> 8) & 0xFF, ip_total & 0xFF,
        0x00, 0x00,                                    -- identification
        0x00, 0x00,                                    -- flags + frag offset
        64,                                            -- TTL
        17,                                            -- protocol = UDP
        0x00, 0x00,                                    -- checksum placeholder
        0, 0, 0, 0,                                    -- src IP 0.0.0.0
        255, 255, 255, 255)                            -- dst IP 255.255.255.255
    local csum = checksum16(ip_hdr_nochk)
    local ip_hdr = string.sub(ip_hdr_nochk, 1, 10) ..
                   string.char((csum >> 8) & 0xFF, csum & 0xFF) ..
                   string.sub(ip_hdr_nochk, 13, 20)

    local eth_hdr = string.char(
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,            -- dst MAC (broadcast)
        local_mac:byte(1), local_mac:byte(2),
        local_mac:byte(3), local_mac:byte(4),
        local_mac:byte(5), local_mac:byte(6),          -- src MAC
        0x08, 0x00)                                    -- EtherType = IPv4

    return eth_hdr .. ip_hdr .. udp_hdr .. dhcp_body
end

-- ============================================================
-- 解析接收到的 DHCP 包 (从 on(EVT_PKG) 回调)
-- ============================================================

local function parse_dhcp_frame(zb)
    if zb:used() < 14 + 20 + 8 + 240 then return nil end
    local s = zb:toStr()
    local ethtype = s:byte(13) * 256 + s:byte(14)
    if ethtype ~= 0x0800 then return nil end
    local ip_proto = s:byte(24)
    if ip_proto ~= 17 then return nil end
    local udp_dst = s:byte(37) * 256 + s:byte(38)
    if udp_dst ~= 68 then return nil end
    local udp_len = s:byte(39) * 256 + s:byte(40)
    if udp_len < 8 + 240 then return nil end

    -- dhcp_off = 包中 DHCP 起始位置的前一个字节 (即 UDP 校验和最后一个字节的位置)
    -- DHCP 字节 N (1-based) -> 包字节 dhcp_off + N
    local dhcp_off = 42
    local op = s:byte(dhcp_off + 1)
    if op ~= DHCP_OP_REPLY then return nil end
    local xid = s:byte(dhcp_off + 5) * 0x1000000 +
                s:byte(dhcp_off + 6) * 0x10000 +
                s:byte(dhcp_off + 7) * 0x100 +
                s:byte(dhcp_off + 8)
    local yiaddr = ip_from_bytes(s, dhcp_off + 17)
    local siaddr = ip_from_bytes(s, dhcp_off + 21)
    local chaddr = bytes_to_mac(s, dhcp_off + 29)

    local opts_str = s:sub(dhcp_off + 240 + 1)
    local opts = parse_dhcp_options(opts_str)
    if not opts.msg_type then return nil end

    return {
        msg_type = opts.msg_type,
        msg_name = DHCP_MSG_NAME[opts.msg_type] or "?",
        xid      = xid,
        yiaddr   = yiaddr,
        siaddr   = siaddr,
        chaddr   = chaddr,
        options  = opts,
    }
end

-- ============================================================
-- 状态机 + 主循环
-- ============================================================

local STATE_IDLE       = 0
local STATE_WAIT_OFFER = 1
local STATE_WAIT_ACK   = 2
local STATE_DONE       = 3

local state          = STATE_IDLE
local cur_xid        = 0
local pending_offer  = nil    -- 期望的 OFFER 报文
local pending_ack    = nil    -- 期望的 ACK 报文 (false = NAK)

-- 用 sys.publish/waitUntil 同步: 不同等待阶段用不同 topic
local TOPIC_OFFER = "raw_dhcp_offer"
local TOPIC_ACK   = "raw_dhcp_ack"

-- 在回调里设置状态变量并发布 topic, 在 task 里 waitUntil
local function on_pkg(id, layer, zb)
    if layer ~= netdrv.CH_HW then return end
    if id ~= ADAPTER then return end

    local dhcp = parse_dhcp_frame(zb)
    if not dhcp then return end
    if dhcp.xid ~= cur_xid then return end        -- 不是我们的 xid

    log.info(TAG, string.format("RX %s xid=0x%08X yiaddr=%s siaddr=%s",
        dhcp.msg_name, dhcp.xid, dhcp.yiaddr, dhcp.siaddr))

    if state == STATE_WAIT_OFFER and dhcp.msg_type == DHCP_OFFER then
        pending_offer = dhcp
        sys.publish(TOPIC_OFFER)
    elseif state == STATE_WAIT_ACK then
        if dhcp.msg_type == DHCP_ACK then
            pending_ack = dhcp
            sys.publish(TOPIC_ACK)
        elseif dhcp.msg_type == DHCP_NAK then
            log.error(TAG, "收到 NAK, 重启握手")
            pending_ack = false
            sys.publish(TOPIC_ACK)
        end
    end
end

-- 等 OFFER: 用 sys.waitUntil 短轮询, 兼容"包比 waitUntil 先到"的竞态
-- 参数: deadline_ms = mcu.ticks() 单位 (ms)
local function wait_offer(deadline_ms)
    while state == STATE_WAIT_OFFER do
        if pending_offer then return pending_offer end
        local now = mcu.ticks()
        if now >= deadline_ms then return nil end
        local remain_ms = deadline_ms - now
        if remain_ms < 1 then remain_ms = 1 end
        if remain_ms > 200 then remain_ms = 200 end
        sys.waitUntil(TOPIC_OFFER, remain_ms)
    end
    return nil
end

local function wait_ack(deadline_ms)
    while state == STATE_WAIT_ACK do
        -- pending_ack: nil=未到, false=NAK, table=ACK
        if pending_ack ~= nil then return pending_ack end
        local now = mcu.ticks()
        if now >= deadline_ms then return nil end
        local remain_ms = deadline_ms - now
        if remain_ms < 1 then remain_ms = 1 end
        if remain_ms > 200 then remain_ms = 200 end
        sys.waitUntil(TOPIC_ACK, remain_ms)
    end
    return nil
end

local function send_frame(frame_bytes, label)
    local zb = zbuff.create(#frame_bytes, 0)
    zb:write(frame_bytes)
    local sent = netdrv.send_raw(ADAPTER, netdrv.CH_HW, zb)
    if sent then
        log.info(TAG, string.format("TX %s 已发送 %d 字节", label, sent))
    else
        log.error(TAG, "TX " .. label .. " send_raw 失败")
    end
end

local local_mac_b
local chaddr16

local function send_discover()
    local frame = build_dhcp_frame(local_mac_b, DHCP_DISCOVER, cur_xid, chaddr16)
    log.info(TAG, string.format("TX DISCOVER xid=0x%08X", cur_xid))
    send_frame(frame, "DISCOVER")
end

local function send_request(offer)
    -- RFC 2131: REQUEST 的 option 54 (Server Identifier) 必须填 OFFER 里 server 自报的 IP
    -- siaddr 在很多 DHCP 服务器的实现里是 0.0.0.0, 不能直接用, 否则 server 不认我们的 REQUEST
    local server_id = nil
    if offer.options[54] then
        server_id = ip_from_bytes(offer.options[54])
    end
    if not server_id or server_id == "0.0.0.0" then
        server_id = offer.siaddr ~= "0.0.0.0" and offer.siaddr or nil
    end
    if not server_id then
        log.warn(TAG, "OFFER 里没有 option 54 也没有 siaddr, REQUEST 无法标识 server, 等待 NAK")
    end
    local frame = build_dhcp_frame(local_mac_b, DHCP_REQUEST, cur_xid, chaddr16,
        offer.yiaddr, server_id)
    log.info(TAG, string.format("TX REQUEST xid=0x%08X req=%s srv=%s",
        cur_xid, offer.yiaddr, server_id or "?"))
    send_frame(frame, "REQUEST")
end

-- ============================================================
-- 任务入口
-- ============================================================

sys.taskInit(function()
    sys.waitUntil("RAW_DHCP_LINK_READY", 30000)
    sys.wait(500)

    local mac_str = netdrv.mac(ADAPTER)
    log.info(TAG, string.format("本机 MAC = %s", mac_str))
    local_mac_b = mac_str_to_bytes(mac_str)
    chaddr16 = local_mac_b .. string.rep("\0", 10)

    local ok = netdrv.on(ADAPTER, netdrv.EVT_PKG, on_pkg, { layer = "hw" })
    if not ok then
        log.error(TAG, "注册 netdrv.on 失败, 中止 raw_dhcp")
        _G.RAW_DHCP_RESULT = false
        sys.publish("RAW_DHCP_DONE")
        return
    end
    log.info(TAG, "已注册 netdrv.on(EVT_PKG, layer=hw), 等待 DHCP 报文")

    local got_ack = nil
    local attempt = 0
    while state ~= STATE_DONE do
        attempt = attempt + 1
        if attempt > 5 then
            log.error(TAG, "重试 5 次仍失败, 放弃")
            break
        end

        cur_xid = math.random(0, 0x7FFFFFFE) + 1
        log.info(TAG, string.format("====== DHCP 握手第 %d 轮 xid=0x%08X ======",
            attempt, cur_xid))

        -- DISCOVER
        state = STATE_WAIT_OFFER
        pending_offer = nil
        pending_ack = nil
        local offer_deadline = mcu.ticks() + 12000
        send_discover()
        local offer = wait_offer(offer_deadline)
        if not offer then
            log.error(TAG, "未收到 OFFER, 本轮失败")
            state = STATE_IDLE
            sys.wait(500)
            goto continue
        end
        log.info(TAG, string.format("✓ OFFER: ip=%s mask=%s gw=%s dns=%s lease=%ss server_id=%s",
            offer.yiaddr,
            offer.options[1] and ip_from_bytes(offer.options[1]) or "?",
            offer.options[3] and ip_from_bytes(offer.options[3]) or "?",
            offer.options[6] and ip_from_bytes(offer.options[6]) or "?",
            offer.options[51] and tostring((offer.options[51]:byte(1) * 0x1000000 +
                                              offer.options[51]:byte(2) * 0x10000 +
                                              offer.options[51]:byte(3) * 0x100 +
                                              offer.options[51]:byte(4))) or "?",
            offer.options[54] and ip_from_bytes(offer.options[54]) or "?"))

        -- REQUEST
        state = STATE_WAIT_ACK
        pending_ack = nil
        local ack_deadline = mcu.ticks() + 12000
        send_request(offer)
        local ack = wait_ack(ack_deadline)
        if not ack then
            log.error(TAG, "未收到 ACK, 本轮失败")
            state = STATE_IDLE
            sys.wait(500)
            goto continue
        end
        if ack == false then
            log.error(TAG, "收到 NAK, 重新握手")
            state = STATE_IDLE
            sys.wait(2000)
            goto continue
        end
        log.info(TAG, "✓ ACK 收到")
        got_ack = ack
        state = STATE_DONE
        ::continue::
    end

    -- 把 DHCP 拿到的 IP 应用到 LWIP netif (DHCP 客户端已禁用, 必须手动 ipv4)
    if got_ack then
        local ip  = got_ack.yiaddr
        local mask = got_ack.options[1] and ip_from_bytes(got_ack.options[1]) or "255.255.255.0"
        local gw   = got_ack.options[3] and ip_from_bytes(got_ack.options[3]) or ip
        log.info(TAG, string.format("应用 netdrv.ipv4(%s, %s, %s)", ip, mask, gw))
        netdrv.ipv4(ADAPTER, ip, mask, gw)
        sys.wait(500)
        local real_ip, real_mask, real_gw = netdrv.ipv4(ADAPTER)
        log.info(TAG, string.format("LWIP netif: ip=%s mask=%s gw=%s",
            real_ip or "?", real_mask or "?", real_gw or "?"))
        _G.RAW_DHCP_RESULT = { ip = ip, mask = mask, gw = gw,
                               server = got_ack.siaddr }
    else
        _G.RAW_DHCP_RESULT = false
    end

    netdrv.on(ADAPTER, netdrv.EVT_PKG, nil)
    log.info(TAG, "已关闭 DHCP 包拦截")

    sys.publish("RAW_DHCP_DONE")
end)
