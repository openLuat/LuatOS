-- netdrv L2TPv2 客户端基础测试
-- 前置: 先运行 mock_lns.py (见同目录), 再设置 LUAT_L2TP_TEST 运行本套件
local M = {}

local L2TP_ADAPTER = socket.LWIP_USER1
local TUNNEL_PEER = "192.168.8.1"

local function setup_l2tp(overrides)
    local opts = {
        l2tp_remote_ip = "127.0.0.1",
        l2tp_remote_port = M.port or 1701,
        l2tp_username = "testuser",
        l2tp_password = "testpass",
        l2tp_mtu = 1450,
        l2tp_retry_enable = true,
        l2tp_retry_base_ms = 1000,
        l2tp_retry_max_ms = 3000,
    }
    if overrides then
        for k, v in pairs(overrides) do
            opts[k] = v
        end
    end
    return netdrv.setup(L2TP_ADAPTER, netdrv.L2TP, opts)
end

local function wait_ready(timeout_ms)
    local deadline = mcu.ticks() + timeout_ms
    while mcu.ticks() < deadline do
        if netdrv.ready(L2TP_ADAPTER) then
            return true
        end
        sys.wait(200)
    end
    return false
end

-- 隧道内 TCP echo: 连接对端 7 端口, 发送一段数据, 等待原样回显
-- host 可以是 IP, 也可以是域名(用于验证 IPCP 下发的 DNS 是否真的生效)
local function tcp_echo_through_tunnel(host)
    local got = false
    local echoed = false
    local closed = false
    local payload = "hello-l2tp-echo-" .. tostring(mcu.ticks())
    host = host or TUNNEL_PEER

    local sk = socket.create(L2TP_ADAPTER, function(sc, event, param)
        log.info("l2tp_test", "socket event", event, param)
        if event == socket.ON_LINE then
            local zb = zbuff.create(256)
            zb:write(payload)
            local ok, full = socket.tx(sc, zb)
            log.info("l2tp_test", "tx ok/full", ok, full)
        elseif event == socket.EVENT then
            local zb = zbuff.create(256)
            local ok, len = socket.rx(sc, zb)
            log.info("l2tp_test", "rx ok/len", ok, len)
            if ok and len and len > 0 then
                local data = zb:query()
                log.info("l2tp_test", "rx data", data)
                if data == payload then
                    echoed = true
                end
                got = true
            end
        elseif event == socket.CLOSED then
            closed = true
        end
    end)
    assert(sk, "socket.create on L2TP adapter failed")
    socket.config(sk, nil, false, false)
    local ok, result = socket.connect(sk, host, 7)
    log.info("l2tp_test", "connect", host, ok, result)

    local deadline = mcu.ticks() + 15000
    while mcu.ticks() < deadline do
        if echoed then
            break
        end
        if closed then
            break
        end
        sys.wait(200)
    end
    socket.close(sk)
    assert(echoed, "TCP echo through L2TP tunnel failed (" .. tostring(host) .. "), got="
           .. tostring(got) .. " closed=" .. tostring(closed))
    return true
end

-- 正向: 建立隧道 + PPP 认证 + IPCP 下发 IP + 隧道内 TCP echo
function M.test_l2tp_connect()
    if M.mode ~= "pap" and M.mode ~= "chap" and M.mode ~= "mschapv2" then
        return true -- 非本模式, 跳过
    end
    assert(setup_l2tp(), "netdrv.setup(L2TP) failed")
    assert(wait_ready(30000), "L2TP not ready within 30s")

    local ip, mask, gw = socket.localIP(L2TP_ADAPTER)
    log.info("l2tp_test", "tunnel ip/mask/gw", ip, mask, gw)
    assert(ip and ip ~= "0.0.0.0", "tunnel has no ip")
    assert(ip == "192.168.8.2", "unexpected tunnel ip " .. tostring(ip))

    assert(tcp_echo_through_tunnel(), "TCP echo failed")
    return true
end

-- MS-CHAPv2 双向认证负向: LNS 回一个算错的 Authenticator Response,
-- 客户端必须验出来并拒绝建链(chap_ms.c 的 chapms2_check_success)。
-- 这一条是 MSCHAPv2 独有的: CHAP-MD5/PAP 没有服务端应答校验。
function M.test_l2tp_mschapv2_mutual_auth()
    if M.mode ~= "mschapv2-bad" then
        return true -- 非本模式, 跳过
    end
    assert(setup_l2tp(), "netdrv.setup(L2TP) failed")
    assert(not wait_ready(20000),
           "L2TP must NOT become ready when the LNS AuthResponse is wrong")
    log.info("l2tp_test", "bad AuthResponse rejected as expected")
    return true
end

