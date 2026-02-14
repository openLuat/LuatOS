--[[
@module extalk
@summary extalk扩展库
@version 1.1.2
@date    2025.12.09
@author  陈媛媛（适配多网卡/手动重连）
@usage
    local extalk = require "extalk"
    -- 配置并初始化
    extalk.setup({
        key = "your_product_key",
        heart_break_time = 30,
        contact_list_cbfnc = function(dev_list) end,
        state_cbfnc = function(state) end
    })
    -- 发起对讲
    extalk.start("remote_device_id")
    -- 结束对讲
    extalk.stop()
]]

local extalk = {}

-- 模块常量（保留原始数据结构）
extalk.START = 1        -- 通话开始
extalk.STOP = 2         -- 通话结束
extalk.UNRESPONSIVE = 3 -- 未响应
extalk.ONE_ON_ONE = 5   -- 一对一来电
extalk.BROADCAST = 6    -- 广播

local AIRTALK_TASK_NAME = "airtalk_task"

-- 消息类型常量（保留原始数据结构）
local MSG_CONNECT_ON_IND = 0
local MSG_CONNECT_OFF_IND = 1
local MSG_AUTH_IND = 2
local MSG_SPEECH_ON_IND = 3
local MSG_SPEECH_OFF_IND = 4
local MSG_SPEECH_CONNECT_TO = 5
local MSG_SPEECH_STOP_TEST_END = 22

-- 设备状态常量（保留原始数据结构）
local SP_T_NO_READY = 0   -- 离线状态无法对讲
local SP_T_IDLE = 1       -- 对讲空闲状态
local SP_T_CONNECTING = 2 -- 主动发起对讲
local SP_T_CONNECTED = 3  -- 对讲中

local SUCC = "success"

-- 全局状态变量（保留原始数据结构）
local g_state = SP_T_NO_READY -- 设备状态
local g_mqttc = nil           -- mqtt客户端
local g_local_id              -- 本机ID
local g_stask_start = false   -- 任务启动标记
local g_remote_id             -- 对端ID
local g_s_type                -- 对讲的模式，字符串形式
local g_s_topic               -- 对讲用的topic
local g_s_mode                -- 对讲的模式
local g_dev_list              -- 对讲列表
local g_dl_topic              -- 下行消息topic模板

-- 配置参数
local extalk_configs_local = {
    key = 0,                  -- 项目key，一般需要和main的PRODUCT_KEY保持一致
    heart_break_time = 0,     -- 心跳间隔(单位秒)
    contact_list_cbfnc = nil, -- 联系人回调函数，含设备号和昵称
    state_cbfnc = nil,        -- 状态回调，分为对讲开始，对讲结束，未响应
}

-- 工具函数：参数检查
local function check_param(param, expected_type, name)
    if type(param) ~= expected_type then
        log.error(string.format("参数错误: %s 应为 %s 类型，实际为 %s",
            name, expected_type, type(param)))
        return false
    end
    return true
end

-- MQTT消息发布函数，集中处理所有发布操作并打印日志
local function publish_message(topic, payload)
    if g_mqttc then
        log.info("MQTT发布 - 主题:", topic, "内容:", payload)
        g_mqttc:publish(topic, payload)
    else
        log.error("MQTT客户端未初始化，无法发布消息")
    end
end

-- 对讲超时处理
function extalk.wait_speech_to()
    log.info("主动请求对讲超时无应答")
    extalk.speech_off(true, true)
end

-- 发送鉴权消息
local function auth()
    if g_state == SP_T_NO_READY and g_mqttc then
        local topic = string.format("ctrl/uplink/%s/0001", g_local_id)
        local payload = json.encode({
            ["key"] = extalk_configs_local.key,
            ["device_type"] = 1
        })
        publish_message(topic, payload)
    end
end

