--[[
@module  websocket_sender
@summary WebSocket client数据发送应用功能模块
@version 1.0
@date    2025.08.25
@author  陈媛媛
@usage
本文件为WebSocket client 数据发送应用功能模块，核心业务逻辑为：
1、sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)订阅"SEND_DATA_REQ"消息，将其他应用模块需要发送的数据存储到队列send_queue中；
2、websocket sender task接收"CONNECT_OK"、"SEND_REQ"、"SEND_OK"三种类型的"WEBSOCKET_EVENT"消息，遍历队列send_queue，逐条发送数据到server；
3、websocket sender task接收"DISCONNECTED"类型的"WEBSOCKET_EVENT"消息，丢弃掉队列send_queue中未发送的数据；
4、任何一条数据无论发送成功还是失败，只要这条数据有回调函数，都会通过回调函数通知数据发送方；

本文件的对外接口有1个：
1、sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)：订阅"SEND_DATA_REQ"消息；
   其他应用模块如果需要发送数据，直接sys.publish这个消息即可，将需要发送的数据以及回调函数和回调参数一起publish出去；
   本demo项目中uart_app.lua和timer_app.lua中publish了这个消息；
]]

local websocket_sender = {}

--[[
数据发送队列，数据结构为：
{
    [1] = {data="data1", cb={func=callback_function1, para=callback_para1}},
    [2] = {data="data2", cb={func=callback_function2, para=callback_para2}},
    [3] = {data="data3", cb={func=callback_function3, para=callback_para3}},
}
data的内容为要发送的数据，string类型，必须存在；
cb.func的内容为数据发送结果的用户回调函数，可以不存在；
cb.para的内容为数据发送结果的用户回调函数的回调参数，可以不存在；
]]

local send_queue = {}

-- WebSocket client的任务名前缀
websocket_sender.TASK_NAME_PREFIX = "websocket_"

-- websocket_client_sender的任务名
websocket_sender.TASK_NAME = websocket_sender.TASK_NAME_PREFIX.."sender"

