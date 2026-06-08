--[[
@module  aircloud_data
@summary AirCloud平台数据上报模块
@version 1.1
@date    2026.05.21
@author  黄何
@usage
本文件为AirCloud数据处理模块，负责定时通过 excloud.send 上报设备数据到 AirCloud 平台。

数据来源（事件订阅，零重复采集）：
  - 定位经纬度 → 订阅 airlbs_app 发布的 Airlbs_LOCATION_UPDATE
  - RTU传感器温湿度 → 订阅 temp_hum_sensor 发布的 TEMP_HUMIDITY_UPDATE
  - TCP传感器温湿度 → 订阅 tcp_modbus_master 发布的 TCP_TEMP_HUMIDITY_UPDATE
  - 基站频段 → 订阅 CELL_INFO_UPDATE
  - 系统数据(CPU/VBAT/CSQ/ICCID/小区ID) → 发送时实时读取（系统级API，一次调用即可）

上报字段：
  - 4G信号强度 (782, INTEGER)
  - SIM ICCID (783, ASCII)
  - 驻留频段 (772, INTEGER)
  - 驻留小区 (773, INTEGER)
  - RTU传感器温度 (256, FLOAT)
  - RTU传感器湿度 (257, FLOAT)
  - CPU温度 (263, INTEGER)
  - VBAT电压 (799, INTEGER)
  - GNSS经度 (512, ASCII)
  - GNSS纬度 (513, ASCII)
  - TCP传感器温度 (256, FLOAT, 自定义)
  - TCP传感器湿度 (257, FLOAT, 自定义)
  本文件没有对外接口，直接在main.lua中require "aircloud_data"就可以加载运行；
]]

local excloud = require "excloud"

-- AirCloud 服务器配置（请填入实际值）
local AIRcloud_CONFIG = {
    host = "124.71.128.165",
    port = 9108,
    auth_key = "47J0PYMJzOCXwjXQ0bpqhXkoq9KMgDgi",
}

-- 经纬度
local lat, lng = nil, nil
sys.subscribe("Airlbs_LOCATION_UPDATE", function(new_lat, new_lng)
    lat = new_lat
    lng = new_lng
end)

-- RTU 传感器温湿度
local rtu_temp, rtu_hum = nil, nil
sys.subscribe("TEMP_HUMIDITY_UPDATE", function(temp, humi)
    rtu_temp = temp
    rtu_hum = humi
end)

-- TCP Modbus 传感器温湿度
local tcp_temp, tcp_hum = nil, nil
sys.subscribe("TCP_TEMP_HUMIDITY_UPDATE", function(temp, humi)
    tcp_temp = temp
    tcp_hum = humi
end)



excloud.on(function(event, data)
    log.info("用户回调函数", event, json.encode(data))

    if event == "connect_result" then
        if data.success then
            log.info("连接成功")
        else
            log.info("连接失败: " .. (data.error or "未知错误"))
        end
    elseif event == "auth_result" then
        if data.success then
            log.info("认证成功")
        else
            log.info("认证失败: " .. (data.message or "?"))
        end
    elseif event == "message" then
        log.info("收到消息, 流水号: " .. (data.header and data.header.seq or "?"))
        for _, tlv in ipairs(data.tlvs or {}) do
            if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND then
                log.info("收到控制命令: " .. tostring(tlv.value))
                local ok, err_msg = excloud.send({
                    {
                        field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
                        data_type = excloud.DATA_TYPES.ASCII,
                        value = "命令执行成功"
                    }
                }, false)
                if not ok then
                    log.info("发送控制响应失败: " .. (err_msg or "?"))
                end
            end
        end
    elseif event == "disconnect" then
        log.warn("与服务器断开连接")
    elseif event == "reconnect_failed" then
        log.info("重连失败，已尝试 " .. data.count .. " 次")
    elseif event == "send_result" then
        if data.success then
            log.info("发送成功, 流水号: " .. (data.seq or "?"))
        else
            log.info("发送失败: " .. (data.error_msg or "?"))
        end
    end
end)


