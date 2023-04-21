--- 模块功能：780E连接到ctwing平台
-- @module ctwing_iot
-- @author 翟科研
-- @license MIT
-- @copyright OpenLuat.com
-- @release 2023.4.13
local sys = require "sys"
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")

--------------需更改的信息-------------------------
-- 设备ID
local device_id ="15601013001"
-- 账号名
local user_name="001"
-- 特征串
local password ="8Jtoo3rc9RRYgtaWv5QXxvF15-tzlmgNzk2O6cQeg_o"
-- 主题
local ctwing_iot_subscribetopic = {
    ["signal_report"]=0 ,["test"]=0,["z1223"]=1 --本demo以z1223为例
}
--------------以上根据个人注册信息修改-------------
local mqtt_client
-- MQTT连接状态
local mqtt_connected = false

local function ctwing_iot()
    local mobile_signal
    sys.waitUntil("IP_READY_IND",30000)
    mobile_signal=mobile.status()
    log.info("SIM SIGNAL",mobile_signal)
    --创建一个MQTT客户端
    log.info("MQTT CONNECTTING...")
    mqtt_client = mqtt.create( nil ,"mqtt.ctwing.cn", 1883)
    mqtt_client:auth(device_id,user_name,password)--三元组配置
    mqtt_client:keepalive(240)--设置心跳包间隔
    mqtt_client:autoreconn(true, 3000) -- 自动重连机制
    mqtt_client:on(function(mqtt_client, event, data, payload)                --[[
                event可能出现的值有
                conack -- 服务器鉴权完成,mqtt连接已经建立, 可以订阅和发布数据了,没有附加数据
                recv   -- 接收到数据,由服务器下发, data为topic值(string), payload为业务数据(string).metas是元数据(table), 一般不处理.
                        -- metas包含以下内容
                        -- qos 取值范围0,1,2
                        -- retain 取值范围 0,1
                        -- dup 取值范围 0,1
                sent   -- 发送完成, qos0会马上通知, qos1/qos2会在服务器应答会回调, data为消息id
                disconnect -- 服务器断开连接,网络问题或服务器踢了客户端,例如clientId重复,超时未上报业务数据
                ]]
                -- 用户自定义代码
                log.info("mqtt", "event", event, mqtt_client, data, payload)
                if event == "conack" then--
                    log.info("MQTT CONNECTTED")
                    sys.publish("mqtt_conack")
                    mqtt_client:subscribe(ctwing_iot_subscribetopic)--主题订阅
                    log.info("Successfully subscribed to mqtt")

                elseif event == "recv" then
                    log.info("mqtt", "downlink", "topic", data, "payload", payload)
                    sys.publish("mqtt_payload", data, payload)

                elseif event == "sent" then --异步发送成功信号
                    log.info("mqtt", "sent", "pkgid", data)

                end
                end)
                -- 自动处理重连, 除非自行关闭
    mqtt_client:connect()
    sys.waitUntil("mqtt_conack")
    while true do
                    --演示等待其他task发送过来的上报信息
                local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 300000)
                local date="test date"--测试数据
                local qos=1
                if ret then
                    -- 提供关闭本while循环的途径, 不需要可以注释掉
                    if topic == "close" then break end
                    mqtt_client:publish("z1223",date,qos)-- QOS0不带puback, QOS1是带puback的
                    log.info("发送成功")
                end
                    -- 如果没有其他task上报, 可以写个空等待
                    --sys.wait(60000000)
    end

    mqtt_client:close()
    mqtt_client = nil
end

sys.taskInit(ctwing_iot)
sys.taskInit(function()
    while true do
        sys.wait(60000)
        if mqtt_client and mqtt_client:ready() then
            sys.publish("mqtt_pub",ctwing_iot_subscribetopic.z1223,1)
        end
    end
end)


return ctwing
