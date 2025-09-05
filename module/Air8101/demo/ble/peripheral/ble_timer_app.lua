--[[
@module  ble_timer_app
@summary 定时器应用功能模块
@version 1.0
@date    2025.08.29
@author  王世豪
@usage
本文件为定时器应用功能模块，核心业务逻辑为：
创建两个独立的循环定时器，用于定时向中心设备发送数据；

本文件的对外接口有1个：
1、sys.publish("SEND_DATA_REQ", "timer", server_uuid, write_char_uuid, data, send_type, {func = send_data_cbfunc, para="timer"..data}),发布SEND_DATA_REQ消息，在ble_client_sender文件中处理,携带的参数为：
    -- 发布消息"SEND_DATA_REQ"
    -- 携带的第一个参数"timer"表示是定时器应用模块发布的消息
    -- 携带的第二个参数server_uuid表示要发送的服务UUID
    -- 携带的第三个参数write_char_uuid表示要发送的特征值UUID
    -- 携带的第四个参数data表示要发送的数据
    -- 携带的第五个参数send_type表示发送类型，notify表示通知，write表示写入
    -- 携带的第六个参数cb为发送结果回调(可以为空，如果为空，表示不关心ble client 发送数据成功还是失败)，其中：
    --   cb.func为回调函数(可以为空，如果为空，表示不关心ble client发送数据成功还是失败)
    --   cb.para为回调函数的第二个参数(可以为空)，回调函数的第一个参数为发送结果(true表示成功，false表示失败)
]]

-- 数据发送结果回调函数
-- result：发送结果，true为发送成功，false为发送失败
-- para：回调参数，sys.publish("SEND_DATA_REQ", "timer", "FA00", "EA02", data, {func=send_data_cbfunc, para="timer"..data})中携带的para
local function send_data_cbfunc(result, para)
    log.info("send_data_cbfunc", result, para)
end

-- 定时器回调函数
function send_notify_data_timer_cbfunc()
    local notify_data = "1 " .. os.date()
    -- 发布消息"SEND_DATA_REQ"
    -- 携带的第一个参数"timer"表示是定时器应用模块发布的消息
    -- 携带的第二个参数server_uuid表示要发送的服务UUID
    -- 携带的第三个参数char_uuid表示要发送的特征值UUID
    -- 携带的第四个参数data表示要发送的数据
    -- 携带的第五个参数cb为发送结果回调(可以为空，如果为空，表示不关心ble client 发送数据成功还是失败)，其中：
    --       cb.func为回调函数(可以为空，如果为空，表示不关心ble client发送数据成功还是失败)
    --       cb.para为回调函数的第二个参数(可以为空)，回调函数的第一个参数为发送结果(true表示成功，false表示失败)
    sys.publish("SEND_DATA_REQ", "timer", config.service_uuid, config.char_uuid1, notify_data, "notify", {func = send_data_cbfunc, para="timer "..notify_data})
end

-- 定时器回调函数
function send_write_data_timer_cbfunc()
    local write_data = "2 " .. os.date()
    -- 发布消息"SEND_DATA_REQ"
    -- 携带的第一个参数"timer"表示是定时器应用模块发布的消息
    -- 携带的第二个参数server_uuid表示要发送的服务UUID
    -- 携带的第三个参数char_uuid表示要发送的特征值UUID
    -- 携带的第四个参数data表示要发送的数据
    -- 携带的第五个参数cb为发送结果回调(可以为空，如果为空，表示不关心ble client 发送数据成功还是失败)，其中：
    --       cb.func为回调函数(可以为空，如果为空，表示不关心ble client发送数据成功还是失败)
    --       cb.para为回调函数的第二个参数(可以为空)，回调函数的第一个参数为发送结果(true表示成功，false表示失败)
    sys.publish("SEND_DATA_REQ", "timer", config.service_uuid, config.char_uuid3, write_data, "write", {func = send_data_cbfunc, para="timer "..write_data})
end

-- 启动5秒的循环定时器用于通过notify方式发送数据
sys.timerLoopStart(send_notify_data_timer_cbfunc, 5000)
log.info("ble_timer_app", "已启动notify发送定时器, 间隔: 5000ms")

-- 启动6秒的循环定时器用于通过write方式发送数据
sys.timerLoopStart(send_write_data_timer_cbfunc, 6000)
log.info("ble_timer_app", "已启动write发送定时器, 间隔: 6000ms")

