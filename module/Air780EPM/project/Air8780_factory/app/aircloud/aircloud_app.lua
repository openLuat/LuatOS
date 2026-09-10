--[[
@module  aircloud_app
@summary AirCloud 云平台应用模块
@version 1.1.0
@date    2026.09.10
@author  江访
@usage
AirCloud excloud 协议通信模块，负责设备与云端的数据交互。

核心功能：
- 初始化excloud配置并开启TCP连接
- 注册回调函数处理云平台事件（连接、认证、消息、断开）
- 主任务循环等待网络就绪，定期上报传感器数据
- 处理服务器下发的控制命令并回复

上报数据字段：
- SIGNAL_STRENGTH_4G: 4G信号强度（CSQ）
- SIM_ICCID: 设备ID（hmeta.devid()）
- TIMESTAMP: 时间戳（os.time()）
- TEMPERATURE: 温度（SHT30传感器）
- HUMIDITY: 湿度（SHT30传感器）
- PARTICULATE: VOC空气质量（AGS02MA传感器）
- ENV_TEMPERATURE: CPU温度（ADC读取）
- GNSS_LATITUDE: 纬度（LBS基站定位）
- GNSS_LONGITUDE: 经度（LBS基站定位）

下行命令（tag 1281）：
- "cycle:秒数" → 设置上报频率（最小5秒）
- "led:blink" → LED闪烁5秒
- "led:on" → LED常亮
- "led:off" → LED熄灭

数据流向：
- sensor_app → sys.publish("read_sht30_voc_rsp") → 本模块上报云端
- 云端 → 本模块 → sys.publish("set_report_cycle") → sensor_app
- 云端 → 本模块 → sys.publish("led_blink_request") → led_app
]]
-- 导入excloud库
local excloud = require "excloud"
-- 导入lbsLoc2基站定位库（免费单基站定位）
local lbsLoc2 = require "lbsLoc2"

--[[
用户回调函数，处理excloud所有事件

@local
@function on_excloud_event
@param event string 事件类型
@param data table 事件数据
@return nil
]]
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
                local ok, err_msg = excloud.send({
                    {
                        field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
                        data_type = excloud.DATA_TYPES.UNICODE,
                        value = "命令执行成功"
                    }
                }, false)
                if not ok then
                    log.info("发送控制响应失败: " .. err_msg)
                end
            elseif tlv.field == 1281 then
                -- 自定义下行命令（tag 1281），格式: "cycle:秒数" 或 "led:blink/on/off"
                local cmd = tostring(tlv.value or "")
                local cycle_val = cmd:match("^cycle:(%d+)$")
                if cycle_val then
                    local seconds = tonumber(cycle_val)
                    if seconds and seconds >= 5 then
                        sys.publish("set_report_cycle", seconds)
                        log.info("aircloud", "下发设置上报频率: " .. seconds .. "秒")
                    else
                        log.warn("aircloud", "无效的上报频率值: " .. cycle_val)
                    end
                else
                    -- LED控制命令
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
                            log.warn("aircloud", "未知的LED命令: " .. led_cmd)
                        end
                    else
                        log.info("aircloud", "收到自定义下行: " .. cmd)
                    end
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

-- 注册回调
excloud.on(on_excloud_event)

--[[
获取设备标识（使用 hmeta.devid() 替代 IMEI/MAC）

@local
@function get_device_id
@return string 设备ID字符串
]]
local function get_device_id()
    local id = hmeta.devid()
    if id and id ~= "" then
        return id
    end
    -- fallback：使用模块号
    local mcu_id = mcu.unique_id()
    if mcu_id then
        return mcu_id
    end
    return "unknown"
end

--[[
获取LBS基站经纬度信息

@local
@function get_lbs_info
@return number|nil 纬度（latitude），失败返回nil
@return number|nil 经度（longitude），失败返回nil
@return table|nil  基站信息（含 lac, cid, rssi 等）
]]
local function get_lbs_info()
    -- 使用 lbsLoc2 免费单基站定位获取经纬度
    -- 步骤1：请求基站扫描
    mobile.reqCellInfo(15)
    -- 步骤2：等待基站信息更新
    local result = sys.waitUntil("CELL_INFO_UPDATE", 3000)
    if not result then
        log.warn("lbs", "基站信息扫描超时")
        return nil, nil, nil
    end

    -- 步骤3：打印当前服务小区信息
    local cell = mobile.scell()
    if cell then
        log.info("lbs", "mcc=" .. tostring(cell.mcc), "mnc=" .. tostring(cell.mnc),
                 "tac=" .. tostring(cell.tac), "eci=" .. tostring(cell.eci))
    end

    -- 步骤4：调用 lbsLoc2 获取经纬度（同步接口，超时5秒）
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

