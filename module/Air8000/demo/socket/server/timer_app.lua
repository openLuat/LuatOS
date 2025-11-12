--[[
@module  timer_app
@summary 定时器应用功能模块 
@version 1.0
@date    2025.09.15
@author  王世豪
@usage
本文件为定时器应用功能模块，核心业务逻辑为：
创建一个5秒的循环定时器，每次产生一段数据，通知TCP或UDP server进行处理；

本文件的对外接口有一个：
1、sys.publish("SEND_DATA_REQ", "timer", data, ip, port, {func=send_data_cbfunc, para="timer"..data})，通过publish通知TCP或UDP server数据发送功能模块发送data数据;
    数据发送结果通过执行回调函数send_data_cbfunc通知本功能模块；
]]

local config = {
    enable_udp = true,            -- 是否启用UDP发送
    enable_tcp = false             -- 是否启用TCP发送
}

local data = 1

local udp_server_receiver = require "udp_server_receiver"

-- 数据发送结果回调函数
-- result：发送结果，true为发送成功，false为发送失败
-- para：回调参数，sys.publish("SEND_DATA_REQ", "timer", data, ip, port, {func=send_data_cbfunc, para="timer"..data})中携带的para
local function send_data_cbfunc(result, para)
    log.info("send_data_cbfunc", result, para)
    -- 无论上一次发送成功还是失败，启动一个5秒的定时器，5秒后发送下次数据
    sys.timerStart(send_data_req_timer_cbfunc, 5000)
end

-- 定时器回调函数
function send_data_req_timer_cbfunc()
    -- 发布消息"SEND_DATA_REQ"
    -- 携带的第一个参数"timer"表示是定时器应用模块发布的消息
    -- 携带的第二个参数data为要发送的原始数据
    -- 携带的第三个参数client_ip为目标IP地址
    -- 携带的第四个参数port为目标端口号
    -- 携带的第五个参数cb为发送结果回调(可以为空，如果为空，表示不关心TCP或UDP server发送数据成功还是失败)，其中：
    --       cb.func为回调函数(可以为空，如果为空，表示不关心TCP或UDP server发送数据成功还是失败)
    --       cb.para为回调函数的第二个参数(可以为空)，回调函数的第一个参数为发送结果(true表示成功，false表示失败)

    -- UDP发送处理
    if config.enable_udp then
        -- 获取客户端信息
        local client_info = udp_server_receiver.get_client_info()
        
        -- 检查是否有客户端IP和端口
        if client_info.ip and client_info.port then
            -- 使用记录的客户端信息发送
            sys.publish("SEND_DATA_REQ", "timer", data, client_info.ip, client_info.port, {func=send_data_cbfunc, para="udp_timer"..data})
        else
            -- 未收到过客户端数据，提示错误
            log.error("timer_app", "尚未收到客户端数据, 无法确定目标IP和端口")
            sys.timerStart(send_data_req_timer_cbfunc, 5000)
        end
        -- TCP发送处理
    elseif config.enable_tcp then
        -- 当前TCP server与client是一对一连接，publish的消息可忽略ip和port参数
        sys.publish("SEND_DATA_REQ", "timer", data, {func=send_data_cbfunc, para="tcp_timer"..data})  
    end

    data = data + 1
    log.info("send_data_req_timer_cbfunc", data)
end

-- 启动一个5秒的单次定时器
-- 时间到达后，执行一次send_data_req_timer_cbfunc函数
sys.timerStart(send_data_req_timer_cbfunc, 5000)
