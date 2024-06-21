-- 合宙模组 LUATOS 接入 ThingsCloud 物联网平台
-- 接入协议参考：ThingsCloud MQTT 接入文档 https://docs.thingscloud.xyz/guide/connect-device/mqtt.html
local ThingsCloud = {}

local projectKey = "" -- project_key
local accessToken = "" -- access_token
local typeKey = "" -- type_key
local host = ""
local port = 1883
local apiEndpoint = "" -- api endpoint
local mqttc = nil
local connected = false
local deviceInfo = {}

local certFetchRetryMax = 5
local certFetchRetryCnt = 0

local SUBSCRIBE_PREFIX = {
    ATTRIBUTES_GET_REPONSE = "attributes/get/response/",
    ATTRIBUTES_PUSH = "attributes/push",
    COMMAND_SEND = "command/send/",
    COMMAND_REPLY_RESPONSE = "command/reply/response/",
    DATA_SET = "data/",
    GW_ATTRIBUTES_PUSH = "gateway/attributes/push",
    GW_COMMAND_SEND = "gateway/command/send"
}
local EVENT_TYPES = {
    fetch_cert = true,
    connect = true,
    attributes_report_response = true,
    attributes_get_response = true,
    attributes_push = true,
    command_send = true,
    command_reply_response = true,
    data_set = true,
    gw_attributes_push = true,
    gw_command_send = true
}
local CALLBACK = {}
local QUEUE = {
    PUBLISH = {}
}
local logger = {}
function logger.info(...)
    log.info("ThingsCloud", ...)
end

function ThingsCloud.on(eType, cb)
    if not eType or not EVENT_TYPES[eType] or type(cb) ~= "function" then
        return
    end
    CALLBACK[eType] = cb
    logger.info("on", eType)
end

local function cb(eType, ...)
    if not eType or not EVENT_TYPES[eType] or not CALLBACK[eType] then
        return
    end
    CALLBACK[eType](...)
    logger.info("event", eType, ...)
end

local function mqttConnect()
    local retryCount = 0
    logger.info("ThingsCloud connecting...")

    mqttc = mqtt.create(nil, host, port, false, {rxSize = 4096})
    mqttc:auth(mobile.imei(), accessToken, projectKey)
    mqttc:keepalive(300)
    mqttc:autoreconn(true, 10000)
    mqttc:connect()

    mqttc:on(function(mqtt_client, event, data, payload)

        if event == "conack" then
            connected = true
            logger.info("ThingsCloud connected")
            cb("connect", true)
            sys.publish("mqtt_conack")
            ThingsCloud.subscribe("attributes/push")
            ThingsCloud.subscribe("attributes/get/response/+")
            ThingsCloud.subscribe("command/send/+")
            ThingsCloud.subscribe("command/reply/response/+")

        elseif event == "recv" then
            logger.info("receive from cloud", data or nil, payload or "nil")
            if (data:sub(1, SUBSCRIBE_PREFIX.ATTRIBUTES_GET_REPONSE:len()) == SUBSCRIBE_PREFIX.ATTRIBUTES_GET_REPONSE) then
                local response = json.decode(payload)
                local responseId = tonumber(data:sub(SUBSCRIBE_PREFIX.ATTRIBUTES_GET_REPONSE:len() + 1))
                cb("attributes_get_response", response, responseId)
            elseif (data == SUBSCRIBE_PREFIX.ATTRIBUTES_PUSH) then
                local response = json.decode(payload)
                cb("attributes_push", response)
            elseif (data:sub(1, SUBSCRIBE_PREFIX.COMMAND_SEND:len()) == SUBSCRIBE_PREFIX.COMMAND_SEND) then
                local response = json.decode(payload)
                if response.method and response.params then
                    cb("command_send", response)
                end
            elseif (data:sub(1, SUBSCRIBE_PREFIX.COMMAND_REPLY_RESPONSE:len()) ==
                SUBSCRIBE_PREFIX.COMMAND_REPLY_RESPONSE) then
                local response = json.decode(payload)
                local replyId = tonumber(data:sub(SUBSCRIBE_PREFIX.COMMAND_REPLY_RESPONSE:len() + 1))
                cb("command_reply_response", response, replyId)
            elseif (data:sub(1, SUBSCRIBE_PREFIX.DATA_SET:len()) == SUBSCRIBE_PREFIX.DATA_SET) then
                local tmp = split(data, "/")
                if #tmp == 3 and tmp[3] == "set" then
                    local identifier = tmp[2]
                    cb("data_set", payload)
                end
            elseif (data == SUBSCRIBE_PREFIX.GW_ATTRIBUTES_PUSH) then
                local response = json.decode(payload)
                cb("gw_attributes_push", response)
            elseif (data == SUBSCRIBE_PREFIX.GW_COMMAND_SEND) then
                local response = json.decode(payload)
                cb("gw_command_send", response)
            end

        elseif event == "sent" then
            log.info("mqtt", "sent", data)
        end
    end)