-- 发送心跳消息
local function heart()
    if g_mqttc then
        adc.open(adc.CH_VBAT)
        local vbat = adc.get(adc.CH_VBAT)
        adc.close(adc.CH_VBAT)
        local topic = string.format("ctrl/uplink/%s/0005", g_local_id)
        local payload = json.encode({
            ["csq"] = mobile.csq(),
            ["battery"] = vbat
        })
        publish_message(topic, payload)
    end
end

-- 开始对讲
local function speech_on(ssrc, sample)
    g_state = SP_T_CONNECTED
    g_mqttc:subscribe(g_s_topic)
    airtalk.set_topic(g_s_topic)
    airtalk.set_ssrc(ssrc)
    log.info("对讲模式", g_s_mode)
    airtalk.speech(true, g_s_mode, sample)
    sys.sendMsg(AIRTALK_TASK_NAME, MSG_SPEECH_ON_IND, true)
    sys.timerStopAll(extalk.wait_speech_to)
end

-- 结束对讲
function extalk.speech_off(need_upload, need_ind)
    if g_state == SP_T_CONNECTED then
        g_mqttc:unsubscribe(g_s_topic)
        airtalk.speech(false)
        g_s_topic = nil
    end

    g_state = SP_T_IDLE
    sys.timerStopAll(auth)
    sys.timerStopAll(extalk.wait_speech_to)

    if need_upload and g_mqttc then
        local topic = string.format("ctrl/uplink/%s/0004", g_local_id)
        publish_message(topic, json.encode({ ["to"] = g_remote_id }))
    end

    if need_ind then
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_SPEECH_OFF_IND, true)
    end
end

-- 命令处理：请求对讲应答
local function handle_speech_response(obj)
    if g_state ~= SP_T_CONNECTING then
        log.error("state", g_state, "need", SP_T_CONNECTING)
        return
    end

    if obj and obj["result"] == SUCC and g_s_topic == obj["topic"] then
        -- 开始对讲
        local sample_rate = obj["audio_code"] == "amr-nb" and 8000 or 16000
        speech_on(obj["ssrc"], sample_rate)
        return
    else
        log.info(obj["result"], obj["topic"], g_s_topic)
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_SPEECH_ON_IND, false)
    end

    g_s_topic = nil
    g_state = SP_T_IDLE
end

-- 命令处理：对端来电
local function handle_incoming_call(obj)
    if not obj or not obj["topic"] or not obj["ssrc"] or not obj["audio_code"] or not obj["type"] then
        local response = {
            ["result"] = "failed",
            ["topic"] = obj and obj["topic"] or "",
            ["info"] = "无效的请求参数"
        }
        publish_message(string.format("ctrl/uplink/%s/8102", g_local_id), json.encode(response))
        return
    end

    -- 非空闲状态无法接收来电
    if g_state ~= SP_T_IDLE then
        log.error("state", g_state, "need", SP_T_IDLE)
        local response = {
            ["result"] = "failed",
            ["topic"] = obj["topic"],
            ["info"] = "device is busy"
        }
        publish_message(string.format("ctrl/uplink/%s/8102", g_local_id), json.encode(response))
        return
    end

    local response, from = {}, nil

    -- 提取对端ID
    from = string.match(obj["topic"], "audio/(.*)/.*/.*")
    if not from then
        response = {
            ["result"] = "failed",
            ["topic"] = obj["topic"],
            ["info"] = "topic error"
        }
        publish_message(string.format("ctrl/uplink/%s/8102", g_local_id), json.encode(response))
        return
    end

    -- 处理一对一通话
    if obj["type"] == "one-on-one" then
        g_s_topic = obj["topic"]
        g_remote_id = from
        g_s_type = "one-on-one"
        g_s_mode = airtalk.MODE_PERSON

        -- 触发回调
        if extalk_configs_local.state_cbfnc then
            extalk_configs_local.state_cbfnc({
                state = extalk.ONE_ON_ONE,
                id = from
            })
        end

        response = { ["result"] = SUCC, ["topic"] = obj["topic"], ["info"] = "" }
        local sample_rate = obj["audio_code"] == "amr-nb" and 8000 or 16000
        speech_on(obj["ssrc"], sample_rate)
    end

    -- 处理广播
    if obj["type"] == "broadcast" then
        g_s_topic = obj["topic"]
        g_remote_id = from
        g_s_mode = airtalk.MODE_GROUP_LISTENER
        g_s_type = "broadcast"

        -- 触发回调
        if extalk_configs_local.state_cbfnc then
            extalk_configs_local.state_cbfnc({
                state = extalk.BROADCAST,
                id = from
            })
        end

        response = { ["result"] = SUCC, ["topic"] = obj["topic"], ["info"] = "" }
        local sample_rate = obj["audio_code"] == "amr-nb" and 8000 or 16000
        speech_on(obj["ssrc"], sample_rate)
    end

    -- 发送响应
    publish_message(string.format("ctrl/uplink/%s/8102", g_local_id), json.encode(response))
