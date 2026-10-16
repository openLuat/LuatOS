--[[
@module  timer_app
@summary 定时器应用功能模块 
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为定时器应用功能模块，核心业务逻辑为：
创建一个5秒的循环定时器，每次产生一段数据，通知WebSocket client进行处理；

本文件的对外接口有一个：
1、sys.publish("SEND_DATA_REQ", "timer", data, {func=send_data_cbfunc, para="timer"..data})，通过publish通知WebSocket client数据发送功能模块发送data数据;
   数据发送结果通过执行回调函数send_data_cbfunc通知本功能模块；
]]

local data = 1

-- 数据发送结果回调函数
local function send_data_cbfunc(result, para)
    log.info("send_data_cbfunc", result, para)
    -- 无论上一次发送成功还是失败，启动一个5秒的定时器，5秒后发送下次数据
    sys.timerStart(send_data_req_timer_cbfunc, 5000)
end

-- 定时器回调函数
function send_data_req_timer_cbfunc()
    -- 发布消息"SEND_DATA_REQ"
    sys.publish("SEND_DATA_REQ", "timer", data, {func=send_data_cbfunc, para="timer"..data})
    data = data+1
end

-- 启动一个5秒的单次定时器
sys.timerStart(send_data_req_timer_cbfunc, 5000)