end

function ThingsCloud.disconnect()
    if not connected then
        return
    end
    mqttc:close()
    mqttc = nil
end

function ThingsCloud.connect(param)
    if not param.host or not param.projectKey then
        logger.info("host or projectKey not found")
        return
    end
    host = param.host
    projectKey = param.projectKey

    if param.accessToken then
        accessToken = param.accessToken
        sys.waitUntil("IP_READY", 30000)
        sys.taskInit(function()
            sys.taskInit(procConnect)
        end)

    else
        if not param.apiEndpoint then
            logger.info("apiEndpoint not found")
            return
        end
        apiEndpoint = param.apiEndpoint
        if param.typeKey ~= "" or param.typeKey ~= nil then
            typeKey = param.typeKey
        end
        sys.waitUntil("IP_READY", 30000)
        sys.taskInit(function()
            sys.taskInit(fetchDeviceCert)
        end)

    end
end

-- 一型一密，使用IMEI作为DeviceKey，领取设备证书AccessToken
function fetchDeviceCert()
    local headers = {}
    headers["Project-Key"] = projectKey
    headers["Content-Type"] = "application/json"
    local url = apiEndpoint .. "/device/v1/certificate"
    local deviceKey = mobile.imei()
    local code, headers, body = http.request("POST", url, headers, json.encode({
        device_key = deviceKey,
        type_key = typeKey
    }), {
        timeout = 5000
    }).wait()
    log.info("http fetch cert:", deviceKey, code, headers, body)
    if code == 200 then
        local data = json.decode(body)
        if data.result == 1 then
            sys.taskInit(function()
                cb("fetch_cert", true)
            end)
            deviceInfo = data.device
            accessToken = deviceInfo.access_token
            procConnect()
            return
        end
    end
    if certFetchRetryCnt < certFetchRetryMax then
        -- 重试
        certFetchRetryCnt = certFetchRetryCnt + 1
        sys.wait(1000 * 10)
        fetchDeviceCert()
    else
        cb("fetch_cert", false)
    end
end

function procConnect()
    mqttConnect()
    sys.waitUntil("mqtt_conack")
    sys.taskInit(function()
        while true do
            if #QUEUE.PUBLISH > 0 then
                local item = table.remove(QUEUE.PUBLISH, 1)
                logger.info("publish", item.topic, item.data)
                if mqttc:publish(item.topic, item.data) then
                    -- 
                end
            end
            sys.wait(100)
        end
    end)
end

function ThingsCloud.isConnected()
    return connected
end

local function insertPublishQueue(topic, data)
    if not connected then
        return
    end
    table.insert(QUEUE.PUBLISH, {
        topic = topic,
        data = data
    })
end

function ThingsCloud.subscribe(topic)
    if not connected then
        return
    end
    logger.info("subscribe", topic)
    mqttc:subscribe(topic)
end

function ThingsCloud.publish(topic, data)
    insertPublishQueue(topic, data)
end

function ThingsCloud.reportAttributes(tableData)
    insertPublishQueue("attributes", json.encode(tableData))
    sys.publish("QUEUE_PUBLISH", "ATTRIBUTES")
end

function ThingsCloud.getAttributes(attrsList, options)
    options = options or {}
    options.getId = options.getId or 1000
    local data = {
        keys = attrsList
    }
    if #attrsList == 0 then
        data = {}
    end
    insertPublishQueue("attributes/get/" .. tostring(options.getId), json.encode(data))
end

function ThingsCloud.reportEvent(event, options)
    options = options or {}
    options.eventId = options.eventId or 1000
    insertPublishQueue("event/report/" .. tostring(options.eventId), json.encode(event))
end

function ThingsCloud.replyCommand(commandReply, options)
    options = options or {}
    options.replyId = options.replyId or 1000
    insertPublishQueue("command/reply/" .. tostring(options.replyId), json.encode(commandReply))
end

function ThingsCloud.publishCustomTopic(topic, payload, options)
    insertPublishQueue(topic, payload)
end

function getAccessToken()
    return accessToken
end

function isGateway()
    if deviceInfo.conn_type == "3" then
        return true
    end
    return false
end

function split(str, sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, function(c)
        fields[#fields + 1] = c
    end)
    return fields
end

return ThingsCloud
