--[[
@module  tcp_modbus_master
@summary 以太网温湿度变送器 Modbus TCP 主站采集模块
@version 1.0
@date    2026.09.24
@usage
本功能模块演示的内容为：
1、将设备配置为 Modbus TCP 主站，通过指定网卡读取以太网温湿度变送器
   （建大仁科 RS-WS-ETH-6：IP 192.168.1.100，端口 500，从站地址 1，保持寄存器）的数据
2、每 5 秒读取一次，解析后通过 sys.publish 广播，供 rtu_slave_regmap（寄存器映射表）、
   httpsrv_web（Web 页面）、aircloud_data（AirCloud 上报）等模块订阅使用
3、原 RS485（UART1）温湿度采集已取消，UART1 隔离485 让位给 485 继电器模块（relay_ctrl），
   温湿度数据改由本模块通过 Modbus TCP 采集

网络绑定说明（重要）：
  现场温湿度变送器接在路由器上，设备通过 WiFi(STA) 连接同一路由器访问它，
  因此默认绑定 NET_ADAPTER = socket.LWIP_STA；
  若变送器改为直连设备网口1，把 NET_ADAPTER 改为 socket.LWIP_ETH 即可。
  TCP 主站会等绑定网卡真正拿到 IP 后才创建，避免绑定到未就绪的网卡。

寄存器说明（保持寄存器，功能码 0x03）：
  0x0000  当前湿度  INT16  x10  （例：501 → 50.1%RH）
  0x0001  当前温度  INT16  x10  （例：253 → 25.3℃，负值已处理）

本文件没有对外接口，直接在 main.lua 中 require "tcp_modbus_master" 即可加载运行；

本文件的对外接口有两个（均通过消息广播）：
1、sys.publish("TCP_TEMP_HUMIDITY_UPDATE", temperature, humidity)
    temperature: 温度值（浮点数℃，如 25.3）
    humidity:    湿度值（浮点数%RH，如 60.5）
2、sys.publish("TCP_TEMP_HUMIDITY_ERROR", status)
    读取失败时广播，供 Web 页面显示温湿度链路状态（status 为 exmodbus 状态码）
]]

local exmodbus = require("exmodbus")

-- ==================== 可配置参数（现场调试只需改这里） ====================
-- 绑定网卡：现场温湿度变送器接在路由器上，设备通过 WiFi(STA) 连接同一路由器访问它；
-- 若变送器改为直连设备网口1，请把下一行改为 socket.LWIP_ETH
local NET_ADAPTER = socket.LWIP_STA
local TARGET_IP = "192.168.1.100"   -- 以太网温湿度变送器 IP 地址
local TARGET_PORT = 500             -- 以太网温湿度变送器端口
local READ_INTERVAL = 5000          -- 采集周期(ms)
-- ======================================================================

-- 创建 TCP 主站配置参数
local CREATE_CONFIG = {
    mode = exmodbus.TCP_MASTER,      -- 通信模式：TCP 主站
    adapter = NET_ADAPTER,           -- 绑定网卡：必须选能到达变送器的那张网卡
    ip_address = TARGET_IP,          -- 以太网温湿度变送器 IP 地址
    port = TARGET_PORT,              -- 以太网温湿度变送器端口
}

-- 读取温湿度寄存器的参数
local READ_CONFIG = {
    slave_id = 1,                         -- 从站地址
    reg_type = exmodbus.HOLDING_REGISTER, -- 寄存器类型：保持寄存器
    start_addr = 0x0000,                  -- 起始地址：湿度
    reg_count = 0x0002,                   -- 读取 2 个寄存器：湿度 + 温度
    timeout = 1000,                       -- 超时时间 1000ms
}

-- 温湿度缓存（零重复采集：本模块是温湿度的唯一数据源）
local sensor_data = {
    temperature = 0,
    humidity = 0,
}

local tcp_master = nil   -- TCP 主站实例（延迟到绑定网卡拿到 IP 后再创建）
local fail_count = 0     -- 连续读取失败次数（用于诊断提示）