end

-- 命令处理：对端挂断
local function handle_remote_hangup(obj)
    local response = {}

    if g_state == SP_T_IDLE then
        response = { ["result"] = "failed", ["info"] = "no speech" }
    else
        log.info("0103", obj, obj["type"], g_s_type)
        if obj and obj["type"] == g_s_type then
            response = { ["result"] = SUCC, ["info"] = "" }
            extalk.speech_off(false, true)
        else
            response = { ["result"] = "failed", ["info"] = "type mismatch" }
        end
    end

    publish_message(string.format("ctrl/uplink/%s/8103", g_local_id), json.encode(response))
end

-- 命令处理：更新设备列表
local function handle_device_list_update(obj)
    local response = {}
    if obj then
        g_dev_list = obj["dev_list"]
        response = { ["result"] = SUCC, ["info"] = "" }
    else
        response = { ["result"] = "failed", ["info"] = "json info error" }
    end

    publish_message(string.format("ctrl/uplink/%s/8101", g_local_id), json.encode(response))
end

-- 命令处理：鉴权结果
local function handle_auth_result(obj)
    if obj and obj["result"] == SUCC then
        publish_message(string.format("ctrl/uplink/%s/0002", g_local_id), "")   -- 更新列表
        sys.timerLoopStart(heart, extalk_configs_local.heart_break_time * 1000) -- 发起心跳
    else
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, false,
            "鉴权失败" .. (obj and obj["info"] or ""))
        log.error("鉴权失败,可能是没有修改PRODUCT_KEY")
    end
end

-- 命令处理：设备列表更新应答
local function handle_device_list_response(obj)
    if obj and obj["result"] == SUCC then
        g_dev_list = obj["dev_list"]
        if extalk_configs_local.contact_list_cbfnc then
            extalk_configs_local.contact_list_cbfnc(g_dev_list)
        end
        g_state = SP_T_IDLE
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, true) -- 完整登录流程结束
    else
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, false, "更新设备列表失败")
    end
end

-- 命令解析路由表
local cmd_handlers = {
    ["8003"] = handle_speech_response,     -- 请求对讲应答
    ["0102"] = handle_incoming_call,       -- 平台通知对端对讲开始
    ["0103"] = handle_remote_hangup,       -- 平台通知终端对讲结束
    ["0101"] = handle_device_list_update,  -- 平台通知终端更新对讲设备列表
    ["8001"] = handle_auth_result,         -- 平台对鉴权应答
    ["8002"] = handle_device_list_response -- 平台对终端获取终端列表应答
}

-- 解析接收到的消息
local function analyze_v1(cmd, topic, obj)
    -- 忽略心跳和结束对讲的应答
    if cmd == "8005" or cmd == "8004" then
        return
    end

    -- 查找并执行对应的命令处理器
    local handler = cmd_handlers[cmd]
    if handler then
        handler(obj)
    else
        log.warn("未处理的命令", cmd)
    end
end

