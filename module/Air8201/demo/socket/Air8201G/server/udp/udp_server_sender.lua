--[[
@module  udp_server_sender
@summary udp server socket数据发送应用功能模块 
@version 1.0
@date    2025.11.15
@author  王世豪
@usage
本文件为udp server socket数据发送应用功能模块，核心业务逻辑为：
1、sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)订阅"SEND_DATA_REQ"消息，将其他应用模块需要发送的数据存储到队列send_queue中；
2、udp_server_main主任务调用udp_server_sender.proc接口，遍历队列send_queue，逐条发送数据到client；
3、udp server socket如果出现异常，udp_server_main主任务调用udp_server_sender.exception_proc接口，丢弃掉队列send_queue中未发送的数据；
4、任何一条数据无论发送成功还是失败，只要这条数据有回调函数，都会通过回调函数通知数据发送方；

本文件的对外接口有3个：
1、sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)：订阅"SEND_DATA_REQ"消息；
    其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的数据、目标IP、目标端口以及回调函数和回调参数一起publish出去；
2、udp_server_sender.proc：数据发送应用逻辑处理入口，在udp_server_main.lua中调用；
3、udp_server_sender.exception_proc：数据发送应用逻辑异常处理入口，在udp_server_main.lua中调用；
]]

local udp_server_sender = {}

--[[
数据发送队列，数据结构为：
{
    [1] = {data="data1", ip="127.0.0.1", port=8888, cb={func=callback_function1, para=callback_para1}},
    [2] = {data="data2", ip="127.0.0.1", port=8888, cb={func=callback_function2, para=callback_para2}},
}
data的内容为真正要发送的数据，必须存在；
ip的内容为目标IP，必须存在；
port的内容为目标端口，必须存在；
func的内容为数据发送结果的用户回调函数，可以不存在
para的内容为数据发送结果的用户回调函数的回调参数，可以不存在；
]]
local send_queue = {}

-- "SEND_DATA_REQ"消息的处理函数
local function send_data_req_proc_func(tag, data, ip, port, cb)
    -- 将原始数据增加前缀，然后插入到发送队列send_queue中
    table.insert(send_queue, {data="send from "..tag..": "..data, ip=ip, port=port, cb=cb}) 
    log.info("send_queue", #send_queue)
    -- 通知主任务：有数据待发送，唤醒阻塞
    sys.publish("udp_server", "SEND_READY", nil, nil)  -- 后两个参数为 remote_ip 和 remote_port，这里置为 nil
end

--[[
检查udp server是否需要发送数据，如果需要发送数据，读取并且发送完发送队列中的所有数据

@api udp_server_sender.proc(udp_server)

@param 
表示由udpsrv.create接口创建的udp_server对象；
必须传入，不允许为空或者nil；

@return1 result bool
表示处理结果，成功为true，失败为false

@usage
udp_server_sender.proc(udp_server)
]]
function udp_server_sender.proc(udp_server)
    local send_item
    local result

    -- 遍历数据发送队列send_queue
    while #send_queue>0 do
        -- 取出来第一条数据赋值给send_item
        -- 同时从队列send_queue中删除这一条数据
        send_item = table.remove(send_queue,1)

        result = udp_server:send(send_item.data, send_item.ip, send_item.port)

        -- 发送失败
        if not result then
            log.error("udp_server_sender.proc", "udp_server:send error")

            -- 如果当前发送的数据有用户回调函数，则执行用户回调函数
            if send_item.cb and send_item.cb.func then
                send_item.cb.func(false, send_item.cb.para)
            end

            return false
        end

        log.info("udp_server_sender.proc", "send success", send_item.ip, send_item.port)
        -- 发送成功，如果当前发送的数据有用户回调函数，则执行用户回调函数
        if send_item.cb and send_item.cb.func then
            send_item.cb.func(true, send_item.cb.para)
        end
    end

    return true
end

-- UDP服务器出现异常时，清空等待发送的数据，并且执行发送方的回调函数
function udp_server_sender.exception_proc()
    -- 遍历数据发送队列send_queue
    while #send_queue>0 do
        local send_item = table.remove(send_queue,1)
        -- 发送失败，如果当前发送的数据有用户回调函数，则执行用户回调函数
        if send_item.cb and send_item.cb.func then
            send_item.cb.func(false, send_item.cb.para)
        end
    end
end

-- 订阅"SEND_DATA_REQ"消息；
-- 其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的数据以及回调函数和回调参数一起publish出去；
-- 参数格式: sys.publish("SEND_DATA_REQ", tag, data, ip, port, cb)
-- tag: 发送方标识, data: 要发送的数据, ip: 目标IP, port: 目标端口, cb: 回调函数
-- 例如: sys.publish("SEND_DATA_REQ", "app1", "hello client", "192.168.1.100", 50000)
-- 本demo项目中uart_app.lua和timer_app.lua中publish了这个消息；
sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)

return udp_server_sender
