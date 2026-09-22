--[[
@module  sim_mock
@summary PC 模拟器数据模拟模块（仅模拟器加载，真机不启用）
@version 1.0
@date    2026.09.21
@author  嵌入式软件设计开发代理
@usage
本模块用于在 **LuatOS-PC 模拟器**上模拟真实业务数据，使界面呈现"可正常工作的状态"，
便于在 PC 上做 UI / 业务联调（模拟器无高压板、无 WiFi 射频、无有效 AirCloud 设备凭证）。

模拟内容：
1、高压板状态帧：订阅 UART_SEND_CTRL 拿到"设定电压/开关机"，
   按真机协议周期（1000ms）发布 UART_STATUS_UPDATED（实际输出电压 + 工作状态），
   并叠加小幅抖动以模拟真实采样波动 → 待机界面"实际输出电压 / 工作状态"正常显示；
2、WiFi：模拟"WiFi 已开启 + 已扫描到热点列表 + 已连接其中一个"，
   完整响应 wifi_win 的各类请求消息 → WiFi 设置页面有热点列表且显示已连接；
3、云端：模拟上报"云端已连接"（AIRCLOUD_CONNECTED），
   并在收到 AIRCLOUD_DISCONNECTED 时立即重新置为已连接 → 待机界面"云端：已连接"。

订阅消息（全部为真机各模块已定义的接口，本模块仅扮演"数据源"）：
- "UART_SEND_CTRL"        -- 控制帧下发（business_app 发布）→ 更新模拟高压板状态
- "AIRCLOUD_DISCONNECTED" -- 云端断开（aircloud_app 发布）→ 重新置为已连接
- "WIFI_SCAN_REQ"         -- 发起扫描请求
- "WIFI_CONNECT_REQ"      -- 连接热点请求 {ssid, password}
- "WIFI_DISCONNECT_REQ"   -- 断开热点请求
- "WIFI_FORGET_REQ"       -- 忘记热点请求 {ssid}
- "WIFI_GET_SAVED_REQ"    -- 查询已保存热点列表
- "WIFI_GET_STATE_REQ"    -- 查询 WiFi 开关状态
- "WIFI_GET_STATUS_REQ"   -- 查询网络总状态
- "WIFI_ENABLE_REQ"       -- 打开 WiFi
- "WIFI_DISABLE_REQ"      -- 关闭 WiFi

发布消息：
- "UART_STATUS_UPDATED"   -- 模拟高压板状态 {voltage, work_status}
- "WIFI_SCAN_RESULT"      -- 模拟扫描结果 {list: [{ssid, rssi, bssid}]}
- "WIFI_SAVED_RSP"        -- 模拟已保存热点列表 {list: [{ssid, password}]}
- "WIFI_CONNECTED"        -- 模拟 WiFi 连接成功 {ssid}
- "WIFI_DISCONNECTED"     -- 模拟 WiFi 断开 {reason}
- "WIFI_STATE_RSP"        -- 模拟 WiFi 开关状态 {enabled}
- "NET_STATUS"            -- 模拟网络总状态（更新标题栏 WiFi 图标）
- "AIRCLOUD_CONNECTED"    -- 模拟云端已连接

说明：本模块所有接口均为"发布真机已有消息"，**未修改任何业务模块逻辑**；
      真机（rtos.bsp() ~= "PC"）上本模块直接返回，不做任何事。
]]

-- 仅在 PC 模拟器上启用（真机加载本模块时直接退出，零影响）
if rtos.bsp() ~= "PC" then
    log.info("sim_mock", "非 PC 模拟器环境，模拟数据模块不启用")
    return
end

-- ==================== 配置项（按需调整）====================
local ENABLE_UART_MOCK  = true    -- 模拟高压板状态上报（实际输出电压 / 工作状态）
local ENABLE_WIFI_MOCK  = true    -- 模拟 WiFi 扫描 / 连接（热点列表 + 已连接热点）
local ENABLE_CLOUD_MOCK = true    -- 模拟云端已连接（界面显示"云端：已连接"）
local AUTO_POWER_ON     = true    -- 启动后自动模拟一次"开机"，使界面进入自洽的正常工作状态

-- 模拟高压板参数
local HV_REPORT_INTERVAL = 1000   -- 状态帧上报周期（ms，与真机协议 1000ms 一致）
local HV_VOLTAGE_JITTER  = 8      -- 实际输出电压抖动幅度（±V），模拟真实采样波动；设 0 则恒定

-- 模拟扫描到的 WiFi 热点列表
local MOCK_AP_LIST = {
    {ssid = "AIR8301_TEST",  rssi = -52, bssid = "A1B2C3D4E501"},
    {ssid = "Office_2.4G",   rssi = -67, bssid = "A1B2C3D4E502"},
    {ssid = "LuatOS-Demo",   rssi = -78, bssid = "A1B2C3D4E503"},
    {ssid = "ChinaNet-5G",   rssi = -85, bssid = "A1B2C3D4E504"},
}

-- 默认"已保存并已连接"的热点
local DEFAULT_AP = {ssid = "AIR8301_TEST", password = "12345678"}