-- MQTT回调处理
local function mqtt_cb(mqttc, event, topic, payload)
    log.info("MQTT事件:", event, "主题:", topic or "")

    if event == "conack" then
        -- MQTT连接成功，开始自定义鉴权流程
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_CONNECT_ON_IND)
        mqttc:subscribe("ctrl/downlink/" .. g_local_id .. "/#")
    elseif event == "suback" then
        if g_state == SP_T_NO_READY then
            if topic then
                auth()
            else
                sys.sendMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, false,
                    "订阅失败: ctrl/downlink/" .. g_local_id .. "/#")
            end
        elseif g_state == SP_T_CONNECTED and not topic then
            extalk.speech_off(false, true)
        end
    elseif event == "recv" then
        local result = string.match(topic, g_dl_topic)
        if result then
            local obj = json.decode(payload)
            analyze_v1(result, topic, obj)
        end
    elseif event == "disconnect" then
        log.warn("MQTT断开连接，触发对讲关闭")
        extalk.speech_off(false, true)
        g_state = SP_T_NO_READY
        -- 发送断开通知，触发重连逻辑
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_CONNECT_OFF_IND, false)
    elseif event == "error" then
        log.error("MQTT错误:", topic, payload)
        -- 发送错误通知，触发重连逻辑
        sys.sendMsg(AIRTALK_TASK_NAME, MSG_CONNECT_OFF_IND, false)
    elseif event == "pong" then
        -- 心跳应答，喂网络看门狗
        --sys.publish("FEED_NETWORK_WATCHDOG")
    end
end

-- 任务消息处理
local function task_cb(msg)
    if msg[1] == MSG_SPEECH_CONNECT_TO then
        extalk.speech_off(true, false)
    else
        log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
    end
end

-- 对讲事件回调
local function airtalk_event_cb(event, param)
    log.info("airtalk event", event, param)
    if event == airtalk.EVENT_ERROR then
        if param == airtalk.ERROR_NO_DATA and g_s_mode == airtalk.MODE_PERSON then
            log.error("长时间没有收到音频数据")
            extalk.speech_off(true, true)
        end
    end
end

