--[[
@module  app_vl53l1x_main
@summary Air8780P VL53L1X激光测距传感器低功耗数据采集与上报主功能模块
@version 1.0
@date    2026.07.21
@author  江访
@usage
本文件为Air8780P工业模组VL53L1X激光测距传感器应用的主功能模块，核心业务逻辑为：
1、开机采集传感器数据，通过excloud和MQTT上报
2、支持libfota2远程升级
3、PSM+低功耗模式
4、双任务架构：任务1 - PSM+超时管理；任务2 - 业务逻辑

本文件没有对外接口，直接require "app_vl53l1x_main"即可加载运行
]]

-- ==================== 加载扩展库 ====================
local exs_vl53l1x = require "exs_vl53l1x"
local libfota2 = require "libfota2"
local excloud = require "excloud"

-- ==================== 可配置参数 ====================
-- 用户可根据项目需求修改以下参数
local CFG = {
    psm_sleep_min_s   = 15,     -- PSM+休眠时间(分钟)，唤醒后重新开始循环，iot平台最多10分钟请求一次
    psm_entry_max_s   = 90,     -- 开机到进入PSM+的超时上限(秒)，到时间不管任务2是否完成都强制进入PSM+
    fota_wait_max_s   = 600,    -- FOTA等待最长时间(秒)，默认10分钟，超时说明网络不好，进PSM+下次再试

    -- 传感器相关
    sensor_samples    = 3,      -- 每次唤醒后采集传感器的次数

    -- I2C引脚定义
    gpio_i2c_scl      = 1,      -- I2C SCL (GPIO1)
    gpio_i2c_sda      = 2,      -- I2C SDA (GPIO2)
    gpio_led_ctrl     = 27,     -- led: 正常状态拉高，进入PSM+前拉低

    -- MQTT配置（使用合宙测试服务器）
    mqtt_broker       = "lbsmqtt.airm2m.com",
    mqtt_port         = 1884,
}

-- ==================== 内部状态 ====================
local g_fota_running = false            -- FOTA是否正在运行
local g_fota_result = nil               -- FOTA结果: 0=成功下载
local g_fota_file = "/fota_version.txt" -- 保存版本信息用于FOTA后对比的文件

-- MQTT同步变量
local g_mqtt_publish_done = false    -- MQTT发布是否完成
local g_mqtt_publish_success = false -- MQTT发布是否成功

-- ==================== LED控制 ====================

local function led_set_high()
    gpio.setup(CFG.gpio_led_ctrl, 1)
    gpio.set(CFG.gpio_led_ctrl, 1)
    log.info("app_vl53l1x", "GPIO27 HIGH")
end

local function led_set_low()
    gpio.set(CFG.gpio_led_ctrl, 0)
    log.info("app_vl53l1x", "GPIO27 LOW")
end

-- ==================== 传感器操作 ====================

local function sensor_init()
    log.info("app_vl53l1x", "正在初始化VL53L1X传感器...")
    local ok = exs_vl53l1x.setup({
        scl = CFG.gpio_i2c_scl,
        sda = CFG.gpio_i2c_sda,
        range_mode = "standard",
    })
    if not ok then
        log.error("app_vl53l1x", "VL53L1X初始化失败")
        return false
    end
    log.info("app_vl53l1x", "VL53L1X初始化成功")
    return true
end

