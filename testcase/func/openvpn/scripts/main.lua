PROJECT = "openvpn_test"
VERSION = "1.0.0"

AUTHOR = {"luatos"}

--[[
OpenVPN 客户端连通性测试
前置条件:
  1. WSL Docker 中运行 kylemanna/openvpn 服务器 (UDP 1194)
  2. 将生成的 ca.crt / client.crt / client.key 放到本 scripts 目录下
  3. 修改下方 SERVER_IP 为本机实际局域网 IP (或 WSL2 IP)
]]

local sys = require("sys")
-- netdrv 和 socket 是 C 内置模块, 已注册为全局变量, 无需 require

-- ===== 配置区域 =====
local SERVER_IP = "192.168.1.4"     -- 本机局域网 IP
local SERVER_PORT = 1194
-- ====================

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

sys.taskInit(function()
    -- 等待底层网络适配器就绪
    sys.wait(3000)

    log.info("openvpn", "=== OpenVPN client test start ===")

    -- 读取证书文件 (PC模拟器中 scripts 目录映射为 /luadb/)
    local ca = read_file("/luadb/ca.crt")
    local cert = read_file("/luadb/client.crt")
    local key = read_file("/luadb/client.key")

    if not ca then
        log.error("openvpn", "ca.crt not found in scripts dir!")
        return
    end
    if not cert then
        log.error("openvpn", "client.crt not found in scripts dir!")
        return
    end
    if not key then
        log.error("openvpn", "client.key not found in scripts dir!")
        return
    end

    log.info("openvpn", "certs loaded, ca:", #ca, "cert:", #cert, "key:", #key)
    log.info("openvpn", "connecting to", SERVER_IP, SERVER_PORT)

    local ok = netdrv.setup(socket.LWIP_USER0, netdrv.OPENVPN, {
        ovpn_remote_ip = SERVER_IP,
        ovpn_remote_port = SERVER_PORT,
        ovpn_ca_cert = ca,
        ovpn_client_cert = cert,
        ovpn_client_key = key,
        ovpn_retry_enable = true,
        ovpn_retry_base_ms = 2000,
        ovpn_retry_max_ms = 10000,
    })

    log.info("openvpn", "netdrv.setup result:", ok)
    if not ok then
        log.error("openvpn", "setup failed!")
        return
    end

    -- 开启 debug 日志
    netdrv.debug(socket.LWIP_USER0, true)

    -- 等待 TLS 握手 + 数据通道建立
    log.info("openvpn", "waiting for connection (15s)...")
    sys.wait(15000)

    log.info("openvpn", "=== test complete ===")
end)

sys.run()
