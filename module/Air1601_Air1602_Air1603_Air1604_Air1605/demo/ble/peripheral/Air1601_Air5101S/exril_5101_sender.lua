--[[
@module  exril_5101_sender
@summary BLE 数据发送应用功能模块
@version 1.0
@date    2026.04.14
@author  王世豪
@usage
本文件为BLE 数据发送应用功能模块，核心业务逻辑为：
1. 订阅"SEND_DATA_REQ"消息，将其他应用模块需要发送的数据存储到队列send_queue中
2. BLE sender task接收"CONNECTED"、"SEND_REQ"两种类型的"BLE_EVENT"消息，处理队列中的数据
3. 接收"DISCONNECTED"类型的"BLE_EVENT"消息，清空发送队列
4. 数据发送完成后通过回调函数通知发送方

本文件的对外接口有1个：
1. sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func); 订阅"SEND_DATA_REQ"消息
    其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的数据、回调函数和回调参数一起publish出去
]]

local exril_5101 = require("exril_5101")

-- 定义模块表
local exril_5101_sender = {}

-- 数据发送队列
local send_queue = {}

-- BLE连接状态
local ble_connected = false

-- BLE sender的任务名前缀
exril_5101_sender.TASK_NAME_PREFIX = "exril_5101_"

-- BLE sender的任务名
exril_5101_sender.TASK_NAME = exril_5101_sender.TASK_NAME_PREFIX.."sender"

-- 当前正在发送的数据项
local current_send_item = nil

-- "SEND_DATA_REQ"消息的处理函数
local function send_data_req_proc_func(data, cb)
    -- 将数据插入到发送队列send_queue中
    table.insert(send_queue, {
        data = data,
        cb = cb,
    })
    -- 发送消息通知 BLE sender task，有新数据等待发送
    -- msg[3] 传递当前连接状态
    sys.sendMsg(exril_5101_sender.TASK_NAME, "BLE_EVENT", "SEND_REQ", ble_connected)
end

-- 处理发送结果的回调函数
local function send_item_cbfunc(result)
    if current_send_item then
        -- 如果当前发送的数据有用户回调函数，则执行用户回调函数
        if current_send_item.cb and current_send_item.cb.func then
            current_send_item.cb.func(result, current_send_item.cb.para)
        end
    end
end

-- 按顺序发送send_queue中的数据
-- 如果发送成功，则返回当前正在发送的数据项
-- 如果发送失败，通知回调函数发送失败后，继续发送下一条数据
local function send_item_func()
    -- 如果发送队列中有数据等待发送
    while #send_queue>0 do
        -- 取出来第一条数据赋值给current_send_item
        -- 同时从队列send_queue中删除这一条数据
        current_send_item = table.remove(send_queue, 1)

        -- 发送数据
        local result = exril_5101.send(current_send_item.data)
        
        -- 发送接口调用成功
        if result then
            -- 发送成功，执行回调
            send_item_cbfunc(true)
            -- 保存当前发送项，等待发送完成
            return
        -- 发送接口调用失败
        else
            -- 如果当前发送的数据有用户回调函数，则执行用户回调函数
            if current_send_item.cb and current_send_item.cb.func then
                current_send_item.cb.func(false, current_send_item.cb.para)
            end
        end
    end
end

-- BLE sender的任务处理函数
local function exril_5101_sender_task_func()
    local msg

    while true do
        msg = sys.waitMsg(exril_5101_sender.TASK_NAME, "BLE_EVENT")
        -- 蓝牙连接成功
        -- msg[3]表示连接状态
        if msg[2] == "CONNECTED" then
            -- 更新连接状态
            ble_connected = true
            -- 发布BLE连接状态消息
            sys.publish("BLE_CONNECT_STATUS", true)
            
            -- 发送send_queue中的数据
            send_item_func()
            
        -- BLE发送数据请求
        elseif msg[2] == "SEND_REQ" then
            -- 如果连接状态，发送send_queue中的数据
            if msg[3] then
                send_item_func()
            end
        elseif msg[2] == "DISCONNECTED" then
            -- 更新连接状态
            ble_connected = false
            -- 发布BLE连接状态消息
            sys.publish("BLE_CONNECT_STATUS", false)
            
            -- 清空当前正在发送的数据项
            current_send_item = nil
            -- 如果存在正在等待发送结果的发送项，执行回调函数通知发送方失败
            send_item_cbfunc(false)
            -- 如果发送队列中有数据等待发送
            while #send_queue>0 do
                -- 取出来第一条数据赋值给current_send_item
                -- 同时从队列send_queue中删除这一条数据
                current_send_item = table.remove(send_queue, 1)
                -- 执行回调函数通知发送方失败
                send_item_cbfunc(false)
            end
            -- 当前没有正在等待发送结果的发送项
            current_send_item = nil
        end
    end
end

-- 订阅"SEND_DATA_REQ"消息
-- 其他应用模块如果需要发送数据，直接sys.publish这个消息即可
-- 参数: data(数据), cb(回调函数和参数)
sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)

-- 启动任务
sys.taskInitEx(exril_5101_sender_task_func, exril_5101_sender.TASK_NAME)

return exril_5101_sender