local function sensor_collect_data()
    log.info("app_vl53l1x", "开始采集传感器数据，采集次数=" .. CFG.sensor_samples)
    local distances = {}
    local valid_count = 0

    for i = 1, CFG.sensor_samples do
        sys.wait(500)
        local data = exs_vl53l1x.get_data()
        if data and data.status == 0 then
            distances[#distances + 1] = data.distance
            valid_count = valid_count + 1
            log.info("app_vl53l1x", string.format("采集[%d/%d] 距离=%dmm 状态=%s",
                i, CFG.sensor_samples, data.distance, data.status_str))
        else
            local status_str = (data and data.status_str) or "无数据"
            log.warn("app_vl53l1x", string.format("采集[%d/%d] 无效数据 状态=%s",
                i, CFG.sensor_samples, status_str))
        end
    end

    if valid_count == 0 then
        log.error("app_vl53l1x", "所有采集数据均无效")
        return nil
    end

    local sum = 0
    for _, d in ipairs(distances) do
        sum = sum + d
    end
    local avg_distance = math.floor(sum / #distances + 0.5)

    log.info("app_vl53l1x", string.format("采集完成: 有效%d帧, 平均距离=%dmm", valid_count, avg_distance))

    return {
        distance_list = distances,
        avg_distance = avg_distance,
        valid_count = valid_count,
    }
end

local function sensor_close()
    log.info("app_vl53l1x", "关闭VL53L1X传感器")
    exs_vl53l1x.close()
end

-- ==================== 网络等待 ====================

local function wait_network_ready(timeout_s)
    timeout_s = timeout_s or 120
    log.info("app_vl53l1x", "等待4G网络就绪，最长" .. timeout_s .. "秒...")
    for i = 1, timeout_s do
        if socket.adapter(socket.dft()) then
            log.info("app_vl53l1x", "4G网络已就绪", socket.localIP(socket.LWIP_GP))
            return true
        end
        log.warn("app_vl53l1x", "等待IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    log.warn("app_vl53l1x", "4G网络等待超时（未插卡或无信号），跳过联网操作")
    return false
end

-- ==================== excloud操作 ====================

local function on_excloud_event(event, data)
    if event == "connect_result" then
        if data.success then
            log.info("app_vl53l1x", "excloud连接成功")
        else
            log.warn("app_vl53l1x", "excloud连接失败:", data.error or "未知")
        end
    elseif event == "auth_result" then
        if data.success then
            log.info("app_vl53l1x", "excloud认证成功")
            sys.publish("EXCLOUD_READY")
        else
            log.warn("app_vl53l1x", "excloud认证失败:", data.message)
        end
    elseif event == "disconnect" then
        log.warn("app_vl53l1x", "excloud断开连接")
    elseif event == "send_result" then
        if data.success then
            log.info("app_vl53l1x", "excloud发送成功, 流水号:", data.sequence_num)
        else
            log.warn("app_vl53l1x", "excloud发送失败:", data.error_msg)
        end
    end
end

local function excloud_init()
    log.info("app_vl53l1x", "正在初始化excloud...")
    excloud.on(on_excloud_event)

    local ok, err_msg = excloud.setup({
        transport = "tcp",
        auto_reconnect = true,
        reconnect_interval = 10,
        max_reconnect = 3,
        mtn_log_enabled = false,
    })

    if not ok then
        log.error("app_vl53l1x", "excloud.setup失败:", err_msg)
        return false
    end

    ok, err_msg = excloud.open()
    if not ok then
        log.error("app_vl53l1x", "excloud.open失败:", err_msg)
        return false
    end

    excloud.start_heartbeat()
    sys.waitUntil("EXCLOUD_READY", 20000)
    return true
end

local function excloud_report_sensor(sensor_data, fota_info)
    local status = excloud.status()
    if not status or not status.is_connected then
        log.warn("app_vl53l1x", "excloud未连接，跳过数据上报")
        return false
    end

    local tlvs = {}

    if sensor_data then
        tlvs[#tlvs + 1] = {
            field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
            data_type = excloud.DATA_TYPES.UNICODE,
            value = tostring(sensor_data.avg_distance)
        }
    end

    if fota_info then
        tlvs[#tlvs + 1] = {
            field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
            data_type = excloud.DATA_TYPES.UNICODE,
            value = fota_info,
        }
    end

    if #tlvs == 0 then
        return false
    end

    local ok, err_msg = excloud.send(tlvs, false)
    if ok then
        log.info("app_vl53l1x", "excloud数据上报成功")
    else
        log.warn("app_vl53l1x", "excloud数据上报失败:", err_msg)
    end
    return ok
end

-- ==================== FOTA版本文件管理 ====================

local function fota_save_version()
    local info = VERSION .. "," .. PROJECT
    io.writeFile(g_fota_file, info)
    log.info("app_vl53l1x", "保存版本信息到文件:", info)
end

local function fota_read_version()
    local data = io.readFile(g_fota_file)
    if data and #data > 0 then
        return data
    end
    return nil
end

local function fota_check_first_boot()
    local old_info = fota_read_version()
    if not old_info then
        fota_save_version()
        return nil
    end

    local comma_pos = string.find(old_info, ",")
    if not comma_pos then
        fota_save_version()
        return nil
    end

    local old_version = string.sub(old_info, 1, comma_pos - 1)
    local old_project = string.sub(old_info, comma_pos + 1)

    if old_version ~= VERSION or old_project ~= PROJECT then
        local result_str = string.format(
            "升级前: PROJECT=%s VERSION=%s ; 升级后: PROJECT=%s VERSION=%s",
            old_project, old_version, PROJECT, VERSION
        )
        log.info("app_vl53l1x", "检测到FOTA升级后的首次启动", result_str)
        fota_save_version()
        return result_str
    else
        fota_save_version()
        return nil
    end
end

-- ==================== FOTA升级 ====================

local function fota_callback(ret)
    log.info("app_vl53l1x", "FOTA回调 ret=", ret)

    g_fota_running = false
    g_fota_result = ret

    if ret == 0 then
        log.info("app_vl53l1x", "FOTA升级包下载成功，准备重启")
    elseif ret == 1 then
        log.info("app_vl53l1x", "FOTA连接失败")
    elseif ret == 2 then
        log.info("app_vl53l1x", "FOTA URL错误")
    elseif ret == 3 then
        log.info("app_vl53l1x", "FOTA服务器断开")
    elseif ret == 4 then
        log.info("app_vl53l1x", "FOTA接收报文错误或已是最新版本")
    elseif ret == 5 then
        log.info("app_vl53l1x", "FOTA版本号格式错误")
    else
        log.info("app_vl53l1x", "FOTA未知返回码", ret)
    end

    sys.publish("FOTA_END")
end

local function fota_check_and_upgrade(sensor_data)
    log.info("app_vl53l1x", "开始检查FOTA升级...")

    fota_save_version()
    g_fota_running = true

    -- 通知任务1：FOTA正在运行，延长PSM+等待
    sys.publish("FOTA_UPGRADING")

    -- 上报"正在升级"状态到excloud平台
    local status = excloud.status()
    if status and status.is_connected then
        excloud.send({
            {
                field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
                data_type = excloud.DATA_TYPES.UNICODE,
                value = "FOTA: 正在检查/升级中"
            }
        }, false)
        log.info("app_vl53l1x", "已上报FOTA升级状态")
    end

    if sensor_data then
        log.info("app_vl53l1x", "FOTA期间同时上报传感器数据:", sensor_data.avg_distance, "mm")
    end

    local opts = {}
    libfota2.request(fota_callback, opts)

    -- 等待FOTA结果，最长CFG.fota_wait_max_s秒
    sys.waitUntil("FOTA_END", CFG.fota_wait_max_s * 1000)

    if g_fota_result == 0 then
        log.info("app_vl53l1x", "FOTA升级包已下载，重启模块")
        local fota_report = "FOTA升级包下载成功, 升级前版本: " .. VERSION
        excloud_report_sensor(nil, fota_report)
        sys.wait(1000)
        rtos.reboot()
    end

    log.info("app_vl53l1x", "FOTA检查完成(无升级或升级失败)")
end

-- ==================== MQTT操作 ====================

local function mqtt_event_callback(mqtt_client, event, data, payload, metas)
    log.info("app_vl53l1x", "MQTT事件:", event, data)

    if event == "conack" then
        log.info("app_vl53l1x", "MQTT连接成功")
        sys.publish("MQTT_CONNECT_OK", mqtt_client)
    elseif event == "sent" then
        log.info("app_vl53l1x", "MQTT数据发送成功")
        g_mqtt_publish_done = true
        g_mqtt_publish_success = true
        sys.publish("MQTT_SENT_OK")
    elseif event == "disconnect" then
        log.warn("app_vl53l1x", "MQTT断开")
        g_mqtt_publish_done = true
        sys.publish("MQTT_SENT_OK")
    elseif event == "error" then
        log.warn("app_vl53l1x", "MQTT错误:", data)
        g_mqtt_publish_done = true
        sys.publish("MQTT_SENT_OK")
    end
end

local function mqtt_report_data(topic, payload_table)
    if not topic or not payload_table then
        return false
    end

    log.info("app_vl53l1x", "MQTT上报数据到:", topic)

    g_mqtt_publish_done = false
    g_mqtt_publish_success = false

    local mqtt_client = mqtt.create(nil, CFG.mqtt_broker, CFG.mqtt_port)
    if not mqtt_client then
        log.error("app_vl53l1x", "MQTT创建失败")
        return false
    end

    mqtt_client:auth(mobile.imei() .. "_vl53l1x", "", "", false)
    mqtt_client:on(mqtt_event_callback)

    if not mqtt_client:connect() then
        log.error("app_vl53l1x", "MQTT连接失败")
        mqtt_client:close()
        return false
    end

    local no_timeout, connected_client = sys.waitUntil("MQTT_CONNECT_OK", 5000)
    if not no_timeout or not connected_client then
        log.warn("app_vl53l1x", "MQTT连接超时")
        mqtt_client:disconnect()
        sys.wait(500)
        mqtt_client:close()
        return false
    end

    local payload_json = json.encode(payload_table)
    connected_client:publish(topic, payload_json, 1, 0)
    log.info("app_vl53l1x", "MQTT已发布:", payload_json)

    sys.waitUntil("MQTT_SENT_OK", 8000)

    connected_client:disconnect()
    sys.wait(500)
    connected_client:close()

    log.info("app_vl53l1x", "MQTT短连接结束，发送", g_mqtt_publish_success and "成功" or "失败")
    return g_mqtt_publish_success
end

local function build_mqtt_payload(sensor_data, fota_info)
    local payload = {
        imei = mobile.imei(),
        project = PROJECT,
        version = VERSION,
        ts = os.time(),
    }

    if sensor_data then
        payload.distance_mm = sensor_data.avg_distance
        payload.distances = sensor_data.distance_list
        payload.valid_samples = sensor_data.valid_count
    end

    if fota_info then
        payload.fota_info = fota_info
    end

    return payload
end

-- ==================== PSM+模式 ====================

local function enter_psm_plus()
    log.info("app_vl53l1x", "准备进入PSM+模式，休眠" .. CFG.psm_sleep_min_s .. "分钟后唤醒")

    sensor_close()
    led_set_low()

    local sleep_ms = CFG.psm_sleep_min_s * 60 * 1000
    pm.dtimerStart(0, sleep_ms)
    log.info("app_vl53l1x", "深度休眠定时器已设置:", sleep_ms, "ms")

    pm.power(pm.WORK_MODE, 3)

    sys.wait(80000)
    log.info("app_vl53l1x", "进入PSM+失败，强制重启")
    rtos.reboot()
end

-- ==================== 任务1：PSM+超时管理 ====================
--
-- 职责：到设定时间就进入PSM+，期间等待FOTA消息
--       收到FOTA_UPGRADING就等待FOTA结果（最长fota_wait_max_s秒）
--       FOTA成功→重启，FOTA超时/失败→进PSM+
--       未收到FOTA消息→到时间直接进PSM+
--
local function psm_timer_task_func()
    log.info("app_vl53l1x", "任务1(PSM+超时管理)启动，最大等待" .. CFG.psm_entry_max_s .. "秒")

    -- 等待 FOTA_UPGRADING 消息，超时 psm_entry_max_s 秒
    local no_timeout = sys.waitUntil("FOTA_UPGRADING", CFG.psm_entry_max_s * 1000)

    if no_timeout then
        -- 收到FOTA消息，等待FOTA结果，最长 fota_wait_max_s 秒
        log.info("app_vl53l1x", "任务1: 收到FOTA_UPGRADING，等待FOTA结果，最长" .. CFG.fota_wait_max_s .. "秒")
        no_timeout = sys.waitUntil("FOTA_END", CFG.fota_wait_max_s * 1000)

        if no_timeout and g_fota_result == 0 then
            -- FOTA升级成功，通知任务2不再上报，直接重启
            log.info("app_vl53l1x", "任务1: FOTA升级成功")
            -- fota_callback 内部已处理 reboot
            return
        end

        if no_timeout then
            log.info("app_vl53l1x", "任务1: FOTA无新版本或失败，进入PSM+")
        else
            log.warn("app_vl53l1x", "任务1: FOTA超时，网络不好，进入PSM+下次再试")
        end
    else
        log.info("app_vl53l1x", "任务1: 未收到FOTA消息，到时间进入PSM+")
    end

    -- 进入PSM+
    enter_psm_plus()

    log.error("app_vl53l1x", "任务1: PSM+入口异常退出")
end

-- ==================== 任务2：业务逻辑 ====================
--
-- 职责：传感器采集、数据上报，完成后进入PSM+
--
local function vl53l1x_main_task_func()
    log.info("app_vl53l1x", "========== Air8780P VL53L1X 主任务启动 ==========")
    log.info("app_vl53l1x", string.format("配置: psm_entry_max=%ds psm_sleep=%dmin fota_wait_max=%ds samples=%d",
        CFG.psm_entry_max_s, CFG.psm_sleep_min_s, CFG.fota_wait_max_s, CFG.sensor_samples))

    -- 第一步：GPIO27拉高(正常工作状态)
    led_set_high()

    -- 第二步：检查是否是FOTA升级后的首次启动
    local fota_first_boot_info = fota_check_first_boot()
    if fota_first_boot_info then
        log.info("app_vl53l1x", "FOTA升级后首次启动:", fota_first_boot_info)
    end

    -- 第三步：初始化传感器
    local sensor_ok = sensor_init()

    -- 第四步：采集传感器数据
    local sensor_data = nil
    if sensor_ok then
        sensor_data = sensor_collect_data()
        if sensor_data then
            log.info("app_vl53l1x", string.format("测距结果 = %d mm (有效%d帧, 原始数据=%s)",
                sensor_data.avg_distance, sensor_data.valid_count, table.concat(sensor_data.distance_list, ",")))
        else
            log.warn("app_vl53l1x", "测距结果 = 无效 (所有帧均未测到目标)")
        end
        sensor_close()
    end

    -- 第五步：等待4G网络就绪（超时后跳过联网操作）
    local net_ok = wait_network_ready()

    if net_ok then
        -- 第六步：初始化excloud连接
        excloud_init()

        -- 第七步：上报数据
        local mqtt_topic = mobile.imei() .. "/vl53l1x/up"
        local mqtt_payload

        if fota_first_boot_info then
            local fota_msg = "FOTA升级成功: " .. fota_first_boot_info
            excloud_report_sensor(sensor_data, fota_msg)
            mqtt_payload = build_mqtt_payload(sensor_data, fota_msg)
            -- 上报完成后删除版本文件，避免下次重启再次上报
            os.remove(g_fota_file)
        else
            excloud_report_sensor(sensor_data, nil)
            mqtt_payload = build_mqtt_payload(sensor_data, nil)
        end
        mqtt_report_data(mqtt_topic, mqtt_payload)

        -- 第八步：检查FOTA升级(非FOTA后首次启动才检查)
        if not fota_first_boot_info then
            fota_check_and_upgrade(sensor_data)
        end
    else
        -- 无网络，跳过上报和FOTA，直接进入PSM+
        if fota_first_boot_info then
            os.remove(g_fota_file)
        end
        log.info("app_vl53l1x", "无网络，跳过上报和FOTA检查")
    end

    -- 任务2完成，进入PSM+
    log.info("app_vl53l1x", "任务2: 发送完成，进入PSM+模式")
    enter_psm_plus()

    log.error("app_vl53l1x", "任务2: PSM+入口异常退出!")
end

-- ==================== 启动双任务 ====================
-- 任务1：PSM+超时管理（先启动，开始计时）
sys.taskInit(psm_timer_task_func)
-- 任务2：业务逻辑
sys.taskInit(vl53l1x_main_task_func)
