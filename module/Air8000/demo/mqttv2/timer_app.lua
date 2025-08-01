--[[
@module  timer_app
@summary 定时器应用功能模块 
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为定时器应用功能模块，核心业务逻辑为：
创建一个5秒的循环定时器，每次产生一段数据，通知三个mqtt client进行处理；

本文件的对外接口有一个：
1、sys.publish("SEND_DATA_REQ", "timer", mobile.imei().."/timer/up", payload, 0, {func=send_data_cbfunc, para="timer"..payload})
   通过publish通知三路mqtt client数据发送功能模块publish数据;
   数据发送结果通过执行回调函数send_data_cbfunc通知本功能模块；
]]

local payload = 1

-- 数据发送结果回调函数
-- result：发送结果，true为发送成功，false为发送失败
-- para：回调参数，sys.publish("SEND_DATA_REQ", "timer", mobile.imei().."/timer/up", payload, 0, {func=send_data_cbfunc, para="timer"..payload})中携带的para
local function send_data_cbfunc(result, para)
    log.info("send_data_cbfunc", result, para)
    -- 无论上一次发送成功还是失败，启动一个5秒的定时器，5秒后发送下次数据
    sys.timerStart(send_data_req_timer_cbfunc, 5000)
end

-- 定时器回调函数
function send_data_req_timer_cbfunc()
    -- 发布消息"SEND_DATA_REQ"
    -- 携带的第一个参数"timer"表示是定时器应用模块发布的消息
    -- 携带的第二个参数mobile.imei().."/timer/up"为要publish的topic
    -- 携带的第三个参数payload为要publish的payload
    -- 携带的第四个参数0为publish的qos
    -- 携带的第五个参数cb为发送结果回调(可以为空，如果为空，表示不关心mqtt client发送数据成功还是失败)，其中：
    --       cb.func为回调函数(可以为空，如果为空，表示不关心mqtt client发送数据成功还是失败)
    --       cb.para为回调函数的第二个参数(可以为空)，回调函数的第一个参数为发送结果(true表示成功，false表示失败)
    sys.publish("SEND_DATA_REQ", "timer", mobile.imei().."/timer/up", payload, 0, {func=send_data_cbfunc, para="timer"..payload})
    payload = payload+1
end

-- 启动一个5秒的单次定时器
-- 时间到达后，执行一次send_data_req_timer_cbfunc函数
sys.timerStart(send_data_req_timer_cbfunc, 5000)
