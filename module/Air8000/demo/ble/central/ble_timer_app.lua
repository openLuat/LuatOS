--[[
@module  ble_timer_app
@summary 定时器应用功能模块
@version 1.0
@date    2025.08.20
@author  王世豪
@usage
本文件为定时器应用功能模块，核心业务逻辑为：
创建两个独立的5秒循环定时器，一个用于定时读取外围设备特征值UUID数据，一个用于定时向外围设备特征值UUID发送数据；

本文件的对外接口有2个：
1、sys.publish("SEND_DATA_REQ", "timer", server_uuid, write_char_uuid, data, {func = send_data_cbfunc, para="timer"..data}),发布SEND_DATA_REQ消息，在ble_client_sender文件中处理,携带的参数为：
    -- 发布消息"SEND_DATA_REQ"
    -- 携带的第一个参数"timer"表示是定时器应用模块发布的消息
    -- 携带的第二个参数server_uuid表示要发送的服务UUID
    -- 携带的第三个参数write_char_uuid表示要发送的特征值UUID
    -- 携带的第四个参数data表示要发送的数据
    -- 携带的第五个参数cb为发送结果回调(可以为空，如果为空，表示不关心ble client 发送数据成功还是失败)，其中：
    --   cb.func为回调函数(可以为空，如果为空，表示不关心ble client发送数据成功还是失败)
    --   cb.para为回调函数的第二个参数(可以为空)，回调函数的第一个参数为发送结果(true表示成功，false表示失败)

2、sys.sendMsg(BLE_TASK_NAME,"BLE_EVENT","READ_REQ",server_uuid,read_char_uuid), 发送读取外围设备特征值UUID数据请求，在ble_client_main文件中处理，携带的参数为：
    -- msg[2]: "READ_REQ" --消息类型
    -- msg[3]: server_uuid --服务UUID
    -- msg[4]: read_char_uuid --特征值UUID
]]

local BLE_TASK_NAME = "ble_client_main"
local server_uuid = "FA00"
local write_char_uuid = "EA02"
local read_char_uuid = "EA03"
local data = "1234"

-- 数据发送结果回调函数
-- result：发送结果，true为发送成功，false为发送失败
-- para：回调参数，sys.publish("SEND_DATA_REQ", "timer", "FA00", "EA02", data, {func=send_data_cbfunc, para="timer"..data})中携带的para
local function send_data_cbfunc(result, para)
    log.info("send_data_cbfunc", result, para)
end

-- 定时器回调函数
function send_data_req_timer_cbfunc()
    -- 发布消息"SEND_DATA_REQ"
    -- 携带的第一个参数"timer"表示是定时器应用模块发布的消息
    -- 携带的第二个参数server_uuid表示要发送的服务UUID
    -- 携带的第三个参数char_uuid表示要发送的特征值UUID
    -- 携带的第四个参数data表示要发送的数据
    -- 携带的第五个参数cb为发送结果回调(可以为空，如果为空，表示不关心ble client 发送数据成功还是失败)，其中：
    --       cb.func为回调函数(可以为空，如果为空，表示不关心ble client发送数据成功还是失败)
    --       cb.para为回调函数的第二个参数(可以为空)，回调函数的第一个参数为发送结果(true表示成功，false表示失败)
    sys.publish("SEND_DATA_REQ", "timer", server_uuid, write_char_uuid, data, {func = send_data_cbfunc, para="timer"..data})
end

local function read_data_req_timer_cbfunc()
    -- msg[2]: "READ_REQ" --消息类型
    -- msg[3]: server_uuid --服务UUID
    -- msg[4]: read_char_uuid --特征值UUID
    sys.sendMsg(BLE_TASK_NAME,"BLE_EVENT","READ_REQ",server_uuid,read_char_uuid)
end

local function ble_connect_status_handler(status)
    if status then
        -- 蓝牙连接成功，启动定时器
        -- 启动5秒的循环定时器用于发送数据
        sys.timerLoopStart(send_data_req_timer_cbfunc, 5000)
        log.info("TIMER_APP", "已启动发送数据循环定时器，间隔: 5000ms")

        -- 启动5秒的循环定时器用于读取数据
        sys.timerLoopStart(read_data_req_timer_cbfunc, 5000)
        log.info("TIMER_APP", "已启动读取数据循环定时器，间隔: 5000ms")
    else
        -- 蓝牙断开连接，停止定时器
        sys.timerStop(send_data_req_timer_cbfunc)
        log.info("TIMER_APP", "已停止发送数据循环定时器")

        sys.timerStop(read_data_req_timer_cbfunc)
        log.info("TIMER_APP", "已停止读取数据循环定时器")
    end
end

-- 订阅BLE_CONNECT_STATUS事件
sys.subscribe("BLE_CONNECT_STATUS", ble_connect_status_handler)