-- MQTT任务主循环（适配多网卡+手动重连）
local function airtalk_mqtt_task()
    -- 提前声明所有局部变量（保证goto合规）
    local msg, online, result, reconnect_delay
    local MQTT_SERVER = "mqtt.airtalk.luatos.com"
    local MQTT_PORT = 1883

    if g_stask_start then
        log.info("airtalk task 已经初始化了")
        return true
    end

    g_stask_start = true
    online = false
    reconnect_delay = 5000 -- 默认重连延迟5秒

    -- 初始化本地ID
    g_local_id = mobile.imei()
    g_dl_topic = "ctrl/downlink/" .. g_local_id .. "/(%w%w%w%w)"

    -- 配置对讲参数（只初始化一次）
    airtalk.config(airtalk.PROTOCOL_MQTT, nil, 200) -- 缓冲至少200ms播放
    airtalk.on(airtalk_event_cb)
    airtalk.start()

    -- 主循环：处理网络等待+MQTT连接+重连
    while true do
        -- 等待默认网卡就绪（适配多网卡）
        while not socket.adapter(socket.dft()) do
            log.warn("airtalk_mqtt_task: 等待默认网卡就绪，当前网卡ID:", socket.dft())
            -- 等待IP_READY消息，1秒超时（适配多网卡切换）
            sys.waitUntil("IP_READY", 1000)
        end
        log.info("airtalk_mqtt_task: 默认网卡就绪，ID:", socket.dft())

        -- 清空任务消息队列（避免重连时残留旧消息）
        sys.cleanMsg(AIRTALK_TASK_NAME)

        -- 销毁旧的MQTT客户端（如果存在）
        if g_mqttc then
            g_mqttc:close()
            g_mqttc = nil
        end

        -- 创建新的MQTT客户端
        g_mqttc = mqtt.create(nil, MQTT_SERVER, MQTT_PORT, false, { rxSize = 32768 })
        if not g_mqttc then
            log.error("airtalk_mqtt_task: 创建MQTT客户端失败")
            goto EXCEPTION_PROC
        end

        -- 配置MQTT客户端（禁用自动重连，手动控制）
        g_mqttc:auth(g_local_id, g_local_id, mobile.muid())
        g_mqttc:keepalive(240) -- 心跳间隔240秒
        g_mqttc:debug(false)
        g_mqttc:on(mqtt_cb)

        -- 更新airtalk的MQTT客户端引用
        airtalk.config(airtalk.PROTOCOL_MQTT, g_mqttc, 200)

        log.info("airtalk_mqtt_task: 设备信息 - IMEI:", g_local_id, "MUID:", mobile.muid())

        -- 连接MQTT服务器
        result = g_mqttc:connect()
        if not result then
            log.error("airtalk_mqtt_task: MQTT连接失败")
            goto EXCEPTION_PROC
        end

        -- 处理登录流程（鉴权+在线状态）
        online = false
        while not online do
            -- 等待鉴权结果，30秒超时
            msg = sys.waitMsg(AIRTALK_TASK_NAME, MSG_AUTH_IND, 30000)

            if type(msg) == 'table' then
                online = msg[2]
                if online then
                    -- 鉴权通过：60分钟重新鉴权+启动心跳
                    log.info("airtalk_mqtt_task: 鉴权成功，进入在线状态")
                    sys.timerLoopStart(auth, 3600000)
                    sys.timerLoopStart(heart, extalk_configs_local.heart_break_time * 1000)
                else
                    -- 鉴权失败：记录原因，退出登录流程
                    log.error("airtalk_mqtt_task: 鉴权失败，原因:", msg[3] or "未知")
                    online = false
                    break
                end
            else
                -- 超时未收到鉴权结果：重新发送鉴权请求
                log.warn("airtalk_mqtt_task: 鉴权超时，重新发送鉴权请求")
                auth()
            end
        end

        -- 在线状态处理：处理对讲+MQTT事件

        log.info("airtalk_mqtt_task: 对讲平台已连接，进入在线状态")
        while online do
            msg = sys.waitMsg(AIRTALK_TASK_NAME)

            if type(msg) == 'table' and type(msg[1]) == "number" then
                -- 处理对讲开始/结束/超时等事件
                if msg[1] == MSG_SPEECH_STOP_TEST_END then
                    if g_state ~= SP_T_CONNECTING and g_state ~= SP_T_CONNECTED then
                        log.info("airtalk_mqtt_task: 无活跃对讲，状态:", g_state)
                    else
                        extalk.speech_off(true, true)
                    end
                elseif msg[1] == MSG_SPEECH_ON_IND then
                    if extalk_configs_local.state_cbfnc then
                        local state = msg[2] and extalk.START or extalk.UNRESPONSIVE
                        extalk_configs_local.state_cbfnc({ state = state })
                    end
                elseif msg[1] == MSG_SPEECH_OFF_IND then
                    if extalk_configs_local.state_cbfnc then
                        extalk_configs_local.state_cbfnc({ state = extalk.STOP })
                    end
                elseif msg[1] == MSG_CONNECT_OFF_IND then
                    -- MQTT断开/错误，退出在线状态
                    log.warn("airtalk_mqtt_task: 收到断开通知，退出在线状态")
                    online = false
                    break
                end
            else
                log.info("airtalk_mqtt_task: 收到未知消息:", type(msg), msg)
            end

            msg = nil     -- 清理引用
        end


        -- 异常处理块（goto目标，所有局部变量已提前声明）
        ::EXCEPTION_PROC::
        log.warn("airtalk_mqtt_task: 进入异常处理，准备重连")

        -- 清理资源
        extalk.speech_off(false, true)          -- 强制结束对讲
        sys.timerStopAll(auth)                  -- 停止鉴权定时器
        sys.timerStopAll(heart)                 -- 停止心跳定时器
        sys.timerStopAll(extalk.wait_speech_to) -- 停止对讲超时定时器

        -- 清空消息队列
        sys.cleanMsg(AIRTALK_TASK_NAME)

        -- 关闭MQTT客户端
        if g_mqttc then
            g_mqttc:disconnect()
            sys.wait(1000) -- 等待断开指令发送
            g_mqttc:close()
            g_mqttc = nil
        end

        -- 重置状态
        g_state = SP_T_NO_READY
        online = false

        -- 延迟重连
        log.info("airtalk_mqtt_task: 等待", reconnect_delay / 1000, "秒后重连")
        sys.wait(reconnect_delay)
    end
