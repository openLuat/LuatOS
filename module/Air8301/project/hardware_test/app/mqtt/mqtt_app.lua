--[[
@module  mqtt_app
@summary MQTT客户端主模块
@version 1.0
@date    2026.09.04
@author  江访
@usage
本模块为MQTT客户端主模块，负责：
- MQTT连接管理（连接、断开、自动重连）
- 从device_config.json读取配置
- 定时上报设备状态（DI/DO/SHT30/网络等）
- 事件驱动上报（DI/DO状态变化即时推送）
- 订阅云端指令（command/config topic）
- 与UI层通过发布/订阅机制通信
]]

local mqtt_app = {}

-- 模块名称标识
local TASK_NAME = "mqtt_app_main"

-- MQTT状态查询/响应消息
local MQTT_CMD_GET_STATUS = "mqtt_cmd_get_status"
local MQTT_STATUS_RSP = "mqtt_status_rsp"

-- MQTT配置变量（由外部传入）
local mqtt_config = nil

-- MQTT连接状态
local mqtt_connected = false
local mqtt_reconnect_interval = 5000

-- 定时上报相关
local upload_timer = nil
local UPLOAD_TOPIC_PREFIX = "device/"
local UPLOAD_TOPIC_SUFFIX = "/upload"

-- 运行时间
local g_runtime_sec = 0

-- 加载mqtt_sender和mqtt_receiver模块
local mqtt_sender = require "mqtt_sender"
local mqtt_receiver = require "mqtt_receiver"

--[[
@function get_client_id
@summary 获取MQTT客户端ID（默认用IMEI）
@return string 客户端ID
]]
local function get_client_id()
    if not mqtt_config or not mqtt_config.cid or mqtt_config.cid == "" or mqtt_config.cid == "IMEI" then
        if mobile and mobile.imei then
            return mobile.imei()
        end
        return "air8301_unknown"
    end
    return mqtt_config.cid
end

--[[
@function do_upload
@summary 执行一次数据上报（DI/DO/SHT30/网络状态等）
@return nil
]]
local function do_upload()
    local client_id = get_client_id()
    local topic = UPLOAD_TOPIC_PREFIX .. client_id .. UPLOAD_TOPIC_SUFFIX

    -- 收集 DI 状态
    local di1, di2 = gpio.get(16), gpio.get(17)
    -- 收集 DO 状态
    local do1, do2 = gpio.get(24), gpio.get(25)
    -- 网络类型
    local net_type = socket.dft() or 2
    -- 信号强度
    local rssi = 0
    if mobile and mobile.rssi then
        rssi = mobile.rssi() or 0
    end

    local upload_data = {
        di = {di1 and 1 or 0, di2 and 1 or 0},
        ["do"] = {do1 and 1 or 0, do2 and 1 or 0},
        net = net_type,
        rssi = rssi,
        run = g_runtime_sec,
    }

    log.info(TASK_NAME, "upload", topic, json.encode(upload_data))
    sys.publish("SEND_DATA_REQ", TASK_NAME, topic, json.encode(upload_data), mqtt_config.qos or 1)
end

--[[
@function start_upload_timer
@summary 启动定时上报
@return nil
]]
local function start_upload_timer()
    if upload_timer then
        sys.timerStop(upload_timer)
        upload_timer = nil
    end
    local interval_sec = mqtt_config.upload_interval or 60
    do_upload()
    upload_timer = sys.timerLoopStart(do_upload, interval_sec * 1000)
    log.info(TASK_NAME, "upload timer started", interval_sec, "sec")
end

--[[
@function publish_status
@summary 发布MQTT状态到UI层
@param connected boolean 连接状态
@return nil
]]
local function publish_status(connected)
    sys.publish(MQTT_STATUS_RSP, {
        connected = connected,
        broker = mqtt_config.broker,
        port = mqtt_config.port,
        client_id = get_client_id(),
        keep = mqtt_config.keep,
        qos = mqtt_config.qos,
        tls = mqtt_config.tls
    })
end

