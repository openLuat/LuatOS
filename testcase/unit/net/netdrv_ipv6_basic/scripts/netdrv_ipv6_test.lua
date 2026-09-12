--[[
netdrv.ipv6 基础功能测试

测试条件: PC 模拟器, LUAT_USE_NETDRV + LWIP_IPV6 已启用 (bsp/pc/include/lwipopts.h)
测试内容:
  1. netdrv.setup 的 mac 参数解析 (IPv6 链路本地地址依赖它)
  2. netdrv.ipv6 读取链路本地地址 (fe80::/10, EUI-64)
  3. netdrv.ipv6 设置/读取静态 IPv6 地址, 且 socket.localIP 同步可见
  4. IPv4/IPv6 互不干扰
  5. 参数校验 (非法地址/前缀/id)
  6. 出向数据面: IPv6 以太网帧能经 netdrv 的 CH_HW 出口路径入队并投递
]]

local tests = {}

local TAG = "netdrv_ipv6"
local ADAPTER_ID = socket.LWIP_USER0  -- 与其他 netdrv 用例隔离
local LOCAL_IP   = "192.168.98.1"
local MAC_BYTES  = string.char(0x02, 0x00, 0x00, 0x98, 0x98, 0x01)
local STATIC_V6  = "2001:db8:1234:5678::10"

local _adapter_ready = false

local function now_s()
    return os.clock()
end

-- lwip 的 ip6addr_ntoa 输出大写十六进制, 比较时统一转小写
local function norm_addr(s)
    if type(s) ~= "string" then return s end
    return s:lower()
end

local function mac_hex(s)
    return (s:gsub(".", function(c) return string.format("%02X", string.byte(c)) end))
end

local function wait_ipv6_addr(expected, timeout_ms)
    local deadline = now_s() + (timeout_ms or 2000) / 1000
    local info = {}
    while true do
        info = netdrv.ipv6(ADAPTER_ID) or {}
        if expected == nil or norm_addr(info.addr) == norm_addr(expected) then
            return info
        end
        if now_s() > deadline then
            return info
        end
        sys.wait(50)
    end
end

function tests.setUp()
    if _adapter_ready then return end
    -- 建卡: 显式传 mac, 这是生成 IPv6 链路本地地址(EUI-64)的前提
    local ok = netdrv.setup(ADAPTER_ID, netdrv.WHALE, {
        mtu = 1500,
        mac = MAC_BYTES,
    })
    assert(ok, "whale 设备创建失败")
    sys.wait(200)
    _adapter_ready = true
end

function tests.tearDown()
    -- 保留设备, 每个用例只清理自己的订阅
end

-- T1: API 与常量存在性 + mac 参数解析
function tests.test_01_api_and_mac()
    assert(type(netdrv) == "userdata", "netdrv 模块不存在")
    if netdrv.ipv6 == nil then
        -- LUAT_USE_NETDRV_IPV6 关闭的构建里该 API 整体不存在, 本套件不适用
        -- (bsp/pc 默认开启; 见 components/network/netdrv/include/luat_netdrv.h)
        log.warn(TAG, "LUAT_USE_NETDRV_IPV6 未启用, netdrv.ipv6 不存在, 跳过本套件")
        os.exit(0)
    end
    assert(type(netdrv.ipv6) == "function", "netdrv.ipv6 不是函数")
    assert(netdrv.IPV6_PREFIX_DEFAULT == 64, "IPV6_PREFIX_DEFAULT 应为 64")
    assert(netdrv.IPV6_PREFIX_MAX == 128, "IPV6_PREFIX_MAX 应为 128")

    -- mac 参数必须真正生效(此前 l_netdrv_setup 没有解析 mac)
    local mac = netdrv.mac(ADAPTER_ID)
    assert(mac == mac_hex(MAC_BYTES),
        "netdrv.setup 的 mac 参数未生效, 实际 " .. tostring(mac) .. " 期望 " .. mac_hex(MAC_BYTES))
end