-- 负向: 密码错误 -> 认证失败, 不应 ready
function M.test_l2tp_auth_fail()
    if M.mode ~= "reject" then
        return true -- 非本模式, 跳过
    end
    assert(setup_l2tp({ l2tp_password = "wrongpass" }),
           "netdrv.setup(L2TP) failed")
    -- 认证失败后客户端会退避重试, 这里只需要确认一直没有 ready
    assert(not wait_ready(12000), "L2TP should NOT become ready with bad password")
    log.info("l2tp_test", "auth fail: not ready as expected")
    return true
end

-- L2TP 隧道认证(共享密钥)正向: 带正确 secret -> 建链成功 + 隧道内 echo
function M.test_l2tp_tunnel_secret()
    if M.mode ~= "secret" then
        return true -- 非本模式, 跳过
    end
    assert(setup_l2tp({ l2tp_secret = "tunnel-secret-123" }),
           "netdrv.setup(L2TP) failed")
    assert(wait_ready(30000), "L2TP with tunnel secret not ready within 30s")
    assert(tcp_echo_through_tunnel(), "TCP echo failed with tunnel secret")
    return true
end

-- 隧道认证负向: secret 不匹配 -> LNS 回 StopCCN, 不应 ready
-- (隧道认证是 L2TP 控制面的认证, 与 PPP 认证是两件事)
function M.test_l2tp_tunnel_secret_mismatch()
    if M.mode ~= "secret-bad" then
        return true -- 非本模式, 跳过
    end
    assert(setup_l2tp({ l2tp_secret = "wrong-tunnel-secret" }),
           "netdrv.setup(L2TP) failed")
    assert(not wait_ready(15000),
           "L2TP must NOT become ready with a wrong tunnel secret")
    log.info("l2tp_test", "wrong tunnel secret rejected as expected")
    return true
end

-- IPCP DNS 端到端: mock LNS 在 192.168.8.1:53 应答 "lns.test" -> 192.168.8.1。
-- 用**域名**建链成功, 才说明 IPCP 下发的 DNS 真被装到隧道网卡上并被用上了
-- (只断言"设置成功"是不够的: 设了不用等于没设)。
function M.test_l2tp_ipcp_dns()
    if M.mode ~= "pap" and M.mode ~= "chap" and M.mode ~= "mschapv2" then
        return true -- 非本模式, 跳过
    end
    assert(setup_l2tp(), "netdrv.setup(L2TP) failed")
    assert(wait_ready(30000), "L2TP not ready within 30s")
    assert(tcp_echo_through_tunnel("lns.test"), "DNS-resolved echo failed")
    log.info("l2tp_test", "tunnel DNS resolve + echo ok")
    return true
end

-- 负向: mock 用 --no-dns 不下发 DNS(隧道本身仍正常), 此时域名应解析不了,
-- 但隧道内直连 IP 必须照旧可用 —— 证明"不下发 DNS"不会连带影响链路
function M.test_l2tp_no_ipcp_dns()
    if M.mode ~= "no-dns" then
        return true -- 非本模式, 跳过
    end
    assert(setup_l2tp(), "netdrv.setup(L2TP) failed")
    assert(wait_ready(30000), "L2TP not ready within 30s (DNS 不下发不应影响建链)")
    assert(tcp_echo_through_tunnel(), "IP echo failed without IPCP DNS")

    local online = false
    local sk = socket.create(L2TP_ADAPTER, function(sc, event, param)
        if event == socket.ON_LINE then
            online = true
        end
    end)
    assert(sk, "socket.create failed")
    socket.config(sk, nil, false, false)
    socket.connect(sk, "lns.test", 7)
    local deadline = mcu.ticks() + 8000
    while mcu.ticks() < deadline and not online do
        sys.wait(200)
    end
    socket.close(sk)
    assert(not online, "域名不该解析成功(对端未下发 DNS)")
    log.info("l2tp_test", "no IPCP DNS: domain unresolved as expected, IP path still ok")
    return true
end

-- 断线重连: 等待第一次 ready, 然后观察 IP_LOSE + 再次 ready
function M.test_l2tp_reconnect()
    if M.mode ~= "reconnect" then
        return true -- 非本模式, 跳过
    end
    assert(setup_l2tp(), "netdrv.setup(L2TP) failed")
    assert(wait_ready(30000), "L2TP not ready initially")
    log.info("l2tp_test", "initial ready, waiting for IP_LOSE ...")

    local lost = false
    local lost_id
    sys.subscribe("IP_LOSE", function(id)
        log.info("l2tp_test", "IP_LOSE", id)
        if id == L2TP_ADAPTER then
            lost = true
            lost_id = id
        end
    end)

    local deadline = mcu.ticks() + 30000
    while mcu.ticks() < deadline and not lost do
        sys.wait(200)
    end
    assert(lost, "IP_LOSE not received after session dropped")
    log.info("l2tp_test", "IP_LOSE received, waiting for reconnect ...")

    assert(wait_ready(40000), "L2TP did not reconnect after drop")
    log.info("l2tp_test", "reconnected successfully")
    return true
end

return M