-- "SEND_DATA_REQ"消息的处理函数
local function send_data_req_proc_func(tag, data, cb)
    -- 确保data是字符串类型
    local data_str = tostring(data)
    
    -- 检查是否是"echo"命令
    if data_str == '"echo"' then
        log.info("WebSocket发送处理", "收到echo命令，发送数据")
        -- 创建JSON格式的echo响应
        local response = json.encode({
            action = "echo",
            msg = os.date("%a %Y-%m-%d %H:%M:%S") -- %a表示星期几缩写
            
        })
      
        -- 将echo响应插入到发送队列send_queue中
        table.insert(send_queue, {data=response, cb=cb})
        log.info("准备发送数据到服务器，长度", #response)
        log.info("原始数据:", response)
    else
        -- 根据tag类型输出日志
        if tag == "timer" then
            -- 对于timer数据，修改日志为"发送心跳"
            log.info("发送心跳", "长度", #data_str)
            log.info("原始数据:", data_str)
            table.insert(send_queue, {data=data_str, cb=cb})
        else
            -- 其他数据（如uart）
            log.info("准备发送数据到服务器，长度", #data_str)
            log.info("原始数据:", data_str)
            log.info("UART发送到服务器的数据包类型", type(data_str))
            log.info("转发普通数据")
            table.insert(send_queue, {data=data_str, cb=cb})
        end
    end
    
    -- 发送消息通知 websocket sender task，有新数据等待发送
    sysplus.sendMsg(websocket_sender.TASK_NAME, "WEBSOCKET_EVENT", "SEND_REQ")
end

-- 按照顺序发送send_queue中的数据
-- 如果调用send接口成功，则返回当前正在发送的数据项
-- 如果调用send接口失败，通知回调函数发送失败后，继续发送下一条数据
local function send_item(ws_client)
    local item
    -- 如果发送队列中有数据等待发送
    while #send_queue > 0 do
        -- 取出来第一条数据赋值给item
        -- 同时从队列send_queue中删除这一条数据
        item = table.remove(send_queue, 1)
        
        -- 检查WebSocket连接状态
        if not ws_client or not ws_client:ready() then
            log.warn("WebSocket发送处理", "WebSocket连接未就绪，无法发送")
            -- 如果当前发送的数据有用户回调函数，则执行用户回调函数
            if item.cb and item.cb.func then
                item.cb.func(false, item.cb.para)
            end
            -- 触发重连
            sysplus.sendMsg(websocket_sender.TASK_NAME, "WEBSOCKET_EVENT", "DISCONNECTED")
            return nil
        end

        -- send数据
        -- result表示调用send接口的同步结果，返回值有以下几种：
        -- 如果失败，返回false
        -- 如果成功，返回true
        result = ws_client:send(item.data)

        -- send接口调用成功
        if result then
            -- 根据数据内容修改日志输出
            if item.data:match("^%d+$") then -- 如果数据是纯数字（来自timer）
                log.info("wbs_sender", "发送心跳成功", "长度", #item.data)
            else
                log.info("wbs_sender", "发送成功", "长度", #item.data)
            end
            
            if item.cb and item.cb.func then
                item.cb.func(true, item.cb.para)
            end
            -- 发送成功，通知网络环境检测看门狗功能模块进行喂狗
            -- 使用来自定时器的数据作为心跳
            if item.data:match("^%d+$") then -- 如果数据是纯数字（来自timer）
                sys.publish("FEED_NETWORK_WATCHDOG")
            end
            return item
        -- send接口调用失败
        else
            log.warn("WebSocket发送处理", "数据发送失败")
            -- 如果当前发送的数据有用户回调函数，则执行用户回调函数
            if item.cb and item.cb.func then
                item.cb.func(false, item.cb.para)
            end
            -- 触发重连
            sysplus.sendMsg(websocket_sender.TASK_NAME, "WEBSOCKET_EVENT", "DISCONNECTED")
            return nil
        end
    end
    return nil
end

-- websocket client sender的任务处理函数
local function websocket_client_sender_task_func()
    local ws_client
    local send_item_obj
    local result, msg

    while true do
        -- 等待"WEBSOCKET_EVENT"消息
        msg = sysplus.waitMsg(websocket_sender.TASK_NAME, "WEBSOCKET_EVENT")
        log.info("WebSocket发送任务等待消息", msg[2], msg[3])

        -- WebSocket连接成功
        -- msg[3]表示WebSocket client对象
        if msg[2] == "CONNECT_OK" then
            ws_client = msg[3]
            log.info("WebSocket发送任务", "WebSocket连接成功")
            -- 发送send_queue中的所有数据
            while #send_queue > 0 do
                send_item_obj = send_item(ws_client)
                if not send_item_obj then
                    break
                end
            end

        -- WebSocket send数据请求
        elseif msg[2] == "SEND_REQ" then
            log.info("WebSocket发送任务", "收到发送请求")
            -- 如果WebSocket client对象存在
            if ws_client then
                send_item_obj = send_item(ws_client)
            end

        -- WebSocket send数据成功
        elseif msg[2] == "SEND_OK" then
            log.info("WebSocket发送任务", "数据发送成功")
            -- 继续发送send_queue中的数据
            send_item_obj = send_item(ws_client)

        -- WebSocket断开连接
        elseif msg[2] == "DISCONNECTED" then
            log.info("WebSocket发送任务", "WebSocket连接断开")
            -- 清空WebSocket client对象
            ws_client = nil
            -- 如果发送队列中有数据等待发送
            while #send_queue > 0 do
                -- 取出来第一条数据赋值给send_item_obj
                -- 同时从队列send_queue中删除这一条数据
                send_item_obj = table.remove(send_queue, 1)
                -- 如果当前发送的数据有用户回调函数，则执行用户回调函数
                if send_item_obj.cb and send_item_obj.cb.func then
                    send_item_obj.cb.func(false, send_item_obj.cb.para)
                end
            end
            -- 当前没有正在等待发送结果的发送项
            send_item_obj = nil
        end
    end
end

-- 订阅"SEND_DATA_REQ"消息；
sys.subscribe("SEND_DATA_REQ", send_data_req_proc_func)

--创建并且启动一个task
sysplus.taskInitEx(websocket_client_sender_task_func, websocket_sender.TASK_NAME)

return websocket_sender