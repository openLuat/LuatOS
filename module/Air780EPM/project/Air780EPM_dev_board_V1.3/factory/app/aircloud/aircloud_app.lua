--[[
@module  aircloud_app
@summary AirCloud 云平台应用模块
@version 1.2.0
@date    2026.10.16
@usage
AirCloud excloud 协议通信，负责设备与云端的数据交互：
  - 初始化 excloud 配置并开启 TCP 连接
  - 主任务等待网络就绪，定期上报传感器数据
  - 处理云端下发的控制命令并回复

上报字段：4G 信号、设备ID(1293)、项目名(1294)、时间戳、温度、湿度、VOC、CPU 温度、LBS 经纬度
下行命令（CONTROL_COMMAND tag 19）：
  - "cycle:秒数" → 设置上报频率（最小 5 秒）
  - "led:blink" / "led:on" / "led:off" → LED 控制
回复通过 CONTROL_RESPONSE（tag 20）。

数据流向：
  sensor_app → sys.publish("read_sensor_rsp") → 本模块上报云端
  云端 → 本模块 → sys.publish("set_report_cycle") → sensor_app
  云端 → 本模块 → sys.publish("led_blink_request") → led_app
]]

local excloud = require "excloud"
local lbsLoc2 = require "lbsLoc2"

function on_excloud_event(event, data)
    log.info("aircloud", event, json.encode(data))

    if event == "connect_result" then
        if data.success then
            log.info("连接成功")
            sys.publish("aircloud_connected")
        else
            log.info("连接失败: " .. (data.error or "未知错误"))
        end
    elseif event == "auth_result" then
        if data.success then
            log.info("认证成功")
        else
            log.info("认证失败: " .. data.message)
        end
    elseif event == "message" then
        log.info("收到消息, 流水号: " .. data.header.sequence_num)
        for _, tlv in ipairs(data.tlvs) do
            log.info("TLV字段", "含义:", tlv.field, "类型:", tlv.type, "值:", tlv.value)
            if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND then
                log.info("收到控制命令: " .. tostring(tlv.value))
                local cmd = tostring(tlv.value or "")
                local resp_msg = "命令执行成功"
                local cycle_val = cmd:match("^cycle:(%d+)$")
                if cycle_val then
                    local seconds = tonumber(cycle_val)
                    if seconds and seconds >= 5 then
                        sys.publish("set_report_cycle", seconds)
                        log.info("aircloud", "下发设置上报频率: " .. seconds .. "秒")
                    else
                        resp_msg = "无效的上报频率值: " .. cycle_val
                        log.warn("aircloud", resp_msg)
                    end
                else
                    local led_cmd = cmd:match("^led:(%w+)$")
                    if led_cmd then
                        if led_cmd == "blink" then
                            sys.publish("led_blink_request")
                            log.info("aircloud", "下发LED闪烁命令")
                        elseif led_cmd == "on" then
                            sys.publish("led_set_request", 1)
                            log.info("aircloud", "下发LED常亮命令")
                        elseif led_cmd == "off" then
                            sys.publish("led_set_request", 0)
                            log.info("aircloud", "下发LED熄灭命令")
                        else
                            resp_msg = "未知的LED命令: " .. led_cmd
                            log.warn("aircloud", resp_msg)
                        end
                    else
                        resp_msg = "未知命令格式: " .. cmd
                        log.info("aircloud", resp_msg)
                    end
                end
                local ok, err_msg = excloud.send({
                    {
                        field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
                        data_type = excloud.DATA_TYPES.ASCII,
                        value = resp_msg
                    }
                }, false)
                if not ok then
                    log.info("发送控制响应失败: " .. err_msg)
                end
            end
        end
    elseif event == "disconnect" then
        log.warn("与服务器断开连接")
    elseif event == "reconnect_failed" then
        log.info("重连失败，已尝试 " .. data.count .. " 次")
    elseif event == "send_result" then
        if data.success then
            log.info("发送成功，流水号: " .. data.sequence_num)
        else
            log.info("发送失败: " .. data.error_msg)
        end
    end
end

excloud.on(on_excloud_event)

local function get_device_id()
    local id = hmeta.devid()
    if id and id ~= "" then
        return id
    end
    local mcu_id = mcu.unique_id()
    if mcu_id then
        return mcu_id
    end
    return "unknown"
end

local function get_lbs_info()
    -- lbsLoc2.request 内部会优先用 mobile.scell() 拿当前驻网基站，无需手动 reqCellInfo 扫描
    local lat, lng, t = lbsLoc2.request(5000)
    lat = tonumber(lat)
    lng = tonumber(lng)
    if lat and lng then
        log.info("lbs", string.format("lat=%.6f lng=%.6f", lat, lng))
        return lat, lng, t
    end

    log.warn("lbs", "未获取到定位信息")
    return nil, nil, nil
