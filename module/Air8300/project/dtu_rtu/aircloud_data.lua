--[[
@module  aircloud_data
@summary AirCloud平台数据上报模块
@version 1.2
@date    2026.06.08
@author  黄何
@usage
本文件为AirCloud数据处理模块，负责定时通过 excloud.send 上报设备数据到 AirCloud 平台。

数据来源（事件订阅，零重复采集）：
  - 定位经纬度 → 订阅 airlbs_app 发布的 Airlbs_LOCATION_UPDATE
  - RTU传感器温湿度 → 订阅 temp_hum_sensor 发布的 TEMP_HUMIDITY_UPDATE
  - 系统数据(CPU/VBAT/CSQ/ICCID/小区ID) → 发送时实时读取（系统级API，一次调用即可）

上报字段：
  - 4G信号强度 (782, INTEGER)
  - SIM ICCID (783, ASCII)
  - RTU传感器温度 (256, FLOAT)
  - RTU传感器湿度 (257, FLOAT)
  - CPU温度 (263, INTEGER)
  - VBAT电压 (799, INTEGER)
  - GNSS经度 (512, ASCII)
  - GNSS纬度 (513, ASCII)
  本文件没有对外接口，直接在main.lua中require "aircloud_data"就可以加载运行；
]]

local excloud = require "excloud"

-- 直接解析 raw data 提取 JSON 命令
sys.subscribe("EXCLOUD_RAW_MSG", function(data)
    if #data < 21 then return end
    -- data: 16B header + 2B field_type + 2B length + NB value
    local function b2int(i) return data:byte(i)*256 + data:byte(i+1) end
    local vlen = b2int(19)
    if #data < 20 + vlen then return end
    local val = data:sub(21, 20 + vlen)
    local ok, cmd = pcall(json.decode, val)
    if not ok or type(cmd) ~= "table" or not cmd.type then return end
    log.info("aircloud", "收到命令:", val)
    local resp = {}
    if cmd.type == "read_all" then
        adc.open(adc.CH_CPU); resp.cpu_temp = adc.get(adc.CH_CPU) / 1000; adc.close(adc.CH_CPU)
        adc.open(adc.CH_VBAT); resp.vbat = adc.get(adc.CH_VBAT) / 1000; adc.close(adc.CH_VBAT)
        resp.temperature = rtu_temp or 0; resp.humidity = rtu_hum or 0
        resp.latitude = lat or ""; resp.longitude = lng or ""
        resp.csq = mobile.csq() or 0; resp.imei = mobile.imei() or ""; resp.iccid = mobile.iccid() or ""
        resp.timestamp = os.time()
    elseif cmd.type == "read_temp" then
        resp.temperature = rtu_temp or 0
    elseif cmd.type == "read_humi" then
        resp.humidity = rtu_hum or 0
    elseif cmd.type == "read_vbat" then
        adc.open(adc.CH_VBAT); resp.vbat = adc.get(adc.CH_VBAT) / 1000; adc.close(adc.CH_VBAT)
    elseif cmd.type == "read_cpu" then
        adc.open(adc.CH_CPU); resp.cpu_temp = adc.get(adc.CH_CPU) / 1000; adc.close(adc.CH_CPU)
    elseif cmd.type == "read_lat" then
        resp.latitude = lat or ""
    elseif cmd.type == "read_lng" then
        resp.longitude = lng or ""
    elseif cmd.type == "read_csq" then
        resp.csq = mobile.csq() or 0
    elseif cmd.type == "read_imei" then
        resp.imei = mobile.imei() or ""
    elseif cmd.type == "read_iccid" then
        resp.iccid = mobile.iccid() or ""
    elseif cmd.type == "read_time" then
        resp.timestamp = os.time()
    else
        resp = {error="未知命令", cmd=cmd.type or ""}
    end
    excloud.send({{field_meaning=excloud.FIELD_MEANINGS.CONTROL_RESPONSE, data_type=excloud.DATA_TYPES.ASCII, value=json.encode(resp)}}, false)
end)

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
        log.info("收到消息, seq:", data.header and data.header.sequence)
    elseif event == "disconnect" then
        log.warn("与服务器断开连接")
    elseif event == "reconnect_failed" then
        log.info("重连失败，已尝试 " .. data.count .. " 次")
    elseif event == "send_result" then
        if data.success then
            log.info("发送成功, 流水号: " .. (data.seq or "?"))
        else
            log.info("发送失败: " .. tostring(data.error_msg or "?"))
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
        sys.wait(60000)

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

        if not ok then
            log.info("发送数据失败: " .. tostring(err_msg or "?"))
        else
            log.info("数据发送成功")
        end
    end
end)
