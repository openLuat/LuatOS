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
local function tcp_echo_through_tunnel()
    local got = false
    local echoed = false
    local closed = false
    local payload = "hello-l2tp-echo-" .. tostring(mcu.ticks())

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
    local ok, result = socket.connect(sk, TUNNEL_PEER, 7)
    log.info("l2tp_test", "connect", ok, result)

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
    assert(echoed, "TCP echo through L2TP tunnel failed, got=" .. tostring(got)
           .. " closed=" .. tostring(closed))
    return true
end

-- 正向: 建立隧道 + PPP 认证 + IPCP 下发 IP + 隧道内 TCP echo
function M.test_l2tp_connect()
    if M.mode ~= "pap" and M.mode ~= "chap" then
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
