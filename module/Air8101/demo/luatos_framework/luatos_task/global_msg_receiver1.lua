--[[
@module  global_msg_receiver1
@summary “使用sys.subscribe和sys.unsubscribe接口实现用户全局消息订阅和取消订阅”功能模块
@version 1.0
@date    2025.08.12
@author  朱天华
@usage
本文件为global_msg_receiver1应用功能模块；
用来演示“使用sys.subscribe和sys.unsubscribe接口实现用户全局消息订阅和取消订阅”的功能，核心业务逻辑为：
1、开机初始化时，订阅"SEND_DATA_REQ"全局消息的回调函数init_subscribe_cbfunc；
2、开机后延时5秒，订阅"SEND_DATA_REQ"全局消息的回调函数delay_subscribe_cbfunc；
3、开机10秒后，取消订阅"SEND_DATA_REQ"全局消息的以上两个回调函数；

本文件没有对外接口，直接在main.lua中require "global_msg_receiver1"就可以加载运行；
]]


local function init_subscribe_cbfunc(tag, count)
    log.info("init_subscribe_cbfunc", tag, count)
end

local function delay_subscribe_cbfunc(tag, count)
    log.info("delay_subscribe_cbfunc", tag, count)
end


sys.subscribe("SEND_DATA_REQ", init_subscribe_cbfunc)
sys.timerStart(sys.subscribe, 5000, "SEND_DATA_REQ", delay_subscribe_cbfunc)


sys.timerStart(sys.unsubscribe, 10000, "SEND_DATA_REQ", init_subscribe_cbfunc)
sys.timerStart(sys.unsubscribe, 10000, "SEND_DATA_REQ", delay_subscribe_cbfunc)