end

-- 模块初始化
function extalk.setup(extalk_configs)
    if not extalk_configs or type(extalk_configs) ~= "table" then
        log.error("AirTalk配置必须为table类型")
        return false
    end

    -- 检查配置参数
    if not check_param(extalk_configs.key, "string", "key") then
        return false
    end
    extalk_configs_local.key = extalk_configs.key

    if not check_param(extalk_configs.heart_break_time, "number", "heart_break_time") then
        return false
    end
    extalk_configs_local.heart_break_time = extalk_configs.heart_break_time

    if extalk_configs.contact_list_cbfnc and type(extalk_configs.contact_list_cbfnc) ~= "function" then
        log.error("参数错误: contact_list_cbfnc 应为 function 类型")
        return false
    end
    extalk_configs_local.contact_list_cbfnc = extalk_configs.contact_list_cbfnc or nil

    if extalk_configs.state_cbfnc and type(extalk_configs.state_cbfnc) ~= "function" then
        log.error("参数错误: state_cbfnc 应为 function 类型")
        return false
    end
    extalk_configs_local.state_cbfnc = extalk_configs.state_cbfnc or nil

    -- 启动任务
    sys.taskInitEx(airtalk_mqtt_task, AIRTALK_TASK_NAME, task_cb)
    return true
end

-- 开始对讲
function extalk.start(id)
    if g_state ~= SP_T_IDLE then
        log.warn("正在对讲无法开始，当前状态:", g_state)
        return false
    end

    if id == nil then
        -- 广播模式
        g_remote_id = "all"
        g_state = SP_T_CONNECTING
        g_s_mode = airtalk.MODE_GROUP_SPEAKER
        g_s_type = "broadcast"
        g_s_topic = string.format("audio/%s/all/%s",
            g_local_id, string.sub(tostring(mcu.ticks()), -4, -1))

        publish_message(string.format("ctrl/uplink/%s/0003", g_local_id),
            json.encode({ ["topic"] = g_s_topic, ["type"] = g_s_type }))
        sys.timerStart(extalk.wait_speech_to, 15000)
    else
        -- 一对一模式
        log.info("向", id, "主动发起对讲")
        if id == g_local_id then
            log.error("不允许本机给本机拨打电话")
            return false
        end

        g_state = SP_T_CONNECTING
        g_remote_id = id
        g_s_mode = airtalk.MODE_PERSON
        g_s_type = "one-on-one"
        g_s_topic = string.format("audio/%s/%s/%s",
            g_local_id, id, string.sub(tostring(mcu.ticks()), -4, -1))

        publish_message(string.format("ctrl/uplink/%s/0003", g_local_id),
            json.encode({ ["topic"] = g_s_topic, ["type"] = g_s_type }))
        sys.timerStart(extalk.wait_speech_to, 15000)
    end

    return true
end

-- 结束对讲
function extalk.stop()
    if g_state ~= SP_T_CONNECTING and g_state ~= SP_T_CONNECTED then
        log.info("没有对讲，当前状态:", g_state)
        return false
    end

    log.info("主动断开对讲")
    extalk.speech_off(true, true)
    return true
end

return extalk