-- 网卡名称（仅用于日志显示，便于现场确认绑定了哪张网卡）
local function adapter_name(adapter)
    if adapter == socket.LWIP_STA then
        return "WiFi(STA)"
    elseif adapter == socket.LWIP_ETH then
        return "网口1(ETH)"
    elseif adapter == socket.LWIP_USER1 then
        return "网口2"
    elseif adapter == socket.LWIP_AP then
        return "WiFi(AP)"
    else
        return "默认网卡(4G)"
    end
end

-- 等待绑定网卡真正拿到 IP
-- 注意：socket.adapter() 只表示网卡已注册，未拿到 IP 时也会返回真值；
--       这里用 socket.localIP() 判断，避免 TCP 主站绑定到尚无 IP 的网卡
local function wait_adapter_ready()
    local tip_shown = false
    while true do
        local ip = socket.localIP(NET_ADAPTER)
        if ip and ip ~= "0.0.0.0" then
            log.info("tcp_modbus_master", "绑定网卡就绪:", adapter_name(NET_ADAPTER), ip)
            return
        end
        if not tip_shown then
            log.info("tcp_modbus_master", "等待绑定网卡就绪...", adapter_name(NET_ADAPTER))
            tip_shown = true
        end
        sys.wait(1000)
    end
end

-- 读取一次温湿度数据并广播
local function read_temp_humidity()
    if not tcp_master then
        return
    end
    local result = tcp_master:read(READ_CONFIG)

    if result and result.status == exmodbus.STATUS_SUCCESS then
        local humi_raw = result.data[READ_CONFIG.start_addr] or 0
        local temp_raw = result.data[READ_CONFIG.start_addr + 1] or 0
        -- INT16 负值处理（环境温度可能为负）
        if temp_raw > 0x7FFF then
            temp_raw = temp_raw - 0x10000
        end
        sensor_data.humidity = humi_raw / 10.0
        sensor_data.temperature = temp_raw / 10.0
        fail_count = 0

        log.info("tcp_modbus_master", "读取成功, 温度:", string.format("%.1f", sensor_data.temperature) .. "℃",
            "湿度:", string.format("%.1f", sensor_data.humidity) .. "%RH")
        sys.publish("TCP_TEMP_HUMIDITY_UPDATE", sensor_data.temperature, sensor_data.humidity)
        -- 网络业务正常，喂网络看门狗
        sys.publish("FEED_NETWORK_WATCHDOG")
    else
        local status = result and result.status or "nil"
        fail_count = fail_count + 1
        log.warn("tcp_modbus_master", "读取失败, 状态:", status,
            "绑定网卡:", adapter_name(NET_ADAPTER), socket.localIP(NET_ADAPTER),
            "目标:", TARGET_IP .. ":" .. TARGET_PORT)
        if fail_count == 3 then
            log.warn("tcp_modbus_master",
                "连续失败3次，请依次检查: 1)变送器是否上电、是否与绑定网卡在同一网络 " ..
                "2)IP/端口是否正确 3)端口是否为502 4)变送器是否工作在TCP Server模式 " ..
                "5)是否存在多网卡同网段(建议网口2/WiFi改到其他网段)")
        end
        sys.publish("TCP_TEMP_HUMIDITY_ERROR", status)
    end
end

-- 定时任务：等待网卡就绪 → 创建 TCP 主站 → 周期读取温湿度数据
local function tcp_master_task()
    -- 等待绑定网卡真正拿到 IP 后再创建主站，避免 socket 绑定到错误/未就绪的网卡
    wait_adapter_ready()

    tcp_master = exmodbus.create(CREATE_CONFIG)
    if not tcp_master then
        log.error("tcp_modbus_master", "TCP 主站创建失败, 网卡:", adapter_name(NET_ADAPTER))
        return
    end
    log.info("tcp_modbus_master", "TCP 主站创建成功, 网卡:", adapter_name(NET_ADAPTER),
        "目标:", TARGET_IP .. ":" .. TARGET_PORT)

    sys.wait(1000)
    while true do
        read_temp_humidity()
        sys.wait(READ_INTERVAL)
    end
end

sys.taskInit(tcp_master_task)

log.info("tcp_modbus_master", "TCP 温湿度采集模块加载完成")