-- ==================== 模拟状态缓存 ====================
local hv_power = 0                -- 模拟的高压板开关机状态（1=开机，0=关机）
local hv_set_voltage = 3500       -- 模拟的设定电压（V），由 UART_SEND_CTRL 更新
local wifi_enabled = true         -- 模拟的 WiFi 开关状态
local saved_list = {              -- 模拟的已保存热点列表（最多 3 个，最新在前）
    {ssid = DEFAULT_AP.ssid, password = DEFAULT_AP.password}
}
local connected_ssid = nil        -- 当前连接的 SSID（nil=未连接）
local connected_rssi = nil        -- 当前连接热点的信号强度（dBm）

--[[
发布网络总状态 NET_STATUS（更新标题栏 WiFi 图标 / WiFi 页面连接状态）

@local
@function publish_net_status
@return nil
]]
local function publish_net_status()
    sys.publish("NET_STATUS",
        connected_ssid ~= nil,   -- wifi_connected
        connected_ssid,          -- wifi_ssid
        connected_rssi,          -- wifi_rssi（dBm）
        false,                   -- g4_connected（模拟器无 4G）
        socket.LWIP_STA)         -- current_adapter（语义上表示 WiFi 网卡）
end

--[[
从模拟热点列表中查找指定 SSID 的热点

@local
@function find_ap
@param ssid string 热点名称
@return table|nil 热点信息 {ssid, rssi, bssid}
]]
local function find_ap(ssid)
    for _, ap in ipairs(MOCK_AP_LIST) do
        if ap.ssid == ssid then
            return ap
        end
    end
    return nil
end

--[[
保存热点到模拟的已保存列表（去重、最新在前、最多 3 个，与真机策略一致）

@local
@function save_ap
@param ssid string 热点名称
@param password string 热点密码
@return nil
]]
local function save_ap(ssid, password)
    local new_list = {
        {ssid = ssid, password = password or ""}
    }
    for _, item in ipairs(saved_list) do
        if item.ssid ~= ssid then
            table.insert(new_list, item)
        end
    end
    while #new_list > 3 do
        table.remove(new_list)
    end
    saved_list = new_list
end

--[[
模拟连接指定热点：发布 WIFI_CONNECTED 与 NET_STATUS

@local
@function mock_connect
@param ssid string 热点名称
@return nil
]]
local function mock_connect(ssid)
    connected_ssid = ssid
    local ap = find_ap(ssid)
    connected_rssi = ap and ap.rssi or -60
    log.info("sim_mock", "模拟 WiFi 已连接:", tostring(connected_ssid), "信号:", tostring(connected_rssi), "dBm")
    sys.publish("WIFI_CONNECTED", connected_ssid)
    publish_net_status()
end

--[[
模拟断开热点：发布 WIFI_DISCONNECTED 与 NET_STATUS

@local
@function mock_disconnect
@param reason string 断开原因
@return nil
]]
local function mock_disconnect(reason)
    log.info("sim_mock", "模拟 WiFi 断开:", tostring(reason))
    connected_ssid = nil
    connected_rssi = nil
    publish_net_status()
    sys.publish("WIFI_DISCONNECTED", reason or "user_disconnect")
end

-- ==================== 各请求消息处理 ====================

