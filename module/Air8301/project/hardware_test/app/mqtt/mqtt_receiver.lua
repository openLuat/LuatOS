--[[
@module  mqtt_receiver
@summary MQTT接收处理模块
@version 1.0
@date    2026.09.04
@author  江访
@usage
本模块为MQTT接收处理模块，负责：
1、处理收到的publish数据
2、解析指令并分发给对应模块处理
3、适配 Air8301 硬件的 IO 控制指令
]]

local mqtt_receiver = {}

--[[
@function proc
@summary 处理接收到的publish数据
@param topic string 主题
@param payload string 负载数据
@param metas table 元数据 {qos, retain, dup, message_id}
@return nil
]]
function mqtt_receiver.proc(topic, payload, metas)
    log.info("mqtt_receiver.proc", topic, payload:len())

    -- 解析JSON
    local ok, msg = pcall(json.decode, payload)
    if not ok or not msg then
        log.warn("mqtt_receiver.proc", "json decode failed", payload)
        return
    end

    local cmd = msg.cmd
    local seq = msg.seq
    local data = msg.data

    if not cmd then
        log.warn("mqtt_receiver.proc", "no cmd in message")
        return
    end

    log.info("mqtt_receiver.proc", "cmd:", cmd, "seq:", seq)

    -- 根据cmd分发到对应模块
    if cmd == "set_do" then
        -- 设置DO继电器: {do_num: 1/2, value: 0/1}
        local do_num = data and data.do_num
        local value = data and data.value
        log.info("mqtt_receiver.proc", "set_do", do_num, value)
        if do_num and value ~= nil then
            sys.publish("DO_SET_REQUEST", do_num, value == 1)
        end
        sys.publish("MQTT_CMD_RESULT", cmd, seq, 0, "ok")

    elseif cmd == "set_buzzer" then
        -- 蜂鸣器鸣响
        log.info("mqtt_receiver.proc", "set_buzzer")
        sys.publish("BUZZER_BEEP_REQUEST")
        sys.publish("MQTT_CMD_RESULT", cmd, seq, 0, "ok")

    elseif cmd == "set_led" then
        -- 设置LED: {type: "4g"/"wifi", state: 0/1}
        local led_type = data and data.type
        local state = data and data.state
        log.info("mqtt_receiver.proc", "set_led", led_type, state)
        if led_type and state ~= nil then
            sys.publish("LED_SET_REQUEST", led_type, state == 1)
        end
        sys.publish("MQTT_CMD_RESULT", cmd, seq, 0, "ok")

    elseif cmd == "feed_watchdog" then
        -- 喂狗
        log.info("mqtt_receiver.proc", "feed_watchdog")
        sys.publish("WDT_FEED_REQUEST")
        sys.publish("MQTT_CMD_RESULT", cmd, seq, 0, "ok")

    elseif cmd == "reboot" then
        log.info("mqtt_receiver.proc", "reboot command received")
        sys.publish("CMD_REBOOT", seq)

    elseif cmd == "factory_reset" then
        log.info("mqtt_receiver.proc", "factory_reset command received")
        sys.publish("CMD_FACTORY_RESET", seq)

    elseif cmd == "get_config" then
        log.info("mqtt_receiver.proc", "get_config command received")
        sys.publish("CMD_GET_CONFIG", seq)

    elseif cmd == "set_config" then
        log.info("mqtt_receiver.proc", "set_config command received")
        sys.publish("CMD_SET_CONFIG", data, seq)

    else
        log.warn("mqtt_receiver.proc", "unknown cmd:", cmd)
        sys.publish("MQTT_CMD_RESULT", cmd, seq, 1, "unknown cmd")
    end
end

return mqtt_receiver
