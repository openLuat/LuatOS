--[[
@module  netif_app
@summary 多网融合：WiFi 提供外网，以太网 LAN 口分流上网，演示 WiFi A -> WiFi B 动态切换
@version 1.1
@date    2026.11.12
@author  王城钧
@usage
本文件为网络管理模块，核心业务逻辑为：
1. 调用 exnetif.setproxy 建立 WiFi A -> 以太网 LAN 多网融合代理（首次自动启用掉线重连）
2. 再次调用 exnetif.setproxy 传入 WiFi B 凭证，库自动检测变化并完成 NAPT/WiFi 切换
3. 全程仅使用 exnetif.setproxy 一个接口，无需额外参数、无需关闭/重开代理

使用前必读：
1. “自动切换”能力依赖 exnetif.lua 库版本 >= 202607211200。
   旧版本库第二次调用 setproxy 只会打印“代理已存在，跳过”，不会真正切换。
   本文件启动时会打印当前库版本，低于该版本请更新 script/libs/exnetif.lua。
   建议直接使用 >= 202611121939 的版本：该版本修复了“切换失败仍返回 true”、
   “切换后掉线重连失效”、“同 SSID 改密码不切换”三个问题。
2. 本文件在每次 setproxy 后都用 netdrv.ipv4 复核真实 IP，不以返回值作为唯一
   成功依据，这样即使拿到未修复的旧库也不会误报成功。
3. 切换过程为“关 NAPT -> 清映射表 -> 断旧 WiFi -> 连新 WiFi -> 重开 NAPT”。
   下游设备 IP 不变、不需要重新 DHCP，但已建立的 TCP 连接会断开，需重连。
本文件没有对外接口，直接在main.lua中require "netif_app"就可以加载运行；
]]

local exnetif = require "exnetif"

-- ==================== 用户配置区：一般只改这里 ====================

-- 以太网口参数（Air8000 开发板板载 CH390：SPI1 / CS=GPIO12 / 中断=GPIO21）
local eth_config = {
    ethpower_en = 140,                      -- CH390 供电使能 GPIO
    tp = netdrv.CH390,                      -- 板载 CH390 以太网芯片型号
    opts = { spi = 1, cs = 12, irq = 21 },  -- SPI 通道 / 片选 / 中断引脚
}

-- 上游 WiFi A：开机先连这个
local wifi_a_config = {
    ssid = "WIFI_A_SSID",
    password = "WIFI_A_PASSWORD",
}

-- 上游 WiFi B：演示切到这一个
local wifi_b_config = {
    ssid = "WIFI_B_SSID",
    password = "WIFI_B_PASSWORD",
}

-- WiFi A 工作多久后切到 WiFi B（单位毫秒）
-- 设为 nil 则只建立 WiFi A 代理、不演示切换
local switch_interval = 30000

-- ==================== 以下为演示逻辑，通常不用修改 ====================

-- 把 WiFi 凭证组装成 setproxy 的第三个参数
local function build_proxy_opts(wifi_config)
    return {
        ethpower_en = eth_config.ethpower_en,
        tp = eth_config.tp,
        opts = eth_config.opts,
        main_adapter = {
            ssid = wifi_config.ssid,
            password = wifi_config.password,
        },
    }
end

-- 读取 WiFi 上游当前 IP，没拿到返回 nil
local function sta_ip()
    local ip = netdrv.ipv4(socket.LWIP_STA)
    if ip and ip ~= "0.0.0.0" then
        return ip
    end
    return nil
end

