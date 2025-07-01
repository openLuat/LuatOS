--[[
@module  udp_client_sender
@summary udp client socket数据发送应用功能模块 
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为udp client socket数据发送应用功能模块，核心业务逻辑为：
1、sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)订阅"SEND_DATA_REQ"消息，将其他应用模块需要发送的数据存储到队列send_queue中；
2、udp_client_main主任务调用udp_client_sender.proc接口，遍历队列send_queue，逐条发送数据到server；
3、udp client socket和server之间的连接如果出现异常，udp_client_main主任务调用udp_client_sender.exception_proc接口，丢弃掉队列send_queue中未发送的数据；
4、任何一条数据无论发送成功还是失败，只要这条数据有回调函数，都会通过回调函数通知数据发送方；

本文件的对外接口有3个：
1、sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)：订阅"SEND_DATA_REQ"消息；
   其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的数据以及回调函数和毁掉参数一起publish出去；
   本demo项目中uart_app.lua和timer_app.lua中publish了这个消息；
2、udp_client_sender.proc：数据发送应用逻辑处理入口，在udp_client_main.lua中调用；
3、udp_client_sender.exception_proc：数据发送应用逻辑异常处理入口，在udp_client_main.lua中调用；
]]

local udp_client_sender = {}

local libnet = require "libnet"

--[[
数据发送队列，数据结构为：
{
    [1] = {data="data1", cb={func=callback_function1, para=callback_para1}},
    [2] = {data="data2", cb={func=callback_function2, para=callback_para2}},
}
data的内容为真正要发送的数据，必须存在；
func的内容为数据发送结果的用户回调函数，可以不存在
para的内容为数据发送结果的用户回调函数的回调参数，可以不存在；
]]
local send_queue = {}

-- udp_client_main的任务名
udp_client_sender.TASK_NAME = "udp_client_main"

-- "SEND_DATA_REQ"消息的处理函数
local function send_data_req_proc_func(tag, data, cb)
    -- 将原始数据增加前缀，然后插入到发送队列send_queue中
    table.insert(send_queue, {data="send from "..tag..": "..data, cb=cb})
    -- 通知udp_client_main主任务有数据需要发送
    -- udp_client_main主任务如果处在libnet.wait调用的阻塞等待状态，就会退出阻塞状态
    sysplus.sendMsg(udp_client_sender.TASK_NAME, socket.EVENT, 0)
end

-- 数据发送应用逻辑处理入口
function udp_client_sender.proc(task_name, socket_client)
    local send_item
    local result, buff_full

    -- 遍历数据发送队列send_queue
    while #send_queue>0 do
        -- 取出来第一条数据赋值给send_item
        -- 同时从队列send_queue中删除这一条数据
        send_item = table.remove(send_queue,1)

        -- 发送这条数据，超时时间15秒钟
        result, buff_full = libnet.tx(task_name, 15000, socket_client, send_item.data)

        -- 发送失败
        if not result then
            log.error("udp_client_sender.proc", "libnet.tx error")

            -- 如果当前发送的数据有用户回调函数，则执行用户回调函数
            if send_item.cb and send_item.cb.func then
                send_item.cb.func(false, send_item.cb.para)
            end

            return false
        end

        -- 如果内核固件中缓冲区满了，则将send_item再次插入到send_queue的队首位置，等待下次尝试发送
        if buff_full then
            log.error("udp_client_sender.proc", "buffer is full, wait for the next time")
            table.insert(send_queue, 1, send_item)
            return true
        end

        log.info("udp_client_sender.proc", "send success")
        -- 发送成功，如果当前发送的数据有用户回调函数，则执行用户回调函数
        if send_item.cb and send_item.cb.func then
            send_item.cb.func(true, send_item.cb.para)
        end
    end

    return true
end

-- 数据发送应用逻辑异常处理入口
function udp_client_sender.exception_proc()
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
-- 其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的数据以及回调函数和毁掉参数一起publish出去；
-- 本demo项目中uart_app.lua和timer_app.lua中publish了这个消息；
sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)

return udp_client_sender