--[[
@function publish_response
@summary 发布指令响应到云平台
@param cmd string 指令名称
@param seq number 序列号
@param result number 结果码（0成功，非0失败）
@param msg string 描述信息
@return nil
]]
local function publish_response(cmd, seq, result, msg)
    local topic = "device/" .. get_client_id() .. "/response"
    local payload = json.encode({
        cmd = cmd,
        seq = seq,
        result = result,
        msg = msg or ""
    })
    log.info(TASK_NAME, "publish_response", cmd, seq, result, msg)
    sys.publish("SEND_DATA_REQ", TASK_NAME, topic, payload, mqtt_config.qos or 1)
end

--[[
@function mqtt_client_event_cbfunc
@summary MQTT事件回调函数
@return nil
]]
local function mqtt_client_event_cbfunc(mqtt_client, event, data, payload, metas)
    log.info("mqtt_event", event, data, payload)

    if event == "conack" then
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "CONNECT", true)
        mqtt_connected = true
        publish_status(true)

        local client_id = get_client_id()
        local sub_topics = {
            ["device/" .. client_id .. "/command"] = mqtt_config.qos or 1,
            ["device/" .. client_id .. "/config"] = mqtt_config.qos or 1
        }
        log.info(TASK_NAME, "subscribe topics:", json.encode(sub_topics))
        if not mqtt_client:subscribe(sub_topics) then
            log.error(TASK_NAME, "subscribe command/config failed")
        end

        mqtt_client:publish("device/" .. client_id .. "/status", "online", 1)
        start_upload_timer()

    elseif event == "suback" then
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "SUBSCRIBE", data, payload)

    elseif event == "unsuback" then
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "UNSUBSCRIBE", true)

    elseif event == "recv" then
        mqtt_receiver.proc(data, payload, metas)

    elseif event == "sent" then
        sys.sendMsg(mqtt_sender.TASK_NAME, "MQTT_EVENT", "PUBLISH_OK")

    elseif event == "disconnect" then
        sys.sendMsg(TASK_NAME, "MQTT_EVENT", "DISCONNECTED", false)
        mqtt_connected = false
        log.warn(TASK_NAME, "mqtt disconnected")
        publish_status(false)
        sys.publish("ALARM_TRIGGER", {
            type = "mqtt",
            message = "MQTT连接断开",
            level = "error"
        })

    elseif event == "pong" then
        log.info(TASK_NAME, "pong received")

    elseif event == "error" then
        mqtt_connected = false
        if data == "connect" or data == "conack" then
            log.error(TASK_NAME, "mqtt connect error", data, payload)
            sys.sendMsg(TASK_NAME, "MQTT_EVENT", "CONNECT", false)
            sys.publish("ALARM_TRIGGER", {
                type = "mqtt",
                message = "MQTT连接错误",
                level = "error"
            })
        elseif data == "other" or data == "tx" then
            log.error(TASK_NAME, "mqtt error", data)
            sys.sendMsg(TASK_NAME, "MQTT_EVENT", "ERROR")
            sys.publish("ALARM_TRIGGER", {
                type = "mqtt",
                message = "MQTT异常",
                level = "error"
            })
        end
        publish_status(false)
    end
end

