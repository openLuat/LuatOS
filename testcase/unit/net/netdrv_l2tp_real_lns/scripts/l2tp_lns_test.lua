-- netdrv L2TPv2 客户端 × 真实 LNS 联调用例 (客户 58.213.164.4)
--
-- 验证点 (对应客户 Windows 配置: L2TP/IPsec + 可选加密 + PAP/CHAP/MS-CHAPv2):
--   1. 该 LNS 允许**无 IPsec 的纯 L2TP**, 隧道 + 会话能建立
--   2. PPP 认证走 CHAP-MD5 (LNS 在 LCP ConfReq 里唯一要求的协议), 认证通过
--   3. IPCP 下发隧道内地址 (LNS 实测给 /32 地址 + 网关 10.129.128.1)
--   4. 数据面: 隧道内 TCP + HTTP 真实往返 (不只是握手)
--
-- 口径: 只读网络, 不改任何配置; 失败一律 assert 抛出, 避免 testrunner "虚绿"
local M = {}

local cfg = require("lns_cfg")

local ADAPTER = socket.LWIP_USER1
local READY_TIMEOUT_MS = 45000
local HTTP_TIMEOUT_MS = 15000

local state = {
    setup_done = false,
    setup_ok = false,
    ready = false,
    ip = nil, mask = nil, gw = nil,
}

local function say(...)
    log.info("l2tp_real", ...)
end

-- 前置: 传输网卡必须是联网的那张。
-- L2TP 在 setup 时抓 network_register_get_default() 作为外层 UDP 传输网卡,
-- 抓错就会从别的网卡(4G/WiFi/隧道自身)出去, 所以这里显式确认并钉住:
--   - PC 模拟器: LWIP_ETH(4) 没有 netdrv, 保持默认网卡(实测默认是 17 = ETH0 宿主网卡)
--   - Air1601 : CH390 外挂以太网注册在 LWIP_ETH(4), 必须钉到它
-- 注意 netdrv 虚拟网卡注册后默认网卡会变成隧道自身(8), 所以这里记住第一次
-- 解析出来的传输网卡, 每次 setup 前重新钉一次。
local TRANSPORT = nil

local function resolve_transport()
    if netdrv.ready(socket.LWIP_ETH) then
        return socket.LWIP_ETH
    end
    local cur = socket.dft and socket.dft() or socket.LWIP_ETH
    if cur == ADAPTER then
        -- 默认网卡已经是隧道自身, 不能再当传输网卡用
        return socket.LWIP_ETH
    end
    return cur
end

local function pin_transport()
    if TRANSPORT == nil then
        TRANSPORT = resolve_transport()
    end
    local cur = socket.dft and socket.dft() or nil
    if cur ~= TRANSPORT and socket.dft then
        pcall(socket.dft, TRANSPORT)
        say("re-pin transport adapter", tostring(cur), "->", TRANSPORT)
    else
        say("transport adapter", TRANSPORT)
    end
end

local function ensure_tunnel()
    if state.setup_done then
        return state.ready
    end
    state.setup_done = true

    assert(cfg.ready, "缺少 LNS 账号/口令: 请设置环境变量 L2TP_USER + L2TP_PASS, "
        .. "或提供 /luadb/lns_secret.txt (user=/pass=)")
    pin_transport()

    local opts = {
        l2tp_remote_ip = cfg.host,
        l2tp_remote_port = cfg.port,
        l2tp_username = cfg.user,
        l2tp_password = cfg.pass,
        l2tp_mtu = 1450,
        l2tp_retry_enable = true,
        l2tp_retry_base_ms = 2000,
        l2tp_retry_max_ms = 10000,
    }
    say("setup", cfg.host, cfg.port, "user=" .. cfg.user, "passwd_source=" .. cfg.source)
    local ok, err = netdrv.setup(ADAPTER, netdrv.L2TP, opts)
    assert(ok, "netdrv.setup(L2TP) 失败: " .. tostring(err))

    local deadline = mcu.ticks() + READY_TIMEOUT_MS
    while mcu.ticks() < deadline do
        if netdrv.ready(ADAPTER) then
            state.ready = true
            break
        end
        sys.wait(200)
    end
    local _, ip, mask, gw = pcall(netdrv.ipv4, ADAPTER)
    state.ip, state.mask, state.gw = ip, mask, gw
    say(string.format("tunnel ready=%s ip=%s mask=%s gw=%s",
        tostring(state.ready), tostring(ip), tostring(mask), tostring(gw)))
    return state.ready
