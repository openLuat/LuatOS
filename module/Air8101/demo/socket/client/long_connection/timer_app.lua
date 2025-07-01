--[[
@module  timer_app
@summary 定时器应用功能模块 
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为定时器应用功能模块，核心业务逻辑为：
创建一个5秒的循环定时器，每次产生一段数据，通知四个socket client进行处理；

本文件的对外接口有一个：
1、sys.publish("SEND_DATA_REQ", "timer", data)，通过publish通知其他应用功能模块处理data数据
]]

local data = 1

-- 循环定时器处理函数
local function send_data_req_timer_loop_func()
    -- 发布消息"SEND_DATA_REQ"
    -- 携带的第一个参数"timer"表示是定时器应用模块发布的消息
    -- 携带的第一个参数data为要发送的原始数据
    sys.publish("SEND_DATA_REQ", "timer", data)
    data = data+1
end

-- 启动一个5秒的循环定时器
-- 每隔5秒执行一次send_data_req_timer_loop_func函数
sys.timerLoopStart(send_data_req_timer_loop_func, 5000)
