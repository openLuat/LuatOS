--[[
@module  business_app
@summary 核心业务逻辑模块（串口 ↔ 云端 ↔ UI 三端数据编排）
@version 1.0
@date    2026.09.18
@author  嵌入式软件设计开发代理
@usage
衔接高压板（UART1）、AirCloud 云端、触摸屏三端数据流转：
- 高压板状态缓存管理（电压、工作状态、设定电压）
- 1 分钟周期上报调度（电压 799 / 工作状态 265）
- 变化即时上报策略（变更 7 方案 C）：仅**工作状态 / 设定电压**变化时立即上报一次；
  实际**电压不参与**变化触发（模拟量抖动会导致高频上报），仅随 1 分钟周期上报
- 云端控制命令执行（Type=19 嵌套 265/800 → UART 下发 → Type=20 回执回显）
- 本地触摸控制（开关机、电压调节）
- 设定电压维护（默认 3500，收到平台指令后更新并持续下发）
- 鉴权成功后上报设备信息（IMEI/ICCID）

订阅消息：
- "UART_STATUS_UPDATED"    -- 高压板状态更新 {voltage, work_status}
- "CTRL_CMD_RECV"          -- 云端控制命令 {ctrl_fields}
- "UI_TOGGLE_POWER"        -- 本地开关机 {power}
- "UI_SET_VOLTAGE"         -- 本地电压调节 {voltage}
- "AIRCLOUD_CONNECTED"     -- 云连接成功
- "AIRCLOUD_AUTHED"        -- 云鉴权成功
- "AIRCLOUD_DISCONNECTED"  -- 云连接断开 {count}

发布消息：
- "REPORT_PERIODIC"        -- 周期上报 {voltage, work_status}
- "REPORT_EVENT"           -- 事件上报 {field, value}
- "REPORT_DEVICE_INFO"     -- 设备信息上报
- "CTRL_CMD_RESULT"        -- 控制命令执行结果 {work_status, set_voltage}
- "UART_SEND_CTRL"         -- 控制帧下发 {power, set_voltage}
- "UI_UPDATE_STATUS"       -- UI 状态刷新 {voltage, work_status, set_voltage, cloud_connected, power, status_synced}
]]

local aircloud_app = require "aircloud_app"

local business_app = {}

-- 字段常量（与 protocol_app 保持一致，协议附录 A.2）
local FIELD = {
    WORK_STATUS = 265,   -- 工作状态（上/下行：上报 + Type=19 控制命令下发目标）
    SET_VOLTAGE = 800,   -- 高压板设定电压（上/下行：上报 + Type=19 控制命令下发目标，自主补充）
}

-- 设定电压范围（协议 5.3.1：0-6000）
local VOLTAGE_MIN = 0
local VOLTAGE_MAX = 6000
local DEFAULT_SET_VOLTAGE = 3500  -- 协议 7：未收到平台指令时默认发送 3500
-- 从 fskv 读取持久化的设定电压（每次开机恢复上次设定值；无记录或超范围时用默认值）
local saved_set_voltage = fskv.get("set_voltage")
if saved_set_voltage ~= nil and saved_set_voltage >= VOLTAGE_MIN and saved_set_voltage <= VOLTAGE_MAX then
    DEFAULT_SET_VOLTAGE = saved_set_voltage
    log.info("business_app", "从 fskv 恢复设定电压: " .. saved_set_voltage)
end

-- 业务状态缓存
local dev_state = {
    voltage = 0,           -- 实际输出电压（V），由状态帧 Byte1-2 映射
    work_status = 0,       -- 工作状态（1=开机中，0=关机中），由状态帧 Byte3 Bit0 映射
    set_voltage = DEFAULT_SET_VOLTAGE,  -- 设定电压（V），默认 3500
    power = 0,             -- 开关机状态（1=开机，0=关机），默认关机
    cloud_connected = false,  -- 云连接状态
    cloud_authed = false,     -- 云鉴权状态
    status_synced = false,    -- 是否已收到高压板状态同步帧（开机初始未同步，收到第一帧后置 true）
}

--[[
刷新 UI 状态（home_win 订阅 UI_UPDATE_STATUS）

@local
@function update_ui
@return nil
]]
local function update_ui()
    sys.publish("UI_UPDATE_STATUS",
        dev_state.voltage,
        dev_state.work_status,
        dev_state.set_voltage,
        dev_state.cloud_connected,
        dev_state.power,
        dev_state.status_synced)
end