end

local function get_cpu_temp()
    adc.open(adc.CH_CPU)
    local raw = adc.get(adc.CH_CPU)
    adc.close(adc.CH_CPU)
    if raw and raw > 0 then
        local temp = raw / 1000
        log.info("cpu_temp", string.format("CPU温度: %.1f℃", temp))
        return temp
    end
    return nil
end

function excloud_task_func()
    while not socket.adapter(socket.dft()) do
        log.warn("excloud_task_func", "wait IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    local device_type
    if rtos.bsp() == "PC" then
        device_type = 9
    elseif rtos.bsp() ~= "Air8101" then
        device_type = 1
    else
        device_type = 2
    end

    local ok, err_msg = excloud.setup({
        use_getip = true,
        device_type = device_type,
        auth_key = PROJECT_KEY,
        transport = "tcp",
        auto_reconnect = true,
        reconnect_interval = 10,
        max_reconnect = 5,
        virtual_phone_number = "10012345678",
    })

    if not ok then
        log.error("excloud初始化失败: " .. err_msg)
        return
    end
    log.info("excloud初始化成功")

    local ok, err_msg = excloud.open()
    if not ok then
        log.error("开启excloud服务失败: " .. err_msg)
        return
    end
    log.info("excloud服务已开启")

    excloud.start_heartbeat()
    log.info("自动心跳已启动")

    local qrinfo = excloud.get_qrinfo()
    if qrinfo and qrinfo.url then
        log.info("二维码URL:", qrinfo.url)
        sys.publish("aircloud_qrinfo", qrinfo.url)
    else
        log.info("未获取到二维码信息")
    end

    while true do
        local result, temp_val, hum_val, voc_val = sys.waitUntil("read_sensor_rsp")

        local status = excloud.status()
        if not status.is_connected then
            log.warn("设备未连接，跳过数据上报")
        else
            local device_id = get_device_id()
            local cpu_temp = get_cpu_temp()
            local lat, lng = get_lbs_info()

            local tlv_list = {
                { field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G, data_type = excloud.DATA_TYPES.INTEGER, value = mobile.csq() },
                { field_meaning = 1293, data_type = excloud.DATA_TYPES.ASCII, value = device_id },
                { field_meaning = 1294, data_type = excloud.DATA_TYPES.ASCII, value = PROJECT },
                { field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP, data_type = excloud.DATA_TYPES.INTEGER, value = os.time() }
            }

            if temp_val ~= nil then
                table.insert(tlv_list, {
                    field_meaning = excloud.FIELD_MEANINGS.TEMPERATURE,
                    data_type = excloud.DATA_TYPES.FLOAT,
                    value = temp_val
                })
            end
            if hum_val ~= nil then
                table.insert(tlv_list, {
                    field_meaning = excloud.FIELD_MEANINGS.HUMIDITY,
                    data_type = excloud.DATA_TYPES.FLOAT,
                    value = hum_val
                })
            end
            if voc_val ~= nil then
                table.insert(tlv_list, {
                    field_meaning = excloud.FIELD_MEANINGS.PARTICULATE,
                    data_type = excloud.DATA_TYPES.FLOAT,
                    value = voc_val
                })
            end
            if cpu_temp ~= nil then
                table.insert(tlv_list, {
                    field_meaning = excloud.FIELD_MEANINGS.ENV_TEMPERATURE,
                    data_type = excloud.DATA_TYPES.FLOAT,
                    value = cpu_temp
                })
                log.info("aircloud", string.format("CPU温度: %.1f℃", cpu_temp))
            end
            if lat ~= nil and lng ~= nil then
                table.insert(tlv_list, {
                    field_meaning = excloud.FIELD_MEANINGS.GNSS_LATITUDE,
                    data_type = excloud.DATA_TYPES.FLOAT,
                    value = lat
                })
                table.insert(tlv_list, {
                    field_meaning = excloud.FIELD_MEANINGS.GNSS_LONGITUDE,
                    data_type = excloud.DATA_TYPES.FLOAT,
                    value = lng
                })
                log.info("aircloud", string.format("LBS: lat=%.6f lng=%.6f", lat, lng))
            end

            log.info("aircloud", "上报数据:", json.encode(tlv_list))

            local ok, err_msg = excloud.send(tlv_list, false)
            if ok then
                log.info("数据上报成功")
            else
                log.error("数据上报失败:", err_msg)
            end
        end
    end
end

sys.taskInit(excloud_task_func)