-- T2: 链路本地地址 (建卡时按 MAC 自动生成 EUI-64 链路本地地址)
function tests.test_02_linklocal()
    -- 建卡阶段已调用 net_lwip2_ipv6_create_linklocal(), 这里用 linklocal 读取模式校验
    local info = netdrv.ipv6(ADAPTER_ID, "linklocal")
    assert(type(info) == "table" and #info.addr > 0, "没有生成链路本地地址")
    info = { addr = info.addr, prefix = info.prefix, source = info.source, state = info.state }
    assert(norm_addr(info.addr):sub(1, 5) == "fe80:",
        "链路本地地址应为 fe80::/10 前缀, 实际 " .. tostring(info.addr))
    assert(info.prefix == 64, "链路本地地址前缀应为 64, 实际 " .. tostring(info.prefix))
    assert(info.source == "linklocal", "source 应为 linklocal, 实际 " .. tostring(info.source))
    assert(info.state == "preferred", "state 应为 preferred, 实际 " .. tostring(info.state))
    log.info(TAG, "链路本地地址", info.addr, info.prefix, info.source, info.state)
end

-- T3: 设置静态全局地址并回读
function tests.test_03_set_static_ipv6()
    local ok = netdrv.ipv6(ADAPTER_ID, STATIC_V6, 64)
    assert(ok == true, "netdrv.ipv6 设置静态地址失败")

    local info = wait_ipv6_addr(STATIC_V6, 2000)
    assert(norm_addr(info.addr) == norm_addr(STATIC_V6),
        "回读地址不匹配, 期望 " .. STATIC_V6 .. " 实际 " .. tostring(info.addr))
    assert(info.prefix == 64, "前缀应为 64, 实际 " .. tostring(info.prefix))
    assert(info.source == "static", "source 应为 static, 实际 " .. tostring(info.source))
    assert(info.state == "preferred", "state 应为 preferred, 实际 " .. tostring(info.state))

    -- socket.localIP 的第 4 个返回值应能看到 IPv6
    local _, _, _, ipv6 = socket.localIP(ADAPTER_ID)
    assert(ipv6 ~= nil, "socket.localIP 未返回 IPv6 地址")
    assert(tostring(ipv6):lower() == STATIC_V6:lower(),
        "socket.localIP 返回的 IPv6 与配置不一致: " .. tostring(ipv6))
    log.info(TAG, "静态地址设置成功", info.addr, info.prefix, info.source)
end

-- T4: 设置 IPv4 不影响已配置的 IPv6
function tests.test_04_ipv4_does_not_clear_ipv6()
    -- 先确保有一个静态全局地址, 避免依赖用例执行顺序
    local ok = netdrv.ipv6(ADAPTER_ID, STATIC_V6, 64)
    assert(ok == true, "netdrv.ipv6 设置静态地址失败")
    local info = wait_ipv6_addr(STATIC_V6, 2000)
    assert(norm_addr(info.addr) == norm_addr(STATIC_V6), "前置条件失败: 静态地址未生效")

    netdrv.ipv4(ADAPTER_ID, LOCAL_IP, "255.255.255.0", "192.168.98.254")
    sys.wait(200)

    local ip = netdrv.ipv4(ADAPTER_ID)
    assert(ip == LOCAL_IP, "IPv4 设置失败, 实际 " .. tostring(ip))

    info = netdrv.ipv6(ADAPTER_ID)
    assert(norm_addr(info.addr) == norm_addr(STATIC_V6),
        "设置IPv4后IPv6被清掉了, 实际 " .. tostring(info.addr))
end

-- T5: 参数校验
function tests.test_05_param_check()
    -- 先建立前置条件, 不依赖用例执行顺序
    assert(netdrv.ipv6(ADAPTER_ID, STATIC_V6, 64) == true, "前置条件: 设置静态地址失败")

    assert(netdrv.ipv6(ADAPTER_ID, STATIC_V6, 0) == false, "prefix=0 应被拒绝")
    assert(netdrv.ipv6(ADAPTER_ID, STATIC_V6, 129) == false, "prefix=129 应被拒绝")
    assert(netdrv.ipv6(ADAPTER_ID, "not-an-ip") == false, "非法地址应被拒绝")
    assert(netdrv.ipv6(ADAPTER_ID, "192.168.1.1") == false, "IPv4 字面量应被拒绝")

    -- 不存在的网卡: 读取返回空 table, 设置返回 false
    local empty = netdrv.ipv6(200)
    assert(type(empty) == "table" and empty.addr == nil,
        "不存在的网卡读取应返回空 table, 实际 " .. tostring(empty))
    assert(netdrv.ipv6(200, STATIC_V6, 64) == false, "不存在的网卡设置应返回 false")
    assert(netdrv.ipv6(-1, STATIC_V6, 64) == false, "负id设置应返回 false")

    -- 设置失败不能破坏已有地址
    local info = netdrv.ipv6(ADAPTER_ID)
    assert(norm_addr(info.addr) == norm_addr(STATIC_V6), "参数校验失败后原有地址被破坏")
end

-- T6: IPv6 出向数据面
--   netdrv.send_raw(CH_HW, ...) 是 IPv6 报文从 netdrv 走向物理/airlink 出口的统一路径,
--   也是 airlink EtherType 放行判定(luat_airlink_queue_send_ippkg)的必经之路.
--   历史上 airlink 只放行 IPv4/ARP, IPv6 帧(0x86DD)会在 airlink 那一步被丢弃;
--   该行为由 docs/netdrv_ipv6_compat.md 记录, 这里锁定 netdrv 侧的 IPv6 出口可用性.
function tests.test_06_ipv6_tx_dataplane()
    -- 构造一个最小以太网 IPv6 帧: dst + src + ethertype(0x86DD) + IPv6头起始
    local frame = string.char(
        0x33, 0x33, 0x00, 0x00, 0x00, 0x01,   -- dst: IPv6 组播
        0x02, 0x00, 0x00, 0x98, 0x98, 0x01,   -- src: 本网卡MAC
        0x86, 0xDD,                           -- ethertype: IPv6
        0x60, 0x00, 0x00, 0x00,               -- version/traffic class/flow label
        0x00, 0x18,                           -- payload length
        0x3A, 0x40)                           -- next header=ICMPv6, hop limit=64
    local zb = zbuff.create(#frame, 0)
    zb:write(frame)

    -- send_raw 进入队列后由 tcpip 线程调用 pkg_output -> dataout(airlink),
    -- 返回值为"进入发送队列的字节数", 只要能进入队列即说明 netdrv 侧 IPv6 通路成立
    local sent, err = netdrv.send_raw(ADAPTER_ID, netdrv.CH_HW, zb)
    assert(sent == #frame, "send_raw(CH_HW) IPv6 帧入队失败: " .. tostring(sent) .. " " .. tostring(err))
    sys.wait(100)
    log.info(TAG, "IPv6 帧已入队并投递到出口, len=" .. tostring(sent))
end

-- T7: 以太网模式是"显式开启"的
--   不传 mac / flags 时保持历史行为(裸 IP 帧, 无 MAC, 无 IPv6 链路本地地址),
--   避免影响既有 airlink 部署; 传 mac 或 flags 才切到以太网模式.
function tests.test_07_ethernet_mode_is_opt_in()
    local OTHER_ID = socket.LWIP_USER1
    -- 不传 mac / flags
    local ok = netdrv.setup(OTHER_ID, netdrv.WHALE, { mtu = 1500 })
    assert(ok, "创建 WHALE 设备失败")

    -- 未显式开启以太网模式 -> hwaddr 保持全 0
    local mac = netdrv.mac(OTHER_ID)
    assert(mac == "000000000000",
        "未显式传 mac/flags 时不应以太网化, 实际 MAC=" .. tostring(mac))

    -- 没有 MAC 就没有合法的链路本地地址
    local info = netdrv.ipv6(OTHER_ID, "linklocal")
    assert(type(info) == "table" and info.addr == nil,
        "未以太网化的网卡不应生成链路本地地址, 实际 " .. tostring(info and info.addr))
    log.info(TAG, "未显式传 mac/flags 时保持裸IP模式(无MAC/无链路本地地址)")
end

return tests
