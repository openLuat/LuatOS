-- netdrv IKEv2/IPsec (tunnel mode) 客户端基础测试
-- 前置:
--   1. 宿主机可访问 ipsec.air32.cn (UDP 500/4500)
--   2. scripts 目录下存在 ikev2-ca.crt (网关私建 CA, 由脚本作为
--      ipsec_ca_cert_pem 提供给客户端, 不再依赖内置 Let's Encrypt 锚)
local M = {}

local IPSEC_ADAPTER = socket.LWIP_USER1

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function setup_ipsec(overrides)
    local opts = {
        ipsec_remote_ip = "154.8.159.79",   -- ipsec.air32.cn
        ipsec_remote_port = 500,
        ipsec_username = "vpnuser",
        ipsec_password = "fnXYgmwsJWpSGYwR",
        ipsec_san = "ipsec.air32.cn",
        ipsec_mtu = 1400,
        ipsec_retry_enable = true,
        ipsec_retry_base_ms = 1000,
        ipsec_retry_max_ms = 3000,
        ipsec_ca_cert_pem = read_file("/luadb/ikev2-ca.crt"),
    }
    if overrides then
        for k, v in pairs(overrides) do
            opts[k] = v
        end
    end
    return netdrv.setup(IPSEC_ADAPTER, netdrv.IPSEC, opts)
end

local function wait_ready(timeout_ms)
    local deadline = mcu.ticks() + timeout_ms
    while mcu.ticks() < deadline do
        if netdrv.ready(IPSEC_ADAPTER) then
            return true
        end
        sys.wait(200)
    end
    return false
end

-- 隧道内 TCP: 连接网关内网 SSH (10.0.24.11:22), 期望收到 SSH banner
local function tcp_through_tunnel()
    local got = false
    local sk = socket.create(IPSEC_ADAPTER, function(sc, event, param)
        if event == socket.EVENT then
            local zb = zbuff.create(256)
            local okrx, len = socket.rx(sc, zb)
            if okrx and len and len > 0 then
                got = true
            end
        end
    end)
    assert(sk, "socket.create on IPSEC adapter failed")
    socket.config(sk, nil, false, false)
    socket.connect(sk, "10.0.24.11", 22)

    local deadline = mcu.ticks() + 15000
    while mcu.ticks() < deadline and not got do
        sys.wait(200)
    end
    socket.close(sk)
    assert(got, "TCP through IPsec tunnel failed (no SSH banner)")
    return true
end

-- 正向: 建立 IKE_SA_INIT -> EAP-MSCHAPv2 -> CP 下发虚拟 IP
function M.test_ipsec_connect()
    if M.mode ~= "connect" then
        return true
    end
    assert(setup_ipsec(), "netdrv.setup(IPSEC) failed")
    assert(wait_ready(45000), "IPsec not ready within 45s")

    local ip, mask, gw = socket.localIP(IPSEC_ADAPTER)
    log.info("ipsec_test", "tunnel ip/mask/gw", ip, mask, gw)
    assert(ip and ip ~= "0.0.0.0", "tunnel has no virtual IP")
    assert(tcp_through_tunnel(), "tunnel TCP data path failed")
    return true
end

-- 负向: 密码错误 -> EAP 认证失败, 不应 ready
function M.test_ipsec_badpass()
    if M.mode ~= "badpass" then
        return true
    end
    assert(setup_ipsec({ ipsec_password = "wrongpass" }),
           "netdrv.setup(IPSEC) failed")
    assert(not wait_ready(20000), "IPsec should NOT become ready with bad password")
    log.info("ipsec_test", "auth fail: not ready as expected")
    return true
end

-- 负向: SAN 校验失败 (证书里没有该名字), 不应 ready
function M.test_ipsec_bad_san()
    if M.mode ~= "sanit" then
        return true
    end
    assert(setup_ipsec({ ipsec_san = "wrong.example.com" }),
           "netdrv.setup(IPSEC) failed")
    assert(not wait_ready(25000), "IPsec should NOT become ready with wrong SAN")
    log.info("ipsec_test", "san fail: not ready as expected")
    return true
end

return M