--[[ 扫描请求：回复模拟热点列表（wifi_win 发布 WIFI_SCAN_REQ）]]
local function on_scan_req()
    log.info("sim_mock", "收到扫描请求，回复模拟热点列表，共", #MOCK_AP_LIST, "个")
    sys.publish("WIFI_SCAN_RESULT", MOCK_AP_LIST)
end

--[[ 连接请求：连接指定热点（wifi_win 发布 WIFI_CONNECT_REQ）]]
local function on_connect_req(ssid, password)
    log.info("sim_mock", "收到连接请求:", tostring(ssid))
    local target = ssid or DEFAULT_AP.ssid
    save_ap(target, password)
    mock_connect(target)
end

--[[ 断开请求（wifi_win 发布 WIFI_DISCONNECT_REQ）]]
local function on_disconnect_req()
    mock_disconnect("user_disconnect")
end

--[[ 忘记热点请求（wifi_win 发布 WIFI_FORGET_REQ）]]
local function on_forget_req(ssid)
    log.info("sim_mock", "收到忘记网络请求:", tostring(ssid))
    local new_list = {}
    for _, item in ipairs(saved_list) do
        if item.ssid ~= ssid then
            table.insert(new_list, item)
        end
    end
    saved_list = new_list
    sys.publish("WIFI_SAVED_RSP", saved_list)
    -- 若忘记的是当前连接热点，则断开
    if connected_ssid == ssid then
        mock_disconnect("forgot")
    end
end

--[[ 查询已保存列表（wifi_win 发布 WIFI_GET_SAVED_REQ）]]
local function on_get_saved_req()
    sys.publish("WIFI_SAVED_RSP", saved_list)
end

--[[ 查询 WiFi 开关状态（wifi_win 发布 WIFI_GET_STATE_REQ）]]
local function on_get_state_req()
    sys.publish("WIFI_STATE_RSP", wifi_enabled)
end

--[[ 查询网络总状态（wifi_win 发布 WIFI_GET_STATUS_REQ）]]
local function on_get_status_req()
    publish_net_status()
end

--[[ 打开 WiFi（wifi_win 发布 WIFI_ENABLE_REQ）]]
local function on_enable_req()
    log.info("sim_mock", "收到打开 WiFi 请求")
    wifi_enabled = true
    sys.publish("WIFI_STATE_RSP", true)
    sys.publish("WIFI_SCAN_RESULT", MOCK_AP_LIST)
    -- 打开后自动连接默认热点
    mock_connect(DEFAULT_AP.ssid)
end

--[[ 关闭 WiFi（wifi_win 发布 WIFI_DISABLE_REQ）]]
local function on_disable_req()
    log.info("sim_mock", "收到关闭 WiFi 请求")
    wifi_enabled = false
    sys.publish("WIFI_STATE_RSP", false)
    sys.publish("WIFI_SCAN_RESULT", {})
    mock_disconnect("wifi_disabled")
end

--[[ 控制帧下发（business_app 发布 UART_SEND_CTRL）：更新模拟高压板状态]]
local function on_uart_send_ctrl(power, set_voltage)
    if power ~= nil then
        hv_power = power
    end
    if set_voltage ~= nil then
        hv_set_voltage = set_voltage
    end
    log.info("sim_mock", "模拟高压板更新: 开关机=" .. tostring(hv_power) .. ", 设定电压=" .. tostring(hv_set_voltage))
end

--[[ 云端断开（aircloud_app 发布）：模拟器无有效云端设备凭证，收到后立即重新置为已连接]]
local function on_aircloud_disconnected()
    if ENABLE_CLOUD_MOCK then
        sys.publish("AIRCLOUD_CONNECTED")
    end
end

--[[
模拟主任务：延迟启动 → 置位初始状态（云端/WiFi/开机）→ 周期模拟高压板状态帧与 WiFi 信号

@local
@function sim_task
@return nil
]]
local function sim_task()
    -- 等待各业务模块订阅关系就绪
    sys.wait(1000)

    -- 1. 模拟云端已连接（界面"云端：已连接"）
    if ENABLE_CLOUD_MOCK then
        sys.publish("AIRCLOUD_CONNECTED")
        log.info("sim_mock", "模拟云端已连接")
    end

    -- 2. 模拟 WiFi 已开启并连接默认热点（标题栏 WiFi 图标 + WiFi 页面）
    if ENABLE_WIFI_MOCK then
        wifi_enabled = true
        sys.publish("WIFI_STATE_RSP", true)
        mock_connect(DEFAULT_AP.ssid)
    end

    -- 3. 模拟一次"开机"操作：使 按钮/工作状态/实际电压 三者自洽（正常工作状态）
    if AUTO_POWER_ON then
        sys.publish("UI_TOGGLE_POWER", 1)
        log.info("sim_mock", "模拟开机操作（UI_TOGGLE_POWER=1）")
    end

    -- 4. 周期模拟：高压板状态帧 + WiFi 信号强度刷新
    while true do
        if ENABLE_UART_MOCK then
            local voltage = 0
            if hv_power == 1 then
                voltage = hv_set_voltage + math.random(-HV_VOLTAGE_JITTER, HV_VOLTAGE_JITTER)
                if voltage < 0 then
                    voltage = 0
                end
            end
            sys.publish("UART_STATUS_UPDATED", voltage, hv_power)
        end
        if ENABLE_WIFI_MOCK and connected_ssid then
            -- 小幅刷新 RSSI，让标题栏信号格有变化（模拟真实波动）
            local base = find_ap(connected_ssid)
            local base_rssi = base and base.rssi or -60
            connected_rssi = base_rssi + math.random(-4, 4)
            publish_net_status()
        end
        sys.wait(HV_REPORT_INTERVAL)
    end
end

-- ==================== 订阅与启动 ====================
if ENABLE_UART_MOCK then
    sys.subscribe("UART_SEND_CTRL", on_uart_send_ctrl)
end
if ENABLE_CLOUD_MOCK then
    sys.subscribe("AIRCLOUD_DISCONNECTED", on_aircloud_disconnected)
end
if ENABLE_WIFI_MOCK then
    sys.subscribe("WIFI_SCAN_REQ", on_scan_req)
    sys.subscribe("WIFI_CONNECT_REQ", on_connect_req)
    sys.subscribe("WIFI_DISCONNECT_REQ", on_disconnect_req)
    sys.subscribe("WIFI_FORGET_REQ", on_forget_req)
    sys.subscribe("WIFI_GET_SAVED_REQ", on_get_saved_req)
    sys.subscribe("WIFI_GET_STATE_REQ", on_get_state_req)
    sys.subscribe("WIFI_GET_STATUS_REQ", on_get_status_req)
    sys.subscribe("WIFI_ENABLE_REQ", on_enable_req)
    sys.subscribe("WIFI_DISABLE_REQ", on_disable_req)
end

log.info("sim_mock", "PC 模拟器数据模拟已启用（高压板/WiFi/云端）")
sys.taskInit(sim_task)
