--[[
@module  config
@summary 系统配置模块
@version 1.0
@date    2026.10.16
@author  王城钧
@usage
本模块提供系统配置参数，包括服务器地址、端口、超时时间等。
各业务模块通过 require "config" 后调用 config.get(key) / config.set(key, value) 读写配置。
]]

local config = {}

-- 服务器配置
config.server = {
    host = "api.luatos.com",
    port = 443,
    api_path = "/iot/smart_locker",
    timeout = 5000, -- 服务器请求超时时间(ms)
    retry_count = 3, -- 服务器请求重试次数
    retry_interval = 2000 -- 服务器请求重试间隔(ms)
}

-- 柜子配置
config.locker = {
    total_boxes = 7, -- 总箱子数量（7路控制板）
    available_boxes = 7, -- 可用箱子数量
    used_boxes = 0, -- 已使用箱子数量
    box_types = {"小", "中", "大"}, -- 箱子类型
    box_sizes = {
        small = {width = 30, height = 40, depth = 40},
        medium = {width = 40, height = 50, depth = 50},
        large = {width = 50, height = 60, depth = 60}
    }
}

-- 串口配置
config.serial = {
    uartid = 1, -- 串口号（485 串口用 uart1，uart3 留给 airlink 4G）
    baudrate = 9600, -- 波特率
    data_bits = 8, -- 数据位
    stop_bits = 1, -- 停止位
    parity = 0, -- 校验位 0:无校验, 1:奇校验, 2:偶校验
    flow_control = 0, -- 流控 0:无流控
    timeout = 2000 -- 超时时间(ms)
}

-- 485总线配置
config.rs485 = {
    pin = 8, -- 485使能引脚
    active_high = true -- 高电平有效
}

-- 网络配置
config.network = {
    connect_timeout = 10000, -- 网络连接超时(ms)
    reconnect_interval = 5000, -- 重连间隔(ms)
    max_reconnects = 10 -- 最大重连次数
}

-- 系统配置
config.system = {
    log_level = 2, -- 日志级别 0:debug, 1:info, 2:warn, 3:error
    time_zone = 8, -- 时区 +8:00
    heartbeat_interval = 30000, -- 心跳间隔(ms)
    status_check_interval = 60000 -- 状态检查间隔(ms)
}

-- 存取件配置
config.business = {
    deposit_timeout = 60000, -- 存件超时时间(ms)
    pickup_timeout = 60000, -- 取件超时时间(ms)
    verify_timeout = 30000, -- 验证超时时间(ms)
    max_boxes_per_user = 1, -- 每个用户最多使用箱子数量
    storage_time_limit = 86400, -- 最大存储时间(s) - 24小时
    warning_time = 3600, -- 超时警告时间(s) - 1小时
    overtime_fee = 0.5 -- 超时费用(元/小时)
}

-- AirCloud配置
config.aircloud = {
    enabled = true, -- 是否启用AirCloud功能
    auto_reconnect = true, -- 自动重连
    reconnect_interval = 10, -- 重连间隔(秒)
    max_reconnects = 5 -- 最大重连次数
}

-- 函数：获取配置值（key 用点号分隔，如 "server.host"）
function config.get(key, default)
    local value = config
    for k in string.gmatch(key, "[^%.]+") do
        if type(value) == "table" then
            value = value[k]
        else
            value = nil
            break
        end
    end
    return value or default
end

-- 函数：设置配置值（key 用点号分隔，如 "server.host"）
function config.set(key, value)
    local tbl = config
    local keys = {}
    for k in string.gmatch(key, "[^%.]+") do
        table.insert(keys, k)
    end

    for i = 1, #keys - 1 do
        local k = keys[i]
        if not tbl[k] or type(tbl[k]) ~= "table" then
            tbl[k] = {}
        end
        tbl = tbl[k]
    end

    tbl[keys[#keys]] = value
end

-- 初始化配置
function config.init()
    log.info("config", "配置模块初始化")

    -- 如果没有配置文件，使用默认值
    -- 可以添加读取配置文件的逻辑
end

-- 导出配置模块
return config
