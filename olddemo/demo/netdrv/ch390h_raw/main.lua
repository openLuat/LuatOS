--[[
ch390h_raw demo 入口
- 平台: Air780EPM + CH390H SPI 以太网 (LDO 由 GPIO20 控制, 板上默认拉高)
- 适配器: socket.LWIP_ETH (= LWIP_USER0 之前的内部以太网口)
- 流程:
    SPI 初始化 -> 注册 ch390h -> 关闭系统 DHCP -> 等 link up
    -> raw_dhcp 手工跑 DHCP 4 步握手 -> ping_raw 手工跑 ARP+ICMP 探测
- 烧录方式: 把本目录烧到 air780epm, 通过串口日志查看握手过程

本 demo 完全不依赖系统 DHCP 客户端, 全部通过
    netdrv.send_raw(id, netdrv.CH_HW, zbuff)
和
    netdrv.on(id, netdrv.EVT_PKG, cb, { layer = "hw" })
两个接口与物理层直接交互.
]]

PROJECT = "ch390h_raw"
VERSION = "1.0.2"

sys = require "sys"
sysplus = require "sysplus"

local TAG = "ch390h_raw"
local ADAPTER = socket.LWIP_ETH

-- ============================================================
-- 通用工具
-- ============================================================

local function ts() return os.date("%H:%M:%S", os.time()) end

local function log_banner(title)
    log.info(TAG, "============================================")
    log.info(TAG, " " .. title)
    log.info(TAG, "============================================")
end

-- ============================================================
-- 启动
-- ============================================================

log_banner(string.format("ch390h_raw demo v%s 启动 [%s]", VERSION, ts()))
log.info(TAG, "  平台       : Air780EPM + CH390H SPI 以太网")
log.info(TAG, string.format("  适配器     : LWIP_ETH = %d", ADAPTER))
log.info(TAG, "  SPI        : SPI0, CS=GPIO8, 25.6MHz, mode0")
log.info(TAG, "  系统 DHCP  : 已禁用 (全程手工跑)")
log.info(TAG, "  演示模块   : raw_dhcp -> ping_raw")

-- 0. CH390H LDO 供电 (板上 GPIO20 控制 LAN 供电) -------------------------
log.info(TAG, "[0/5] gpio.setup(20, 1)  -- 打开 CH390H LDO")
gpio.setup(20, 1)

-- 1. SPI 初始化 --------------------------------------------------------
log.info(TAG, "[1/5] spi.setup(0, nil, 0, 0, 8, 25600000)")
local spi_result = spi.setup(0, nil, 0, 0, 8, 25600000)
log.info(TAG, string.format("      返回=%d (0=成功, 其他=失败码)", spi_result))
if spi_result ~= 0 then
    log.error(TAG, "      ✗ SPI 初始化失败,中止 demo")
    return
end
log.info(TAG, "      ✓ SPI 就绪")

-- 2. 注册 ch390h -------------------------------------------------------
-- 注: opts 关键字是 "spi" (不是 spiid), 详见 luat_lib_netdrv.c l_netdrv_setup
log.info(TAG, "[2/5] netdrv.setup(LWIP_ETH, CH390, {spi=0, cs=8})")
local setup_ok = netdrv.setup(ADAPTER, netdrv.CH390, { spi = 0, cs = 8 })
log.info(TAG, string.format("      返回=%s", tostring(setup_ok)))
if setup_ok ~= true then
    log.error(TAG, "      ✗ ch390h 注册失败,中止 demo")
    return
end
log.info(TAG, "      ✓ ch390h 设备已注册")

-- 读一下 MAC (DHCP DISCOVER 需要填入 chaddr) ----------------------------
local mac_str = netdrv.mac(ADAPTER)
log.info(TAG, string.format("      本机 MAC = %s", mac_str))

-- 3. 禁用系统 DHCP 客户端 ---------------------------------------------
log.info(TAG, "[3/5] netdrv.dhcp(LWIP_ETH, false) -- 禁用系统 DHCP 客户端")
netdrv.dhcp(ADAPTER, false)
log.info(TAG, "      ✓ 系统 DHCP 已禁用")

-- 4. main task: 等 link -> 等 DHCP -> 加载 ping_raw -------------------
log.info(TAG, "[4/5] 启动 main task (等 link + 等 DHCP + 启动 ping)")
sys.taskInit(function()
    -- 阶段 A: 等 ch390h link up
    log.info(TAG, "      - 阶段 A: 等 ch390h link up")
    local link_start = os.time()
    while netdrv.link(ADAPTER) ~= true do
        if os.time() - link_start > 30 then
            log.error(TAG, "      - link up 30s 超时,中止")
            return
        end
        sys.wait(500)
    end
    log.info(TAG, string.format("      ✓ link up (耗时 %ds) [%s]", os.time() - link_start, ts()))
    sys.publish("RAW_DHCP_LINK_READY")

    -- 阶段 B: 等 raw_dhcp 完成 (60s 超时)
    log.info(TAG, "      - 阶段 B: 等 raw_dhcp 完成 (60s 超时)")
    local dhcp_start = os.time()
    local got = sys.waitUntil("RAW_DHCP_DONE", 60000)
    if not got then
        log.error(TAG, "      ✗ raw DHCP 60s 超时,跳过 ping_raw")
        return
    end
    log.info(TAG, string.format("      ✓ raw DHCP 完成 (耗时 %ds) [%s]",
        os.time() - dhcp_start, ts()))

    -- 让网络稳定一会儿
    sys.wait(2000)

    -- 阶段 C: 加载 ping_raw (静态 IP + ARP/ICMP 探测网关)
    log.info(TAG, "      - 阶段 C: 加载 ping_raw")
end)

-- 5. 加载 raw_dhcp ----------------------------------------------------
log.info(TAG, "[5/5] 加载 raw_dhcp 模块")
require "raw_dhcp"

-- 预加载
require "ping_raw"

log.info(TAG, string.format("进入 sys.run() [%s]", ts()))
sys.run()
