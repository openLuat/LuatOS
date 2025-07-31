--[[
@module  mqtts_receiver
@summary mqtts cient数据接收处理应用功能模块 
@version 1.0
@date    2025.07.29
@author  朱天华
@usage
本文件为mqtts client 数据接收应用功能模块，核心业务逻辑为：
处理接收到的publish数据，同时将数据发送给其他应用功能模块做进一步处理；

本文件的对外接口有2个：
1、mqtts_receiver.proc(topic, payload, metas)：publish数据处理入口，在mqtts_main.lua中调用；
2、sys.publish("RECV_DATA_FROM_SERVER", "recv from mqtt ssl server: ", topic, payload)：
   将接收到的publish中的topic和payload数据通过消息"RECV_DATA_FROM_SERVER"发布出去；
   需要处理数据的应用功能模块订阅处理此消息即可，本demo项目中uart_app.lua中订阅处理了本消息；
]]

local mqtts_receiver = {}



--[[
处理接收到的publish数据

@api mqtts_receiver.proc(topic, payload, metas)

@param1 topic string
表示publish主题

@param2 payload string
表示publish数据负载

@param2 payload string
表示publish数据负载

@param3 metas table
表示publish报文的一些参数；格式如下：
{
    qos: number类型，取值范围0,1,2
    retain：number类型，取值范围0,1
    dup：number类型，取值范围0,1
    message_id: number类型
}

@return1 result nil

@usage

mqtts_receiver.proc(topic, payload, metas)
]]
function mqtts_receiver.proc(topic, payload, metas)

    log.info("mqtts_receiver.proc", topic, payload:len(), json.encode(metas))

    -- 接收到数据，通知网络环境检测看门狗功能模块进行喂狗
    sys.publish("FEED_NETWORK_WATCHDOG") 

    -- 将topic和payload通过"RECV_DATA_FROM_SERVER"消息publish出去，给其他应用模块处理
    sys.publish("RECV_DATA_FROM_SERVER", "recv from mqtt ssl server: ", topic, payload)

    -- 也可以直接在此处编写代码，处理topic和payload   
end

return mqtts_receiver