-- 获取上报工作状态：未同步时上报 255（未知状态）
local function get_report_work_status()
    if dev_state.status_synced then
        return dev_state.work_status
    end
    return 255
end

--[[
周期上报任务（协议 7.5：1 分钟周期上报电压/工作状态）

@local
@function periodic_report_task
@return nil
]]
local function periodic_report_task()
    -- 等待首次鉴权成功（鉴权成功后开始 1 分钟周期计时）
    while not dev_state.cloud_authed do
        sys.wait(500)
    end
    -- 之后每 1 分钟周期上报（鉴权成功后的立即上报由 on_aircloud_authed 触发）
    while true do
        sys.wait(60000)
        -- 云鉴权成功后才上报（避免无效发送）
        if dev_state.cloud_authed then
            sys.publish("REPORT_PERIODIC", dev_state.voltage, get_report_work_status(), dev_state.set_voltage)
        end
    end
end

--[[
高压板状态更新处理（uart_app 发布 UART_STATUS_UPDATED）

@local
@function on_uart_status_updated
@param voltage number 实际输出电压（V）
@param work_status number 工作状态（1=开机中，0=关机中）
@return nil
]]
local function on_uart_status_updated(voltage, work_status)
    -- 检测工作状态变化（与缓存比较）
    -- 变化即时上报策略（变更 7，方案 C）：
    --   实际电压为持续抖动的模拟量（实测在数十伏范围内反复跳动），若按"数值不等即变化"
    --   触发即时上报，会导致上报频率飙升至 12~60 次/分钟，既浪费流量又使曲线充满毛刺。
    --   故实际电压**仅随 1 分钟周期上报**；仅工作状态（开关机）变化时立即上报一次。
    local work_status_changed = dev_state.work_status ~= work_status
    dev_state.voltage = voltage
    dev_state.work_status = work_status
    -- 已收到高压板状态同步帧（UI 从"未同步"切换为实际工作状态）
    dev_state.status_synced = true
    -- 刷新界面显示
    update_ui()
    -- 工作状态变化：立即上报一次（协议 7.5：状态变化即时上报；三字段同包）
    if work_status_changed and dev_state.cloud_authed then
        log.info("business_app", "工作状态变化立即上报: 电压=" .. tostring(voltage) .. ", 工作状态=" .. tostring(work_status))
        sys.publish("REPORT_STATUS", dev_state.voltage, get_report_work_status(), dev_state.set_voltage)
    end
end

--[[
执行云端控制命令（协议 8.5：Type=19 嵌套 265/800 → UART1 下发 → Type=20 回执回显）

@local
@function execute_ctrl_cmd
@param ctrl_fields table 控制字段表 {[265]=工作状态, [800]=设定电压}，可单个或组合下发
@return nil
]]
local function execute_ctrl_cmd(ctrl_fields)
    -- 打印控制字段
    local desc = {}
    for f, v in pairs(ctrl_fields or {}) do
        table.insert(desc, "字段" .. f .. "=" .. tostring(v))
    end
    log.info("business_app", "执行控制命令: " .. table.concat(desc, ", "))
    local has_field = false

    -- 处理 265 工作状态（协议 8.4.1：1=开机，0=关机）
    local work_status = ctrl_fields[FIELD.WORK_STATUS]
    if work_status ~= nil then
        has_field = true
        if work_status == 1 or work_status == 0 then
            dev_state.power = work_status
            log.info("business_app", "工作状态命令执行: " .. tostring(work_status))
            aircloud_app.mtn_log("ctrl", "执行工作状态命令: " .. tostring(work_status))
        else
            log.warn("business_app", "工作状态参数非法: " .. tostring(work_status))
        end
    end

    -- 处理 800 设定电压（协议 8.4.1：0~6000）
    local set_voltage = ctrl_fields[FIELD.SET_VOLTAGE]
    if set_voltage ~= nil then
        has_field = true
        if set_voltage >= VOLTAGE_MIN and set_voltage <= VOLTAGE_MAX then
            dev_state.set_voltage = set_voltage
            -- 持久化设定电压到 fskv（重启后恢复）
            fskv.set("set_voltage", dev_state.set_voltage)
            log.info("business_app", "设定电压命令执行: " .. tostring(set_voltage))
            aircloud_app.mtn_log("ctrl", "执行设定电压命令: " .. tostring(set_voltage))
        else
            log.warn("business_app", "电压参数超范围: " .. tostring(set_voltage))
        end
    end

    if has_field then
        -- 通过 UART1 下发控制指令（协议 8.5）
        sys.publish("UART_SEND_CTRL", dev_state.power, dev_state.set_voltage)
        -- 刷新 UI 显示
        update_ui()
        -- 设定电压变化：立即上报（与电压/工作状态同包，协议 7.5）
        if set_voltage ~= nil then
            sys.publish("REPORT_STATUS", dev_state.voltage, get_report_work_status(), dev_state.set_voltage)
        end
    end

    -- 发布控制回执（协议 8.4.2：Type=20 回显当前 265/800 值，由 protocol_app 构造发送）
    sys.publish("CTRL_CMD_RESULT", dev_state.work_status, dev_state.set_voltage)