--[[
@function mqtt_client_task
@summary MQTT客户端主任务（连接/重连循环）
@return nil
]]
local function mqtt_client_task()
    local mqtt_client
    local result
    local client_id
    while true do
        while not socket.adapter(socket.dft()) do
            log.warn(TASK_NAME, "wait IP_READY", socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end
        log.info(TASK_NAME, "IP_READY received", socket.dft())

        sys.cleanMsg(TASK_NAME)

        if not mqtt_config.broker or mqtt_config.broker == "" then
            log.warn(TASK_NAME, "mqtt broker not configured")
            sys.wait(5000)
            goto RECONNECT
        end

        mqtt_client = mqtt.create(nil, mqtt_config.broker, mqtt_config.port)
        if not mqtt_client then
            log.error(TASK_NAME, "mqtt.create error")
            goto RECONNECT
        end

        client_id = get_client_id()
        result = mqtt_client:auth(client_id, mqtt_config.username, mqtt_config.password, true)
        if not result then
            log.error(TASK_NAME, "mqtt_client:auth error")
            goto RECONNECT
        end

        mqtt_client:on(mqtt_client_event_cbfunc)
        mqtt_client:keepalive(mqtt_config.keep)
        mqtt_client:will("device/" .. client_id .. "/status", "offline")

        result = mqtt_client:connect()
        if not result then
            log.error(TASK_NAME, "mqtt_client:connect error")
            goto RECONNECT
        end

        while true do
            local msg = sys.waitMsg(TASK_NAME, "MQTT_EVENT")
            if not msg then break end
            log.info(TASK_NAME, "waitMsg", msg[2], msg[3], msg[4])

            if msg[2] == "CONNECT" then
                if msg[3] then
                    log.info(TASK_NAME, "connect success")
                    sys.sendMsg(mqtt_sender.TASK_NAME, "MQTT_EVENT", "CONNECT_OK", mqtt_client)
                else
                    log.info(TASK_NAME, "connect error")
                    break
                end
            elseif msg[2] == "SUBSCRIBE" then
                if msg[3] then
                    log.info(TASK_NAME, "subscribe success")
                else
                    log.error(TASK_NAME, "subscribe error", msg[4])
                    mqtt_client:disconnect()
                    sys.wait(1000)
                    break
                end
            elseif msg[2] == "UNSUBSCRIBE" then
                log.info(TASK_NAME, "unsubscribe success")
            elseif msg[2] == "CLOSE" then
                mqtt_client:disconnect()
                sys.wait(1000)
                break
            elseif msg[2] == "DISCONNECTED" then
                break
            elseif msg[2] == "ERROR" then
                break
            end
        end

        ::RECONNECT::
        sys.cleanMsg(TASK_NAME)
        sys.sendMsg(mqtt_sender.TASK_NAME, "MQTT_EVENT", "DISCONNECTED")
        sys.sendMsg(mqtt_sender.TASK_NAME, "MQTT_EVENT", "MOVE_TO_HIST")

        mqtt_connected = false
        publish_status(false)
        if mqtt_client then
            mqtt_client:close()
            mqtt_client = nil
        end
        sys.wait(mqtt_reconnect_interval)
    end
end

--[[
@function mqtt_config_changed
@summary 检查MQTT配置是否有变化
@param new_mqtt table 新配置
@return boolean 是否有变化
]]
local function mqtt_config_changed(new_mqtt)
    if not new_mqtt then return false end
    if new_mqtt.broker ~= nil and mqtt_config.broker ~= new_mqtt.broker then return true end
    if new_mqtt.port ~= nil and mqtt_config.port ~= new_mqtt.port then return true end
    if new_mqtt.cid ~= nil and mqtt_config.cid ~= new_mqtt.cid then return true end
    if new_mqtt.username ~= nil and mqtt_config.username ~= new_mqtt.username then return true end
    if new_mqtt.password ~= nil and mqtt_config.password ~= new_mqtt.password then return true end
    if new_mqtt.keep ~= nil and mqtt_config.keep ~= new_mqtt.keep then return true end
    if new_mqtt.qos ~= nil and mqtt_config.qos ~= new_mqtt.qos then return true end
    if new_mqtt.tls ~= nil and mqtt_config.tls ~= new_mqtt.tls then return true end
    return false
end

--[[
@function subscribe_events
@summary 订阅事件
@return nil
]]
local function subscribe_events()
    -- MQTT状态查询
    sys.subscribe(MQTT_CMD_GET_STATUS, function()
        log.info(TASK_NAME, MQTT_CMD_GET_STATUS .. " received")
        publish_status(mqtt_connected)
    end)

    -- 配置热切换
    sys.subscribe("CONFIG_UPDATED", function(new_config)
        if new_config.mqtt and mqtt_config_changed(new_config.mqtt) then
            for k, v in pairs(new_config.mqtt) do
                mqtt_config[k] = v
            end
            sys.sendMsg(TASK_NAME, "MQTT_EVENT", "CLOSE")
            log.info(TASK_NAME, "mqtt config changed, will reconnect")
        end
    end)

    -- 运行时间更新
    sys.subscribe("monitor_runtime_update", function(data)
        g_runtime_sec = data.runtime_sec
    end)

    -- 云端指令：重启
    sys.subscribe("CMD_REBOOT", function(seq)
        log.info(TASK_NAME, "CMD_REBOOT received, seq:", seq)
        publish_response("reboot", seq, 0, "rebooting")
        sys.timerStart(rtos.reboot, 3000)
    end)

    -- 云端指令：恢复出厂
    sys.subscribe("CMD_FACTORY_RESET", function(seq)
        log.info(TASK_NAME, "CMD_FACTORY_RESET received, seq:", seq)
        local ok = pcall(function()
            local param_default = require "param_default"
            local default_path = "/device_config_default.json"
            local wf = io.open(default_path, "w")
            if wf then
                wf:write(json.encode(param_default))
                wf:close()
            end
        end)
        publish_response("factory_reset", seq, ok and 0 or 1, ok and "ok" or "failed")
        if ok then sys.timerStart(rtos.reboot, 3000) end
    end)

    -- 云端指令：获取配置
    sys.subscribe("CMD_GET_CONFIG", function(seq)
        log.info(TASK_NAME, "CMD_GET_CONFIG received, seq:", seq)
        local f = io.open("/device_config.json", "r")
        if f then
            local content = f:read("*a")
            f:close()
            local topic = "device/" .. get_client_id() .. "/response"
            local payload = json.encode({
                cmd = "get_config",
                seq = seq,
                result = 0,
                msg = "success",
                data = json.decode(content)
            })
            sys.publish("SEND_DATA_REQ", TASK_NAME, topic, payload, mqtt_config.qos or 1)
        else
            publish_response("get_config", seq, 1, "config file not found")
        end
    end)

    -- 云端指令：设置配置（合并更新）
    local function deep_equal(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k, v in pairs(a) do
            if not deep_equal(v, b[k]) then return false end
        end
        for k, v in pairs(b) do
            if not deep_equal(v, a[k]) then return false end
        end
        return true
    end

    local function merge_config(base, update)
        local result = {}
        for k, v in pairs(base) do result[k] = v end
        for k, v in pairs(update) do
            if type(v) == "table" and type(result[k]) == "table" then
                result[k] = merge_config(result[k], v)
            else
                result[k] = v
            end
        end
        return result
    end

    sys.subscribe("CMD_SET_CONFIG", function(data, seq)
        log.info(TASK_NAME, "CMD_SET_CONFIG received, seq:", seq)
        if not data then
            publish_response("set_config", seq, 1, "invalid data")
            return
        end

        local f = io.open("/device_config.json", "r")
        local current_config = {}
        if f then
            local content = f:read("*a")
            f:close()
            local ok, cfg = pcall(json.decode, content)
            if ok and cfg then current_config = cfg end
        end

        local new_config = merge_config(current_config, data)
        if deep_equal(current_config, new_config) then
            publish_response("set_config", seq, 1, "no change")
            return
        end

        f = io.open("/device_config.json", "w")
        if f then
            f:write(json.encode(new_config))
            f:close()
            log.info(TASK_NAME, "set_config saved")
            publish_response("set_config", seq, 0, "success")
            sys.publish("CONFIG_UPDATED", new_config)
        else
            publish_response("set_config", seq, 1, "save failed")
        end
    end)

    -- 指令响应转发
    sys.subscribe("MQTT_CMD_RESULT", function(cmd, seq, result, msg)
        publish_response(cmd, seq, result, msg)
    end)

    -- DI 状态变化即时上报
    sys.subscribe("DI_STATUS_CHANGED", function(di1, di2)
        local topic = "device/" .. get_client_id() .. "/event"
        local payload = json.encode({
            ts = os.time(),
            type = "di_change",
            data = {di = {di1 and 1 or 0, di2 and 1 or 0}}
        })
        sys.publish("SEND_DATA_REQ", TASK_NAME, topic, payload, mqtt_config.qos or 1)
    end)

    -- DO 状态变化即时上报
    sys.subscribe("DO_STATUS_CHANGED", function(ch, state)
        local topic = "device/" .. get_client_id() .. "/event"
        local payload = json.encode({
            ts = os.time(),
            type = "do_change",
            data = {ch = ch, value = state and 1 or 0}
        })
        sys.publish("SEND_DATA_REQ", TASK_NAME, topic, payload, mqtt_config.qos or 1)
    end)
end

--[[
@function init
@summary 初始化模块
@param mqtt_cfg table MQTT配置（由app_main统一传入）
@return nil
]]
function mqtt_app.init(mqtt_cfg)
    log.info(TASK_NAME, "initializing")
    mqtt_config = mqtt_cfg or {}
    subscribe_events()
    sys.taskInitEx(mqtt_client_task, TASK_NAME)
    log.info(TASK_NAME, "mqtt_app ready")
end

return mqtt_app
