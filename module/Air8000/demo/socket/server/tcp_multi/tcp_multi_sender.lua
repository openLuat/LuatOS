--[[
@module  tcp_multi_sender
@summary tcp server socket数据发送应用功能模块(一对多)
@version 1.0
@date    2026.08.02
@author  王世豪
@usage
本文件为tcp server socket数据发送应用功能模块(一对多版本)，核心业务逻辑为：
1、sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)订阅"SEND_DATA_REQ"消息；
2、收到发送请求后，直接遍历clients列表，通过socket.tx向所有client广播数据；
3、也提供send_to(client, data)单播接口，向指定client发送数据；
4、tcp server socket如果出现异常，tcp_multi_main主任务调用exception_proc接口做异常处理；

本文件的对外接口有4个：
1、sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)：订阅"SEND_DATA_REQ"消息；
    其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的数据以及回调函数和回调参数一起publish出去；
    本demo项目中uart_app.lua和timer_app.lua中publish了这个消息；
2、tcp_multi_sender.proc：兼容保留，一对多场景下广播由消息订阅直接完成；
3、tcp_multi_sender.send_to：向指定client单播发送数据；
4、tcp_multi_sender.exception_proc：兼容保留，一对多场景下无队列需要清空；
]]

local tcp_multi_sender = {}

-- 已连接client列表，由tcp_multi_main.lua注入，结构为{ [1]=client_netc, [2]=client_netc, ... }
tcp_multi_sender.clients = {}

-- tcp_multi_main的任务名
tcp_multi_sender.TASK_NAME = "tcp_multi_main"

--[[
"SEND_DATA_REQ"消息的处理函数
收到发送请求后，直接遍历clients列表广播

@param1 tag string
消息来源标识，例如"uart"、"timer"，会作为数据前缀使用；

@param2 data string
需要发送的原始数据；

@param3 cb table
发送结果的用户回调函数及参数，可以为空；
格式：{func=callback_function, para=callback_para}
cb.func收到两个参数：result(true成功/false失败)、cb.para；
]]
local function send_data_req_proc_func(tag, data, cb)
    local msg = "send from "..tag..": "..data

    -- 无client连接时直接回调失败
    if #tcp_multi_sender.clients == 0 then
        log.warn("tcp_multi_sender", "无client连接，丢弃数据")
        if cb and cb.func then
            cb.func(false, cb.para)
        end
        return
    end

    -- 向所有client广播，倒序遍历方便处理断开的client
    local send_ok = false
    for i = #tcp_multi_sender.clients, 1, -1 do
        local client = tcp_multi_sender.clients[i]
        -- 使用socket.tx非阻塞发送，不使用libnet.tx
        -- 因为accept派生的client走回调模式，没有task_name，libnet.tx会等待task消息导致超时
        local succ, buff_full = socket.tx(client, msg)
        if succ and not buff_full then
            send_ok = true
        elseif not succ then
            -- 发送失败，client可能已断开，由client_event_cb的CLOSED事件兜底清理
            log.error("tcp_multi_sender", "发送失败，client可能断开", i)
        elseif buff_full then
            -- 内核缓冲区满，丢弃本条数据
            log.warn("tcp_multi_sender", "缓冲区满，丢弃数据", i)
        end
    end

    -- 只要有一条client发送成功，就认为发送成功
    if cb and cb.func then
        cb.func(send_ok, cb.para)
    end
end

--[[
数据发送应用逻辑处理入口（兼容保留）
一对多场景下，数据广播在"SEND_DATA_REQ"消息订阅中直接完成，本接口不再需要实现发送逻辑

@api tcp_multi_sender.proc()
]]
function tcp_multi_sender.proc()
    return true
end

--[[
向指定client单播发送数据

@api tcp_multi_sender.send_to(client, data)

@param1 client userdata or lightuserdata
表示由socket.accept接口派生的client socket对象；

@param2 data string
需要发送的数据；

@return1 succ bool
发送是否成功
]]
function tcp_multi_sender.send_to(client, data)
    if not client then
        return false
    end
    return socket.tx(client, data)
end

--[[
socket server连接出现异常时的处理（兼容保留）
一对多场景下无发送队列需要清空，本接口为空实现

@api tcp_multi_sender.exception_proc()

@usage
tcp_multi_sender.exception_proc()
]]
function tcp_multi_sender.exception_proc()
end

-- 订阅"SEND_DATA_REQ"消息；
-- 其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的数据以及回调函数和回调参数一起publish出去；
-- 本demo项目中uart_app.lua和timer_app.lua中publish了这个消息；
sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)

return tcp_multi_sender