end

--[[
本地开关机（home_win 触摸 UI_TOGGLE_POWER）

@local
@function on_ui_toggle_power
@param power number 开关机状态（1=开机，0=关机）
@return nil
]]
local function on_ui_toggle_power(power)
    log.info("business_app", "本地开关机: " .. tostring(power))
    dev_state.power = power
    -- 通过 UART1 下发控制指令
    sys.publish("UART_SEND_CTRL", dev_state.power, dev_state.set_voltage)
    -- 刷新 UI 显示（开关机状态变化）
    update_ui()
    aircloud_app.mtn_log("local", "本地开关机: " .. tostring(power))
end

--[[
本地电压调节（home_win 触摸 UI_SET_VOLTAGE）

@local
@function on_ui_set_voltage
@param voltage number 目标电压（0-6000）
@return nil
]]
local function on_ui_set_voltage(voltage)
    log.info("business_app", "本地电压调节: " .. tostring(voltage))
    if voltage >= VOLTAGE_MIN and voltage <= VOLTAGE_MAX then
        dev_state.set_voltage = voltage
        -- 通过 UART1 下发控制指令
        sys.publish("UART_SEND_CTRL", dev_state.power, dev_state.set_voltage)
        -- 设定电压变化：立即上报（与电压/工作状态同包，协议 7.5）
        sys.publish("REPORT_STATUS", dev_state.voltage, get_report_work_status(), dev_state.set_voltage)
        -- 刷新 UI 显示（设定电压变化）
        update_ui()
        -- 持久化设定电压到 fskv（重启后恢复）
        fskv.set("set_voltage", dev_state.set_voltage)
        aircloud_app.mtn_log("local", "本地电压调节: " .. tostring(voltage))
    else
        log.warn("business_app", "电压参数超范围: " .. tostring(voltage))
    end
end

--[[
云连接成功处理（aircloud_app 发布 AIRCLOUD_CONNECTED）

@local
@function on_aircloud_connected
@return nil
]]
local function on_aircloud_connected()
    dev_state.cloud_connected = true
    update_ui()
    log.info("business_app", "AirCloud 连接成功")
end

--[[
云鉴权成功处理（aircloud_app 发布 AIRCLOUD_AUTHED）

@local
@function on_aircloud_authed
@return nil
]]
local function on_aircloud_authed()
    dev_state.cloud_authed = true
    update_ui()
    log.info("business_app", "AirCloud 鉴权成功")
    -- 鉴权成功后立即上报一次电压/工作状态/设定电压（协议 7.5：鉴权成功后立即上报）
    sys.publish("REPORT_STATUS", dev_state.voltage, get_report_work_status(), dev_state.set_voltage)
    -- 鉴权成功后上报设备信息（协议 7.5：开机上报一次 IMEI/ICCID）
    sys.publish("REPORT_DEVICE_INFO")
end

--[[
云连接断开处理（aircloud_app 发布 AIRCLOUD_DISCONNECTED）

@local
@function on_aircloud_disconnected
@param count number 重连失败次数
@return nil
]]
local function on_aircloud_disconnected(count)
    dev_state.cloud_connected = false
    dev_state.cloud_authed = false
    update_ui()
    log.warn("business_app", "AirCloud 连接断开, 重连次数=" .. tostring(count))
end

-- 订阅消息
sys.subscribe("UART_STATUS_UPDATED", on_uart_status_updated)
sys.subscribe("CTRL_CMD_RECV", execute_ctrl_cmd)
sys.subscribe("UI_TOGGLE_POWER", on_ui_toggle_power)
sys.subscribe("UI_SET_VOLTAGE", on_ui_set_voltage)
sys.subscribe("AIRCLOUD_CONNECTED", on_aircloud_connected)
sys.subscribe("AIRCLOUD_AUTHED", on_aircloud_authed)
sys.subscribe("AIRCLOUD_DISCONNECTED", on_aircloud_disconnected)

-- 启动周期上报任务
sys.taskInit(periodic_report_task)

return business_app
