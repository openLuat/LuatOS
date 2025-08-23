--[[
@module  ble_uart_app
@summary 串口应用功能模块
@version 1.0
@date    2025.08.20
@author  王世豪
@usage
本文件为串口应用功能模块，核心业务逻辑为：
1、打开uart1，波特率115200，数据位8，停止位1，无奇偶校验位；
2、uart1和pc端的串口工具相连；
3、收到ble_client通过notify监听的数据后，将数据通过uart1发送到pc端串口工具；

本文件的对外接口有1个：
1. sys.subscribe("RECV_BLE_NOTIFY_DATA", recv_ble_notify_data_proc)，订阅RECV_BLE_NOTIFY_DATA消息，处理消息携带的数据；
]]

local UART_ID = 1
-- 初始化UART1，波特率115200，数据位8，停止位1
uart.setup(UART_ID, 115200, 8, 1)

-- 将service_uuid,char_uuid和data数据拼接
-- 然后末尾增加回车换行两个字符，通过uart1发送出去，方便在PC端换行显示查看
local function recv_ble_notify_data_proc(service_uuid, char_uuid, data)
    uart.write(UART_ID, service_uuid..","..char_uuid..","..data.."\r\n")
end

-- 订阅"RECV_BLE_NOTIFY_DATA"消息的处理函数recv_ble_notify_data_proc
sys.subscribe("RECV_BLE_NOTIFY_DATA", recv_ble_notify_data_proc)