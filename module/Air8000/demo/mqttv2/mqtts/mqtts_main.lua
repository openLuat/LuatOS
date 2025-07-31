--[[
@module  mqtts_main
@summary mqtts client 主应用功能模块 
@version 1.0
@date    2025.07.28
@author  朱天华
@usage
本文件为mqtts client 主应用功能模块，核心业务逻辑为：
1、创建一个mqtts client，连接server；
2、处理连接/订阅/取消订阅/异常逻辑，出现异常后执行重连动作；
3、调用mqtts_receiver的外部接口mqtts_receiver.proc，对接收到的publish数据进行处理；
4、调用sysplus.sendMsg接口，发送"CONNECT OK"、"PUBLISH OK"和"DISCONNECTED"三种类型的"MQTT_EVENT"消息到mqtts_sender的task，控制publish数据发送逻辑；
5、收到MQTT心跳应答后，执行sys.publish("FEED_NETWORK_WATCHDOG") 对网络环境检测看门狗功能模块进行喂狗；

本文件没有对外接口，直接在main.lua中require "mqtts_main"就可以加载运行；
]]


-- 加载mqtts client数据接收功能模块
local mqtts_receiver = require "mqtts_receiver"
-- 加载mqtts client数据发送功能模块
local mqtts_sender = require "mqtts_sender"

-- mqtts服务器地址和端口
-- 这里使用的地址和端口，仅能用作测试用途，不可商用，说不定哪一天就关闭了
-- 用户开发项目时，替换为自己的商用服务器地址和端口
local SERVER_ADDR = "airlbs.openluat.com"
local SERVER_PORT = 8883

-- mqtts_main的任务名
local TASK_NAME = mqtts_sender.TASK_NAME_PREFIX.."main"

-- mqtt主题的前缀：IMEI号
local TOPIC_PREFIX = mobile.imei()

