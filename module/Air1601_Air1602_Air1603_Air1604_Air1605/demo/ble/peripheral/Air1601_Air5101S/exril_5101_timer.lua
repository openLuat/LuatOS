--[[
@module  exril_5101_timer
@summary 定时器应用功能模块
@version 1.0
@date    2026.04.14
@author  王世豪
@usage
本文件为定时器应用功能模块，核心业务逻辑为：
创建循环定时器，用于定时向中心设备发送数据

本文件的对外接口有1个：
1. sys.publish("SEND_DATA_REQ", data, cb); 发布SEND_DATA_REQ消息
    在exril_5101_sender文件中处理
    携带的参数为：
    - data: 要发送的数据
    - cb: 发送结果回调(可以为空)
      cb.func为回调函数(可以为空)
      cb.para为回调函数的第二个参数(可以为空)
]]

-- 配置参数
local config = {
    notify_interval = 5000,  -- notify发送间隔（毫秒）
    counter = 0,            -- 计数器
}

-- 数据发送结果回调函数
-- result：发送结果，true为发送成功，false为发送失败
-- para：回调参数
local function send_data_cbfunc(result, para)
    log.info("exril_5101_timer", "发送结果:", result, "参数:", para)
end

-- 定时器回调函数 - 发送notify数据
function send_notify_data_timer_cbfunc()
    config.counter = config.counter + 1
    local notify_data = "Notify " .. config.counter .. " " .. os.date("%H:%M:%S")
    
    -- 发布消息"SEND_DATA_REQ"
    sys.publish("SEND_DATA_REQ", notify_data, {func = send_data_cbfunc, para="notify "..notify_data})
end


-- BLE连接状态处理函数
local function ble_connect_status_handler(status)
    if status then
        -- 蓝牙连接成功，启动定时器
        sys.timerLoopStart(send_notify_data_timer_cbfunc, config.notify_interval)
        log.info("exril_5101_timer", "已启动notify发送定时器, 间隔:", config.notify_interval, "ms")

    else
        -- 蓝牙断开连接，停止定时器
        sys.timerStop(send_notify_data_timer_cbfunc)
        log.info("exril_5101_timer", "已停止notify发送定时器")
        
        -- 重置计数器
        config.counter = 0
    end
end

-- 订阅BLE连接状态事件
sys.subscribe("BLE_CONNECT_STATUS", ble_connect_status_handler)
