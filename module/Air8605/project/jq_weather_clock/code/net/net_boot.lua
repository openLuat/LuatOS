--[[
@module  net_boot
@summary Airlink UART 4G 联网初始化（Air8605B：Air1602 主控 + Air780ER2，UART3 @2M）
@version 1.0
@date    2026.11.08
@board   Air8605B（Air1602 主控）+ 外挂 Air780ER2 4G 模组

=== 为什么需要这个文件 ===
本工程原先没有任何网络初始化：weather 直接 http.request，请求打在固件默认网卡上，
8 秒超时返回 -8，日志表现为「定位源失败 → 所有定位源均失败」。
4G 模组不会自己上线，必须显式把 Airlink 拉起来。

=== 与 8605_factory 的对应关系 ===
参数与 factory 的 eng_8605b_10i_v0.lua 里
  network = { { type = "4g_airlink_uart", uart_id = 3, baud = 2000000,
                adapter = socket.LWIP_GP_GW } }
完全一致。小工程不带 net_manager / exnetif 两个文件，所以这里直接调底层 API，
做的事等价于 exnetif.setup_airlink_4G()。

=== 时序前提 ===
必须在 app_main.power_on() 之后调用：4G_RESET = GPIO64 的「高 50ms → 低 120ms」
复位在那个函数里完成，复位没走完就 start 会握不上手。

=== 网卡号必须留在 LWIP_GP_GW ===
4G 的 IP_READY/IP_LOSE 由 C 层固定发在 NW_ADAPTER_INDEX_LWIP_GP_GW 上
（components/airlink/src/exec/luat_airlink_cmd_exec_info.c），换成别的网卡号
（如 LWIP_USER0）链路能起来但永远收不到 IP_READY。
]]

local M = {}

-- ==================== 与 factory 配置保持一致的硬件参数 ====================
local UART_ID = 3
local BAUD    = 2000000
local ADAPTER = socket.LWIP_GP_GW

-- 4G 代理网关：本机侧拿 192.168.111.1，模组侧是 192.168.111.2
local GW_IP, GW_MASK, GW_ADDR = "192.168.111.1", "255.255.255.0", "192.168.111.2"
local MODULE_BOOT_MS = 1000   -- 复位后等模组启动完再握手

local started = false
local ready = false

--- 4G 是否已拿到 IP
function M.is_ready() return ready end

sys.subscribe("IP_READY", function(ip, adapter)
    if adapter ~= ADAPTER then return end
    ready = true
    -- DNS 必须在拿到 IP 之后再设：链路未就绪时设会被 netif 重置清掉
    socket.setDNS(ADAPTER, 1, "114.114.114.114")
    socket.setDNS(ADAPTER, 2, "223.5.5.5")
    log.info("net_boot", "4G 已联网", ip, "adapter", adapter)
end)

--- 启动 4G 联网（幂等，可重复调用）
--- @return boolean 是否已发起初始化
function M.start()
    if started then return true end
    started = true

    if rtos.bsp() == "PC" then
        log.info("net_boot", "PC 模拟器，跳过 4G 初始化")
        return false
    end

    sys.taskInit(function()
        -- 等模组复位 + 启动完成，避免握手打在上电过程中的模组上
        sys.wait(MODULE_BOOT_MS)

        uart.setup(UART_ID, BAUD, 8, 1)
        airlink.config(airlink.CONF_UART_ID, UART_ID)
        airlink.init()

        if netdrv.setup(ADAPTER, netdrv.WHALE) == false then
            log.error("net_boot", "netdrv.setup 失败，4G 无法上线")
            return
        end
        airlink.start(airlink.MODE_UART)

        netdrv.ipv4(ADAPTER, GW_IP, GW_MASK, GW_ADDR)
        -- 默认网卡切到 4G：http/socket 不显式指定 adapter 时就走它
        socket.dft(ADAPTER)
        log.info("net_boot", "Airlink UART 4G 已启动", "UART" .. UART_ID, BAUD,
            "adapter", ADAPTER)

        -- 只做诊断：数据刷新由 weather 订阅 IP_READY 后自行触发
        sys.waitUntil("IP_READY", 120000)
        if not ready then
            log.warn("net_boot", "120s 内未收到 IP_READY，检查 SIM 卡 / 天线 / UART3 接线")
        end
    end)

    return true
end

return M
