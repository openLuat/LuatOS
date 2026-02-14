--[[
@module  lora2_sender
@summary lora数据发送应用功能模块
@version 1.0
@date    2025.11.23
@author  王世豪
@usage
本文件为lora数据发送应用功能模块，核心业务逻辑为：
1、订阅"SEND_DATA_REQ"消息，将其他应用模块需要发送的数据存储到队列send_queue中；
2、lora2_sender task接收"DEVICE_READY"、"SEND_REQ"、"TX_DONE"消息，处理队列中的数据；
    "DEVICE_READY"消息表示lora设备已初始化完成，"SEND_REQ"消息表示有新数据需要发送，"TX_DONE"消息表示数据发送完成；
4、数据发送完成后通过回调函数通知发送方。

本文件的对外接口有：
1. sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func); 订阅"SEND_DATA_REQ"消息;
    其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的数据、回调函数和回调参数一起publish出去；
]]

local lora2_sender = {}

--[[
数据发送队列，数据结构为：
{
    [1] = {data="data1", cb={func=callback_function1, para=callback_para1}},
    [2] = {data="data2", cb={func=callback_function2, para=callback_para2}},
}
data: 要发送的数据，string类型，必须存在；
cb.func: 数据发送结果的用户回调函数，可以不存在；
cb.para: 数据发送结果的用户回调函数参数，可以不存在；
]]

local send_queue = {}

lora2_sender.TASK_NAME = "lora2_sender"

-- "SEND_DATA_REQ"消息的处理函数
local function send_data_req_proc_func(tag, data, cb)
    -- 将数据插入到发送队列send_queue中
    table.insert(send_queue, {data=data, cb=cb})
    -- 发送消息通知 lora sender task，有新数据等待发送
    sys.sendMsg(lora2_sender.TASK_NAME, "LORA_EVENT", "SEND_REQ") 
    log.info("队列", #send_queue)
end

-- 按照顺序发送send_queue中的数据
-- 发送请求提交后，返回当前正在发送的数据项，等待发送完成事件
-- 如果设备未初始化，则通知回调函数发送失败，并继续处理下一条
local function send_item_func(lora_device)
    local item
    -- 如果发送队列中有数据等待发送
    while #send_queue>0 do
        -- 取出来第一条数据赋值给item
        -- 同时从队列send_queue中删除这一条数据
        item = table.remove(send_queue, 1)

        -- 检查设备是否初始化
        if not lora_device then
            log.error("lora2_sender", "设备未初始化")
            -- 通知回调函数发送失败
            if item.cb and item.cb.func then
                item.cb.func(false, item.cb.para)
            end
            return nil
        end
        
        -- 发送数据
        lora_device:send(item.data)
        
        -- 返回当前发送项，等待发送完成"TX_DONE"事件
        return item
    end
    return nil
end

-- 处理发送结果的回调函数
local function send_item_cbfunc(item, result)
    if item then
        -- 如果当前发送的数据有用户回调函数，则执行用户回调函数
        if item.cb and item.cb.func then
            item.cb.func(result, item.cb.para)
        end
    end
end

-- lora client sender的任务处理函数
local function lora2_sender_task_func()
    local lora_device
    local send_item = nil
    local msg

    while true do
        -- 等待"LORA_EVENT"消息
        msg = sys.waitMsg(lora2_sender.TASK_NAME, "LORA_EVENT")
        log.info("lora2_sender", "收到消息", msg[2])
        
        -- 设备就绪事件
        if msg[2] == "DEVICE_READY" then
            lora_device = msg[3]
            -- 如果当前没有正在发送的数据，则开始发送队列中的数据
            if lora_device and not send_item then
                send_item = send_item_func(lora_device)
            end

        -- 发送数据请求
        elseif msg[2] == "SEND_REQ" then
            -- 如果当前没有正在发送的数据，则开始发送队列中的数据
            if lora_device and not send_item then
                send_item = send_item_func(lora_device)
            end
        -- 发送完成事件
        elseif msg[2] == "TX_DONE" then
            -- 通知回调函数发送成功
            send_item_cbfunc(send_item, true)
            -- 清空当前发送项
            send_item = nil
            -- 继续处理队列中的下一条数据
            send_item = send_item_func(lora_device)
        end
    end
end

-- 订阅"SEND_DATA_REQ"消息；
-- 其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的数据以及回调函数和回调参数一起publish出去；
-- 本demo项目中uart_app.lua中publish了这个消息；
sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)

--创建并且启动一个task
--运行这个task的处理函数lora2_sender_task_func
sys.taskInitEx(lora2_sender_task_func, lora2_sender.TASK_NAME)

return lora2_sender