sys.taskInit(function()
    -- 等待IP就绪
    while not socket.adapter(socket.dft()) do
        log.warn("aircloud_data", "wait IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    sys.wait(1000)

    -- 配置 excloud
    local ok, err = excloud.setup({
        device_type = 1,
        host = AIRcloud_CONFIG.host,
        port = AIRcloud_CONFIG.port,
        auth_key = AIRcloud_CONFIG.auth_key,
        transport = "tcp",
        auto_reconnect = true,
        reconnect_interval = 10,
        max_reconnect = 5,
        timeout = 30,
    })
    if not ok then log.info("初始化失败: " .. (err or "?")); return end
    log.info("excloud初始化成功")

    ok, err = excloud.open()
    if not ok then log.info("开启excloud服务失败: " .. (err or "?")); return end
    log.info("excloud服务已开启")

    -- 定时上报
    while true do
        sys.wait(30000)

        -- 系统数据：发送时实时读取（系统API，不会重复采集传感器）
        local rssi = mobile.csq() or 0
        local iccid = mobile.iccid() or ""

        adc.open(adc.CH_CPU)
        local cpu_temp = adc.get(adc.CH_CPU) or 0
        adc.close(adc.CH_CPU)

        adc.open(adc.CH_VBAT)
        local vbat = adc.get(adc.CH_VBAT) or 3300
        adc.close(adc.CH_VBAT)

        -- 异步数据：空值兜底
        local _lat = lat or 0
        local _lng = lng or 0
        local _rtu_temp = rtu_temp or 0
        local _rtu_hum = rtu_hum or 0
        local _tcp_temp = tcp_temp or 0
        local _tcp_hum = tcp_hum or 0

        local ok, err_msg = excloud.send({
            { field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G,  data_type = excloud.DATA_TYPES.INTEGER, value = rssi },
            { field_meaning = excloud.FIELD_MEANINGS.SIM_ICCID,           data_type = excloud.DATA_TYPES.ASCII,   value = iccid },
            { field_meaning = excloud.FIELD_MEANINGS.TEMPERATURE,         data_type = excloud.DATA_TYPES.FLOAT,   value = _rtu_temp },
            { field_meaning = excloud.FIELD_MEANINGS.HUMIDITY,            data_type = excloud.DATA_TYPES.FLOAT,   value = _rtu_hum },
            { field_meaning = excloud.FIELD_MEANINGS.ENV_TEMPERATURE,     data_type = excloud.DATA_TYPES.INTEGER, value = cpu_temp },
            { field_meaning = excloud.FIELD_MEANINGS.VOLTAGE,             data_type = excloud.DATA_TYPES.INTEGER, value = vbat },
            { field_meaning = excloud.FIELD_MEANINGS.GNSS_LONGITUDE,      data_type = excloud.DATA_TYPES.ASCII,   value = _lng },
            { field_meaning = excloud.FIELD_MEANINGS.GNSS_LATITUDE,       data_type = excloud.DATA_TYPES.ASCII,   value = _lat },
        }, false)

        -- 每包数据内只有一个温湿度，故此处二次发送
        local yes,not_ok = excloud.send({
            { field_meaning = excloud.FIELD_MEANINGS.TEMPERATURE, data_type = excloud.DATA_TYPES.FLOAT, value = _tcp_temp },
            { field_meaning = excloud.FIELD_MEANINGS.HUMIDITY, data_type = excloud.DATA_TYPES.FLOAT, value = _tcp_hum },
        }, false)

        if not ok then
            log.info("发送数据失败: " .. (err_msg or "?"))
        else
            log.info("数据发送成功")
        end
        
        if not yes then
            log.info("发送数据失败: " .. (not_ok or "?"))
        else
            log.info("数据发送成功")
        end
    end
end)