--[[
获取CPU温度

@local
@function get_cpu_temp
@return number|nil CPU温度（摄氏度），失败返回nil
]]
local function get_cpu_temp()
    -- 读取CPU内部温度，单位0.001摄氏度
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

--[[
主任务函数，负责网络等待、excloud初始化、开启服务和数据上报

@local
@function excloud_task_func
@return nil
]]
function excloud_task_func()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
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

    -- 配置excloud参数
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

    -- 开启excloud服务
    local ok, err_msg = excloud.open()
    if not ok then
        log.error("开启excloud服务失败: " .. err_msg)
        return
    end
    log.info("excloud服务已开启")

    -- 启动自动心跳，默认5分钟一次
    excloud.start_heartbeat()
    log.info("自动心跳已启动")

    -- 获取并打印二维码信息
    local qrinfo = excloud.get_qrinfo()
    if qrinfo and qrinfo.url then
        log.info("二维码URL:", qrinfo.url)
        sys.publish("aircloud_qrinfo", qrinfo.url)
    else
        log.info("未获取到二维码信息")
    end

    -- 主循环：定期上报数据
    while true do
        local result, temp_val, hum_val, voc_val = sys.waitUntil("read_sht30_voc_rsp")

        -- 检查连接状态
        local status = excloud.status()
        if not status.is_connected then
            log.warn("设备未连接，跳过数据上报")
        else
            -- 获取附加数据
            local device_id = get_device_id()
            local cpu_temp = get_cpu_temp()
            local lat, lng = get_lbs_info()

            -- 构建TLV列表
            local tlv_list = {
                -- 信号强度
                { field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G, data_type = excloud.DATA_TYPES.INTEGER, value = mobile.csq() },
                -- 设备ID（hmeta.devid() 替代 IMEI/MAC）
                { field_meaning = excloud.FIELD_MEANINGS.SIM_ICCID,         data_type = excloud.DATA_TYPES.ASCII,   value = device_id },
                -- 时间戳
                { field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,         data_type = excloud.DATA_TYPES.INTEGER, value = os.time() }
            }

            -- 温湿度（传感器）
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

            -- VOC（空气质量）
            if voc_val ~= nil then
                table.insert(tlv_list, {
                    field_meaning = excloud.FIELD_MEANINGS.PARTICULATE,
                    data_type = excloud.DATA_TYPES.FLOAT,
                    value = voc_val
                })
            end

            -- CPU温度
            if cpu_temp ~= nil then
                table.insert(tlv_list, {
                    field_meaning = excloud.FIELD_MEANINGS.ENV_TEMPERATURE,
                    data_type = excloud.DATA_TYPES.FLOAT,
                    value = cpu_temp
                })
                log.info("aircloud", string.format("CPU温度: %.1f℃", cpu_temp))
            end

            -- LBS经纬度
            if lat ~= nil and lng ~= nil then
                -- 纬度
                table.insert(tlv_list, {
                    field_meaning = excloud.FIELD_MEANINGS.GNSS_LATITUDE,
                    data_type = excloud.DATA_TYPES.FLOAT,
                    value = lat
                })
                -- 经度
                table.insert(tlv_list, {
                    field_meaning = excloud.FIELD_MEANINGS.GNSS_LONGITUDE,
                    data_type = excloud.DATA_TYPES.FLOAT,
                    value = lng
                })
                log.info("aircloud", string.format("LBS: lat=%.6f lng=%.6f", lat, lng))
            end

            -- 打印完整TLV列表
            log.info("aircloud", "上报数据:", json.encode(tlv_list))

            -- 发送数据
            local ok, err_msg = excloud.send(tlv_list, false)
            if ok then
                log.info("数据上报成功")
            else
                log.error("数据上报失败:", err_msg)
            end
        end
    end
end

-- 启动主任务
sys.taskInit(excloud_task_func)
