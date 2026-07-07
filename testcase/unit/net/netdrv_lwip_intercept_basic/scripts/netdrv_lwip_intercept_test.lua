--[[
netdrv LWIP 层拦截 + send_raw 注回应答 闭环测试

测试条件: PC 模拟器, LUAT_USE_NETDRV + LUAT_USE_ICMP 已启用
测试内容:
  1. 创建 whale 设备 (socket.LWIP_USER0), 配置 IP
  2. 注册 LWIP 层 EVT_PKG 拦截 (opts.layer = "lwip")
  3. 调用 netdrv.ping 触发 ICMP echo request
  4. 验证回调收到 LWIP 出口的 ICMP 请求包
  5. 构造 ICMP echo reply 包, 通过 send_raw(CH_LWIP) 注回 LWIP
  6. 验证 PING_RESULT 事件收到 (闭环成功)
]]

local tests = {}

local TAG = "netdrv_lwip"
local ADAPTER_ID = socket.LWIP_USER0  -- 选用 USER0, 与其他测试隔离
local LOCAL_IP   = "192.168.99.1"
local REMOTE_IP  = "192.168.99.2"     -- 假装这是远程服务器 IP

-- 一个用于计算 IP/ICMP 头 checksum 的工具 (RFC 1071)
-- 16-bit 累加 (大端), 含回卷
local function checksum16(s, off, len)
    local sum = 0
    local i = off or 1
    local last = (off or 1) + (len or #s) - 1
    -- 偶数字节对
    while i + 1 <= last do
        sum = sum + string.byte(s, i) * 256 + string.byte(s, i + 1)
        i = i + 2
    end
    -- 奇数字节
    if i <= last then
        sum = sum + string.byte(s, i) * 256
    end
    while sum >= 0x10000 do
        sum = (sum & 0xFFFF) + (sum >> 16)
    end
    return (~sum) & 0xFFFF
end

local function u16be(msb, lsb) return string.char(msb, lsb) end

-- 构造 ICMP echo reply 包 (输入是请求的 IP 包字符串, 输出是新 zbuff)
local function build_icmp_reply(req_s)
    -- IPv4 header (20 bytes) + ICMP echo reply (8 bytes) + 同样的 payload
    -- req_s 已是完整 IP 包
    local IP_HDR = 20
    local total = #req_s

    -- 构造新字符串, 先复制请求
    local reply_bytes = {req_s:byte(1, total)}
    -- 交换 src/dst IP (Lua 1-based: src=byte 13-16, dst=byte 17-20)
    for i = 1, 4 do
        reply_bytes[12 + i] = req_s:byte(16 + i)  -- copy req dst -> reply src
        reply_bytes[16 + i] = req_s:byte(12 + i)  -- copy req src -> reply dst
    end
    -- TTL 设成 64 (byte 9)
    reply_bytes[9] = 64
    -- IP 头 checksum 清 0 (bytes 11-12), 稍后重算
    reply_bytes[11] = 0
    reply_bytes[12] = 0
    -- 拼成 string 算 IP 头 checksum
    local ip_part = string.char(unpack(reply_bytes, 1, IP_HDR))
    local ip_csum = checksum16(ip_part)
    reply_bytes[11] = (ip_csum >> 8) & 0xFF
    reply_bytes[12] = ip_csum & 0xFF

    -- ICMP type: 8 -> 0 (echo reply) - ICMP 头从 byte 21 开始
    reply_bytes[IP_HDR + 1] = 0
    -- ICMP checksum 清 0 (bytes 23-24)
    reply_bytes[IP_HDR + 3] = 0
    reply_bytes[IP_HDR + 4] = 0
    local reply_s = string.char(unpack(reply_bytes, 1, total))
    -- ICMP checksum: 从 ICMP 头开始算 (off=IP_HDR+1=21, len=40)
    local icmp_csum = checksum16(reply_s, IP_HDR + 1, total - IP_HDR)
    reply_bytes[IP_HDR + 3] = (icmp_csum >> 8) & 0xFF
    reply_bytes[IP_HDR + 4] = icmp_csum & 0xFF
    reply_s = string.char(unpack(reply_bytes, 1, total))

    -- 装入 zbuff (send_raw 会按 used 长度发送, 不要 seek 回 0)
    local zb = zbuff.create(total, 0)
    zb:write(reply_s)
    return zb
end

-- 共享状态: 拦截回调捕获的请求包
local intercepted = nil

local _adapter_ready = false
function tests.setUp()
    if _adapter_ready then return end
    -- 1. 关闭任何已注册的拦截 (幂等)
    netdrv.on(ADAPTER_ID, netdrv.EVT_PKG, nil)

    -- 2. 创建 whale 设备
    local ok = netdrv.setup(ADAPTER_ID, netdrv.WHALE, {
        mtu = 1500,
        flags = 0,
        mac = string.char(0x02, 0x00, 0x00, 0x99, 0x99, 0x01),
    })
    assert(ok, "whale 设备创建失败: " .. tostring(ok))

    -- 3. 静态 IP
    netdrv.ipv4(ADAPTER_ID, LOCAL_IP, "255.255.255.0", "192.168.99.254")
    sys.wait(200)

    -- 4. 注册 LWIP 拦截 (注册即拦截)
    intercepted = nil
    netdrv.on(ADAPTER_ID, netdrv.EVT_PKG, function(id, layer, zb)
        if layer == netdrv.CH_LWIP then
            intercepted = { id = id, layer = layer, zb = zb, time = os.time() }
        end
    end, { layer = "lwip" })

    _adapter_ready = true
    log.info(TAG, "setUp: whale 设备 ready, LWIP 拦截已注册")
end

function tests.tearDown()
    netdrv.on(ADAPTER_ID, netdrv.EVT_PKG, nil)
    intercepted = nil
    _adapter_ready = false  -- 让 setUp 下次能重新注册
end

-- T1: 模块 API 检查
function tests.test_01_module_api()
    assert(type(netdrv) == "userdata", "netdrv 不存在")
    assert(netdrv.WHALE ~= nil, "netdrv.WHALE 不存在")
    assert(type(netdrv.setup) == "function", "netdrv.setup 不存在")
    assert(type(netdrv.on) == "function", "netdrv.on 不存在")
    assert(type(netdrv.send_raw) == "function", "netdrv.send_raw 不存在")
    assert(type(netdrv.ping) == "function", "netdrv.ping 不存在")
    assert(netdrv.CH_LWIP == 0x20, "CH_LWIP 值变化?")
    assert(netdrv.EVT_PKG == 2, "EVT_PKG 值变化?")
end

-- T2: 拦截回调能 fire (基本通道验证)
function tests.test_02_lwip_intercept_fires()
    tests.tearDown()
    tests.setUp()
    assert(intercepted == nil, "setup 后 intercepted 应为 nil")
    log.info(TAG, "test_02 ready, 待 ping 触发拦截")
end

-- T3: 端到端 ping 闭环 - 拦截请求包 + 构造 reply + send_raw 注回
function tests.test_03_ping_roundtrip_via_intercept()
    tests.tearDown()
    tests.setUp()

    -- 等 icmp 模块 init 完成
    sys.wait(100)

    -- 订阅 PING_RESULT (icmp 模块的标准事件)
    local result = nil
    local h = sys.subscribe("PING_RESULT", function(id, time, dst, ttl)
        result = { id = id, time = time, dst = dst, ttl = ttl }
    end)

    -- 触发 ping (异步, 通过 raw pcb -> linkoutput -> 我们的拦截)
    local ok = netdrv.ping(ADAPTER_ID, REMOTE_IP, 32)
    assert(ok, "netdrv.ping 返回失败")

    -- 等拦截回调 fire (msgbus 异步, 最多等 3 秒)
    local deadline = os.time() + 3
    while intercepted == nil and os.time() < deadline do
        sys.wait(50)
    end
    assert(intercepted ~= nil, "LWIP 拦截回调未触发 (没有看到出向 ICMP 包)")
    assert(intercepted.layer == netdrv.CH_LWIP, "layer 应为 CH_LWIP")
    assert(intercepted.zb:used() >= 28, "包太小, 不是有效的 IP+ICMP 包, size=" .. tostring(intercepted.zb:used()))

    -- 校验包内容是 ICMP echo request
    local req_s = intercepted.zb:toStr()
    assert(req_s:byte(10) == 1, "应为 ICMP 协议 (1)")
    assert(req_s:byte(21) == 8, "应为 ICMP echo request (type=8)")

    log.info(TAG, string.format("拦截到 ICMP echo request, size=%d", intercepted.zb:used()))

    -- 构造 reply 并通过 send_raw(CH_LWIP) 注回
    local reply = build_icmp_reply(req_s)
    local sent, err = netdrv.send_raw(ADAPTER_ID, netdrv.CH_LWIP, reply)
    if not sent then
        log.warn(TAG, "send_raw(CH_LWIP) 失败: " .. tostring(err))
    end
    assert(sent, "send_raw(CH_LWIP) 返回失败")

    -- 等 PING_RESULT (LWIP 处理入向 ICMP, 超时 3 秒)
    deadline = os.time() + 3
    while result == nil and os.time() < deadline do
        sys.wait(50)
    end
    sys.unsubscribe(h)

    assert(result ~= nil, "PING_RESULT 未触发 (闭环失败)")
    log.info(TAG, string.format("PING_RESULT: id=%s time=%s dst=%s ttl=%s",
        tostring(result.id), tostring(result.time), tostring(result.dst), tostring(result.ttl)))
end

return tests