end

-- 隧道内 TCP + HTTP 往返: 连对端 80 端口发 GET, 断言收到 HTTP 响应
local function http_through_tunnel(ip, port)
    local online, closed = false, false
    local rxbytes, first = 0, nil

    local sk = socket.create(ADAPTER, function(sc, event, param)
        if event == socket.ON_LINE then
            online = true
            local zb = zbuff.create(128)
            zb:write("GET / HTTP/1.0\r\nHost: " .. ip .. "\r\nConnection: close\r\n\r\n")
            socket.tx(sc, zb)
        elseif event == socket.EVENT then
            local zb = zbuff.create(1500)
            local ok, len = socket.rx(sc, zb)
            if ok and len and len > 0 then
                rxbytes = rxbytes + len
                if not first then
                    first = tostring(zb:query())
                end
            end
        elseif event == socket.CLOSED then
            closed = true
        end
    end)
    assert(sk, "socket.create(L2TP adapter) 失败")

    socket.config(sk, nil, false, false)
    socket.connect(sk, ip, port)
    local deadline = mcu.ticks() + HTTP_TIMEOUT_MS
    while mcu.ticks() < deadline do
        if closed or rxbytes > 0 then
            break
        end
        sys.wait(200)
    end
    socket.close(sk)
    sys.wait(200)
    socket.release(sk)

    say(string.format("tunnel tcp %s:%d online=%s closed=%s rx=%d",
        ip, port, tostring(online), tostring(closed), rxbytes))
    return online, rxbytes, first
end

-- ============================ 用例 ============================

function M.test_l2tp_tunnel_ready()
    local ready = ensure_tunnel()
    assert(ready, "L2TP 隧道在 " .. (READY_TIMEOUT_MS / 1000) .. "s 内未就绪")
    assert(state.ip and state.ip ~= "0.0.0.0", "未通过 IPCP 拿到隧道地址: " .. tostring(state.ip))
    return true
end

function M.test_l2tp_ipcp_address()
    assert(ensure_tunnel(), "隧道未就绪")
    local _, ip, mask, gw = pcall(netdrv.ipv4, ADAPTER)
    say("ipcp", ip, mask, gw)
    assert(ip == state.ip, "隧道地址发生变化: " .. tostring(ip) .. " != " .. tostring(state.ip))
    assert(gw and gw ~= "0.0.0.0", "IPCP 未下发对端地址")
    return true
end

function M.test_l2tp_tcp_through_tunnel()
    assert(ensure_tunnel(), "隧道未就绪")
    local peer = cfg.peer or state.gw
    assert(peer, "没有可用的隧道内验证目标")
    local online, rxbytes, first = http_through_tunnel(peer, 80)
    assert(online, "隧道内 TCP 未连上 " .. peer .. ":80")
    assert(rxbytes > 0, "隧道内 TCP 连上但没收到任何数据")
    assert(first and first:find("HTTP/"), "隧道内 80 端口未返回 HTTP 响应: " .. tostring(first))
    return true
end

-- 注: 故意不做 teardown/重连用例。对真实 LNS 快速重连可能被限速(实测首个 SCCRQ
-- 偶发被丢, 靠客户端内部重传才成功), 会造成偶发 FAIL; 断线重连机制由
-- netdrv_l2tp_basic(本地 mock LNS) 确定性覆盖。

return M
