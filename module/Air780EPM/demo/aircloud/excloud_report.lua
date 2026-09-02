--[[
@module  excloud_report
@summary 业务数据上报模块
@version 1.0.0
@date    2026.08.29
@author  LuatOS 嵌入式软件设计开发
@usage
本模块负责把设备侧的业务数据（温度/湿度/信号强度/状态等）按 TLV 格式上报到云平台。

核心接口：
1. M.send_one(field_meaning, data_type, value) —— 封装一次 TLV 字段的上报，供外部复用
2. M.trigger_report(type) —— 一次性触发上报（由控制命令 "trigger_report" 调用）
3. 周期上报任务 —— 等待“鉴权成功”事件后，每隔 report_cycle 秒自动上报一次

演示的数据类型（DATA_TYPES）：
   INTEGER      —— 整数（4 字节大端）
   FLOAT        —— 浮点数（*1000 整数编码）
   BOOLEAN      —— 布尔（1 字节 0/1）
   ASCII        —— ASCII 字符串
   UNICODE      —— Unicode 字符串
   BINARY       —— 二进制数据
结合不同的 FIELD_MEANINGS 字段含义，展示如何构造合法的 TLV 报文。

注：本示例中的传感器数据均为【模拟数据】，真实项目中可替换为实际的传感器采集值。
]]

-- 依赖库
local excloud = require("excloud")

-- 配置
local config = require("config")

-- 本模块对外导出的表
local M = {}

-- 日志辅助
local log_tag = config.log_tag
local function log_info(...) log.info(log_tag, ...) end
local function log_warn(...) log.warn(log_tag, ...) end

-- 是否已成功鉴权的标志（用于周期上报任务判断）
local authed = false

-- =========================================================================
-- 上报单条 TLV 字段
-- @param field_meaning 字段含义（见 config.FIELD_MEANINGS）
-- @param data_type     数据类型（见 config.DATA_TYPES）
-- @param value         数值
-- @return ok, err
-- =========================================================================
function M.send_one(field_meaning, data_type, value)
    local ok, err = excloud.send({
        {
            field_meaning = field_meaning,
            data_type = data_type,
            value = value,
        }
    }, false)
    if not ok then
        log_warn("上报单字段失败", "字段:", field_meaning, "错误:", err)
    end
    return ok, err
end

-- =========================================================================
-- 批量上报：把多段 TLV 一次性发出去
-- @param tlvs 形如 { {field_meaning=, data_type=, value=}, ... }
-- @return ok, err
-- =========================================================================
function M.send_multi(tlvs)
    local ok, err = excloud.send(tlvs, false)
    if not ok then
        log_warn("批量上报失败", "错误:", err)
    end
    return ok, err
end

-- =========================================================================
-- 模拟采集环境温度（摄氏度）
-- =========================================================================
local function read_temperature()
    -- 【模拟】真实项目使用 temp/hum 等传感器库读取
    return 26.5
end

-- =========================================================================
-- 模拟采集相对湿度（%）
-- =========================================================================
local function read_humidity()
    -- 【模拟】
    return 60.0
end

-- =========================================================================
-- 模拟获取 4G 信号强度（单元格信号 CSQ，0~31）
-- =========================================================================
local function read_signal_csq()
    -- 【模拟】真实项目使用 net.getSignal() / mobile 相关接口读取
    return 23
end

-- =========================================================================
-- 模拟读取设备电池电压（mV）
-- =========================================================================
local function read_voltage_mv()
    -- 【模拟】
    return 3700
end

-- =========================================================================
-- 模拟获取设备开机原因（枚举值，1=上电 2=复位 等）
-- =========================================================================
local function read_boot_reason()
    return 1
end

-- =========================================================================
-- 上报“环境传感器 + 设备状态”综合数据
-- 一次性把多段 TLV 组成一条消息发送，减少网络往返。
-- =========================================================================
local function report_environment()
    -- 温度：浮点数，使用 FLOAT 类型（库内部以 *1000 整数编码）
    -- 湿度：浮点数
    -- 4G 信号强度：整数
    -- 电池电压：整数（mV）
    -- 开机原因：整数
    local tlvs = {
        {
            field_meaning = config.FIELD_MEANINGS.TEMPERATURE,
            data_type = config.DATA_TYPES.FLOAT,
            value = read_temperature(),
        },
        {
            field_meaning = config.FIELD_MEANINGS.HUMIDITY,
            data_type = config.DATA_TYPES.FLOAT,
            value = read_humidity(),
        },
        {
            field_meaning = config.FIELD_MEANINGS.SIGNAL_STRENGTH_4G,
            data_type = config.DATA_TYPES.INTEGER,
            value = read_signal_csq(),
        },
        {
            field_meaning = config.FIELD_MEANINGS.BATTERY_LEVEL,
            data_type = config.DATA_TYPES.INTEGER,
            value = read_voltage_mv(),
        },
        {
            field_meaning = config.FIELD_MEANINGS.BOOT_REASON,
            data_type = config.DATA_TYPES.INTEGER,
            value = read_boot_reason(),
        },
    }
    return M.send_multi(tlvs)
end

-- =========================================================================
-- 上报“设备状态信息”综合数据（字符串、布尔类演示）
-- =========================================================================
local function report_device_status()
    -- 工作状态：整数
    -- 设备号(IMEI)：ASCII 字符串
    -- 是否在线：布尔（演示）
    local tlvs = {
        {
            field_meaning = config.FIELD_MEANINGS.WORK_STATUS,
            data_type = config.DATA_TYPES.INTEGER,
            value = 1, -- 1=在线
        },
        {
            field_meaning = config.FIELD_MEANINGS.DEVICE_ID,
            data_type = config.DATA_TYPES.ASCII,
            value = "860000000000001", -- 模拟 IMEI（真实项目用 mobile.imei()）
        },
        {
            field_meaning = config.FIELD_MEANINGS.HEARTBEAT_COUNT,
            data_type = config.DATA_TYPES.INTEGER,
            value = 100, -- 模拟心跳计数
        },
    }
    return M.send_multi(tlvs)
end

-- =========================================================================
-- 一次性触发上报（供控制命令 "trigger_report" 调用）
-- @param report_type "environment" | "status" | "all"
-- =========================================================================
function M.trigger_report(report_type)
    log_info("触发一次性上报，类型:", report_type)
    if report_type == "environment" then
        return report_environment()
    elseif report_type == "status" then
        return report_device_status()
    else
        -- 默认上报两类
        local ok1 = report_environment()
        local ok2 = report_device_status()
        return (ok1 and ok2), "触发上报"
    end
end

-- =========================================================================
-- 周期上报任务：等待鉴权成功事件后，每隔 report_cycle 秒上报一次
-- =========================================================================
local function period_report_task()
    log_info("周期上报任务启动，等待鉴权成功...")

    -- 等待云平台鉴权成功事件
    -- 若鉴权一直未到达，则每 1 秒轮询一次 authed 标志
    while not authed do
        sys.wait(1000)
    end

    log_info("已鉴权成功，开始周期上报，周期:", config.report_cycle, "秒")

    -- 周期循环上报
    while true do
        report_environment()
        sys.wait(config.report_cycle * 1000)
    end
end

-- 启动周期上报协程
sys.taskInit(period_report_task)

-- 订阅云平台“鉴权成功”事件（由 excloud_main 在 auth_result 成功后 publish）
-- 注册一次即可，收到消息后置位 authed 标志，唤醒上面的周期上报任务
sys.subscribe("excloud_authed", function() authed = true end)

-- 导出本模块
return M