-- 切换失败后的兜底
-- 说明：exnetif >= 202611121939 切换失败时会恢复原凭证，由 IP_LOSE 触发自动重连
--       WiFi A；旧版本不会恢复。这里先给库 10 秒自愈时间，避免和库的重连任务
--       同时操作 wlan，超时后再手动拉一次。
local function fallback_to_wifi_a()
    log.warn("netif_app", "切换失败，先等待 exnetif 自动重连 WiFi A")
    for _ = 1, 100 do
        local ip = sta_ip()
        if ip then
            log.info("netif_app", "WiFi A 已自动恢复，IP", ip)
            return true
        end
        sys.wait(100)
    end

    log.warn("netif_app", "自动重连未生效，手动回退到 WiFi A")
    netdrv.napt(-1)
    wlan.disconnect()
    sys.wait(2000)
    wlan.connect(wifi_a_config.ssid, wifi_a_config.password, 1)
    for _ = 1, 300 do
        local ip = sta_ip()
        if ip then
            netdrv.napt(socket.LWIP_STA)
            log.info("netif_app", "手动回退成功，WiFi A 已恢复，IP", ip)
            return true
        end
        sys.wait(100)
    end
    log.error("netif_app", "回退失败，WiFi A 也连不上，请检查配置后重启设备")
    return false
end

-- 判断当前 exnetif 库是否支持“再次调用 setproxy 自动切换上游 WiFi”
-- 该能力在库版本 202607211200 才加入，更早的版本没有 version() 接口
local function lib_support_switch()
    if not exnetif.version then
        return false, "未知(库版本过旧)"
    end
    local ver = exnetif.version()
    return ver >= "202607211200", ver
end

local function netif_app_task_func()
    local can_switch, lib_ver = lib_support_switch()
    log.info("netif_app", "exnetif 库版本", lib_ver, "（切换功能需 >= 202607211200）")

    -- 第一阶段：WiFi A -> 以太网
    local res = exnetif.setproxy(socket.LWIP_ETH, socket.LWIP_STA, build_proxy_opts(wifi_a_config))
    local ip = sta_ip()
    if not res or not ip then
        log.error("第一阶段失败：以太网或 WiFi A 初始化失败")
        log.error("请检查 netif_app.lua 中 wifi_a_config 的 ssid/password，以及网线是否插好")
        return
    end
    log.info("第一阶段成功：WiFi A -> 以太网 代理已建立，WiFi IP", ip)

    if not switch_interval then
        log.info("switch_interval 为 nil，不演示切换，保持使用 WiFi A 提供网络")
        return
    end

    -- 切换前先确认库支持，否则第二次 setproxy 会被当成“重复调用”直接跳过，
    -- 看着像成功、其实还连着 WiFi A
    if not can_switch then
        log.error("netif_app", "当前 exnetif 库不支持自动切换上游 WiFi，跳过第二阶段")
        log.error("netif_app", "请把 script/libs/exnetif.lua 更新到 >= 202607211200")
        return
    end
    if wifi_a_config.ssid == wifi_b_config.ssid then
        log.error("netif_app", "wifi_a_config 与 wifi_b_config 的 ssid 相同，无法演示切换")
        return
    end

    log.info("WiFi A 将工作", switch_interval / 1000, "秒后切换到 WiFi B")
    sys.wait(switch_interval)

    -- 第二阶段：只改 WiFi 凭证，库内部检测到 ssid 变化后自动完成 NAPT/WiFi 切换
    res = exnetif.setproxy(socket.LWIP_ETH, socket.LWIP_STA, build_proxy_opts(wifi_b_config))
    -- 注意：setproxy 在切换失败时仍会返回 true，必须以实际拿到 IP 为准
    ip = sta_ip()
    if res and ip then
        log.info("第二阶段成功：WiFi B -> 以太网 代理已建立，WiFi IP", ip)
        log.info("WiFi 切换演示完成，当前使用 WiFi B 提供网络")
        return
    end

    log.error("第二阶段失败：无法切换到 WiFi B", wifi_b_config.ssid)
    log.error("请检查 netif_app.lua 中 wifi_b_config 的 ssid/password")
    log.warn("下游设备会短暂断网，正在尝试恢复 WiFi A")
    fallback_to_wifi_a()
end

sys.taskInit(netif_app_task_func)
