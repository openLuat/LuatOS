--[[
@module  ble_server_sender
@summary BLE server 数据发送应用功能模块
@version 1.0
@date    2025.08.29
@author  王世豪
@usage
本文件为BLE server 数据发送应用功能模块，核心业务逻辑为：
1、订阅"SEND_DATA_REQ"消息，将其他应用模块需要发送的数据存储到队列send_queue中；
2、BLE_server_sender task接收"CONNECT_OK"、"SEND_REQ"、两种类型的"BLE_EVENT"消息，处理队列中的数据；
3、接收"DISCONNECTED"类型的"BLE_EVENT"消息，清空发送队列；
4、数据发送完成后通过回调函数通知发送方。

本文件的对外接口有1个：
1. sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func); 订阅"SEND_DATA_REQ"消息;
    其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的服务UUID、特征值UUID、数据、回调函数和回调参数一起publish出去；
    本demo项目中ble_timer_app.lua中publish了这个消息；
]]

local ble_server_sender = {}

--[[
数据发送队列，数据结构为：
{
    [1] = {service_uuid="service1", char_uuid="char1", data="data1", cb={func=callback_function1, para=callback_para1}},
    [2] = {service_uuid="service2", char_uuid="char2", data="data2", cb={func=callback_function2, para=callback_para2}},
}
service_uuid: BLE服务UUID，string类型，必须存在；
char_uuid: BLE特征值UUID，string类型，必须存在；
data: 要发送的数据，string类型，必须存在；
send_type: 发送类型，string类型，可选，默认值为"write"，可选值为"notify"；
cb.func: 数据发送结果的用户回调函数，可以不存在；
cb.para: 数据发送结果的用户回调函数参数，可以不存在；
]]

local send_queue = {}

-- BLE server的任务名前缀
ble_server_sender.TASK_NAME_PREFIX = "ble_server_"

-- ble_client_sender的任务名
ble_server_sender.TASK_NAME = ble_server_sender.TASK_NAME_PREFIX.."sender"

-- "SEND_DATA_REQ"消息的处理函数
local function send_data_req_proc_func(tag, service_uuid, char_uuid, data, send_type, cb)
    -- 将数据插入到发送队列send_queue中
    table.insert(send_queue, {
        service_uuid = service_uuid, 
        char_uuid = char_uuid, 
        data = data, 
        send_type = send_type or "write",
        cb = cb,
    })
    -- 发送消息通知 BLE sender task，有新数据等待发送
    sys.sendMsg(ble_server_sender.TASK_NAME, "BLE_EVENT", "SEND_REQ")
end

-- 按照顺序发送send_queue中的数据
-- 如果发送成功，则返回当前正在发送的数据项
-- 如果发送失败，通知回调函数发送失败后，继续发送下一条数据
local function send_item_func(ble_device)
    local item
    -- 如果发送队列中有数据等待发送
    while #send_queue>0 do
        -- 取出来第一条数据赋值给item
        -- 同时从队列send_queue中删除这一条数据
        item = table.remove(send_queue, 1)

        -- 发送数据
        local params = {
            uuid_service = string.fromHex(item.service_uuid),
            uuid_characteristic = string.fromHex(item.char_uuid)
        }
        local data = item.data
        local result = false
        local send_type = string.lower(item.send_type or "write")

        -- notify方式：主动向中心设备推送数据（需中心设备先开启notify订阅）
        if send_type == "notify" then
            result = ble_device:write_notify(params, data)
            log.info("ble_server_sender", "使用notify方式发送数据")
        else -- 默认使用write方式，更新特征值数据，中心设备需要主动读取特征值获取最新数据
            result = ble_device:write_value(params, data)
            log.info("ble_server_sender", "使用write方式发送数据")
        end

        -- 发送接口调用成功
        if result then
            -- 保存当前发送项，等待写入完成通知
            return item
        -- 发送接口调用失败
        else
            -- 如果当前发送的数据有用户回调函数，则执行用户回调函数
            if item.cb and item.cb.func then
                item.cb.func(false, item.cb.para)
            end
        end
    end
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

-- BLE server sender的任务处理函数
local function ble_server_sender_task_func()
    local ble_device
    local send_item
    local result, msg

    while true do
        msg = sys.waitMsg(ble_server_sender.TASK_NAME, "BLE_EVENT")

        -- BLE连接成功
        -- msg[3]表示ble_device对象
        if msg[2] == "CONNECT_OK" then
            ble_device = msg[3]
            -- 发送send_queue中的数据
            send_item = send_item_func(ble_device)
        -- BLE发送数据请求
        elseif msg[2] == "SEND_REQ" then
            -- 如果ble_device对象存在，发送send_queue中的数据
            if ble_device then
                send_item_cbfunc(send_item, true)
                send_item = send_item_func(ble_device)
            end
        elseif msg[2] == "DISCONNECTED" then
            -- 清空ble_device对象
            ble_device = nil
            -- 如果存在正在等待发送结果的发送项，执行回调函数通知发送方失败
            send_item_cbfunc(send_item, false)
            -- 如果发送队列中有数据等待发送
            while #send_queue>0 do
                -- 取出来第一条数据赋值给send_item
                -- 同时从队列send_queue中删除这一条数据
                send_item = table.remove(send_queue,1)
                -- 执行回调函数通知发送方失败
                send_item_cbfunc(send_item, false)
            end
            -- 当前没有正在等待发送结果的发送项
            send_item = nil
        end
    end
end

-- 订阅"SEND_DATA_REQ"消息；
-- 其他应用模块如果需要发送数据，直接sys.publish这个消息即可
-- 参数: tag(标签), service_uuid(服务UUID), char_uuid(特征值UUID), data(数据), cb(回调函数和参数)
sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)

-- 启动任务
sys.taskInitEx(ble_server_sender_task_func, ble_server_sender.TASK_NAME)

return ble_server_sender