-- mqtts client的事件回调函数
local function mqtts_client_event_cbfunc(mqtt_client, event, data, payload, metas)
    log.info("mqtts_client_event_cbfunc", mqtt_client, event, data, payload, json.encode(metas))

    -- mqtt连接成功
    if event == "conack" then
        sysplus.sendMsg(TASK_NAME, "MQTT_EVENT", "CONNECT", true)
        -- 订阅单主题
        -- 第二个参数表示qos，取值范围为0,1,2，如果不设置，默认为0
        if not mqtt_client:subscribe(TOPIC_PREFIX .. "/down") then
            sysplus.sendMsg(TASK_NAME, "MQTT_EVENT", "SUBSCRIBE", false, -1)
        end
        -- 订阅多主题，如果有需要，打开注释
        -- 表中的每一个订阅主题的格式为[topic]=qos
        -- if not mqtt_client:subscribe(
        --         {
        --             [(TOPIC_PREFIX .. "/data"]=0,
        --             [(TOPIC_PREFIX .. "/cmd"]=1
        --         }
        -- ) then
        --     sysplus.sendMsg(TASK_NAME, "MQTT_EVENT", "SUBSCRIBE", false, -1)
        -- end

    -- 订阅结果
    -- data：订阅应答结果，true为成功，false为失败
    -- payload：number类型；成功时表示qos，取值范围为0,1,2；失败时表示失败码，一般是0x80
    elseif event == "suback" then
        -- 发送消息通知 mqtts main task
        sysplus.sendMsg(TASK_NAME, "MQTT_EVENT", "SUBSCRIBE", data, payload)
        
    -- 取消订阅成功
    elseif event == "unsuback" then
        -- 发送消息通知 mqtts main task
        sysplus.sendMsg(TASK_NAME, "MQTT_EVENT", "UNSUBSCRIBE", true)

    -- 接收到服务器下发的publish数据
    -- data：string类型，表示topic
    -- payload：string类型，表示payload
    -- metas：table类型，数据内容如下
    -- {
    --     qos: number类型，取值范围0,1,2
    --     retain：number类型，取值范围0,1
    --     dup：number类型，取值范围0,1
    --     message_id: number类型
    -- }
    elseif event == "recv" then
        -- 对接收到的publish数据处理
        mqtts_receiver.proc(data, payload, metas)

    -- 发送成功publish数据
    -- data：number类型，表示message id
    elseif event == "sent" then
        -- 发送消息通知 mqtts sender task
        sysplus.sendMsg(mqtts_sender.TASK_NAME, "MQTT_EVENT", "PUBLISH_OK", data)

    -- 服务器断开mqtt连接
    elseif event == "disconnect" then
        -- 发送消息通知 mqtts main task
        sysplus.sendMsg(TASK_NAME, "MQTT_EVENT", "DISCONNECTED", false)

    -- 收到服务器的心跳应答
    elseif event == "pong" then
        -- 接收到数据，通知网络环境检测看门狗功能模块进行喂狗
        sys.publish("FEED_NETWORK_WATCHDOG") 
	
    -- 严重异常，本地会主动断开连接
    -- data：string类型，表示具体的异常，有以下几种：
    --       "connect"：tcp连接失败
    --       "tx"：数据发送失败
    --       "conack"：mqtt connect后，服务器应答CONNACK鉴权失败，失败码为payload（number类型）
    --       "other"：其他异常
    elseif event == "error" then
        if data == "connect" or data == "conack" then
            -- 发送消息通知 mqtts main task，连接失败
            sysplus.sendMsg(TASK_NAME, "MQTT_EVENT", "CONNECT", false)
        elseif data == "other" or data == "tx" then
            -- 发送消息通知 mqtts main task，出现异常
            sysplus.sendMsg(TASK_NAME, "MQTT_EVENT", "ERROR")
        end
    end
end

-- mqtts main task 的任务处理函数
local function mqtts_client_main_task_func() 

    local mqtt_client
    local result, msg, para

    while true do
        -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
        while not socket.adapter(socket.dft()) do
            log.warn("mqtts_client_main_task_func", "wait IP_READY", socket.dft())
            -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
            -- 或者等待1秒超时退出阻塞等待状态;
            -- 注意：此处的1000毫秒超时不要修改的更长；
            -- 因为当使用libnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
            -- 当libnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
            -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
            sys.waitUntil("IP_READY", 1000)
        end

        -- 检测到了IP_READY消息
        log.info("mqtts_client_main_task_func", "recv IP_READY", socket.dft())

        -- 清空此task绑定的消息队列中的未处理的消息
        sysplus.cleanMsg(TASK_NAME)

        -- 创建mqtt client对象，ssl连接，不需要证书校验
        mqtt_client = mqtt.create(nil, SERVER_ADDR, SERVER_PORT, true)
        -- 如果创建mqtt client对象失败
        if not mqtt_client then
            log.error("mqtts_client_main_task_func", "mqtt.create error")
            goto EXCEPTION_PROC
        end

        -- 配置mqtt client对象的client id，username，password和clean session标志
        result = mqtt_client:auth(mobile.imei(), "", "", true)
        -- 如果配置失败
        if not result then
            log.error("mqtts_client_main_task_func", "mqtt_client:auth error")
            goto EXCEPTION_PROC
        end

        -- 注册mqtt client对象的事件回调函数
        mqtt_client:on(mqtts_client_event_cbfunc)

        -- 设置mqtt keepalive时间为120秒
        -- 如果没有设置，内核固件中默认为180秒
        -- 有需要的话，可以打开注释
        -- mqtt_client:keepalive(120)

        -- 设置遗嘱消息，有需要的话，可以打开注释
        -- mqtt_client:will(TOPIC_PREFIX .. "/status", "offline")

        -- 连接server
        result = mqtt_client:connect()
        -- 如果连接server失败
        if not result then
            log.error("mqtts_client_main_task_func", "mqtt_client:connect error")
            goto EXCEPTION_PROC
        end


        -- 连接、断开连接、订阅、取消订阅、异常等各种事件的处理调度逻辑
        while true do
            -- 等待"MQTT_EVENT"消息
            msg = sysplus.waitMsg(TASK_NAME, "MQTT_EVENT")
            log.info("mqtts_client_main_task_func waitMsg", msg[2], msg[3], msg[4])

            -- connect连接结果
            -- msg[3]表示连接结果，true为连接成功，false为连接失败
            if msg[2] == "CONNECT" then                
                -- mqtt连接成功
                if msg[3] then
                    log.info("mqtts_client_main_task_func", "connect success")
                    -- 通知数据发送应用模块，MQTT连接成功
                    sysplus.sendMsg(mqtts_sender.TASK_NAME, "MQTT_EVENT", "CONNECT_OK", mqtt_client)
                -- mqtt连接失败
                else
                    log.info("mqtts_client_main_task_func", "connect error")
                    -- 退出循环，发起重连
                    break
                end

            -- subscribe订阅结果
            -- msg[3]表示订阅结果，true为订阅成功，false为订阅失败
            elseif msg[2] == "SUBSCRIBE" then
                -- 订阅成功
                if msg[3] then
                    log.info("mqtts_client_main_task_func", "subscribe success", "qos: "..(msg[4] or "nil"))
                -- 订阅失败
                else
                    log.error("mqtts_client_main_task_func", "subscribe error", "code", msg[4])
                    -- 主动断开mqtt client连接
                    mqtt_client:disconnect()
                    -- 发送disconnect之后，此处延时1秒，给数据发送预留一点儿时间，发送到服务器；
                    -- 即使1秒的时间不足以发送给服务器也没关系；对服务器来说，mqtt客户端只是没有优雅的断开，不影响什么实质功能；
                    sys.wait(1000)
                    break
                end

            -- unsubscribe取消订阅成功
            elseif msg[2] == "UNSUBSCRIBE" then
                log.info("mqtts_client_main_task_func", "unsubscribe success")
            
            -- 需要主动关闭mqtt连接
            -- 用户需要主动关闭mqtt连接时，可以调用sysplus.sendMsg(TASK_NAME, "MQTT_EVENT", "CLOSE")
            elseif msg[2] == "CLOSE" then
                -- 主动断开mqtt client连接
                mqtt_client:disconnect()
                -- 发送disconnect之后，此处延时1秒，给数据发送预留一点儿时间，发送到服务器；
                -- 即使1秒的时间不足以发送给服务器也没关系；对服务器来说，mqtt客户端只是没有优雅的断开，不影响什么实质功能；
                sys.wait(1000)
                break
            
            -- 被动关闭了mqtt连接
            -- 被网络或者服务器断开了连接
            elseif msg[2] == "DISCONNECTED" then
                break
            
            -- 出现了其他异常
            elseif msg[2] == "ERROR" then
                break
            end     
        end

        -- 出现异常    
        ::EXCEPTION_PROC::

        -- 清空此task绑定的消息队列中的未处理的消息
        sysplus.cleanMsg(TASK_NAME)

        -- 通知mqtts sender数据发送应用模块的task，MQTT连接已经断开
        sysplus.sendMsg(mqtts_sender.TASK_NAME, "MQTT_EVENT", "DISCONNECTED")

        -- 如果存在mqtt client对象
        if mqtt_client then
            -- 关闭mqtt client，并且释放mqtt client对象
            mqtt_client:close()
            mqtt_client = nil
        end
        
        -- 5秒后跳转到循环体开始位置，自动发起重连
        sys.wait(5000)
    end
end

--创建并且启动一个task
--运行这个task的处理函数mqtts_client_main_task_func
sysplus.taskInitEx(mqtts_client_main_task_func, TASK_NAME)

