--[[
@module  uart_app
@summary UART串口通信模块，负责与PC端串口交互获取文件数据
@version 1.0
@date    2025.07.28
@author  马梦阳
@usage
本文件为UART串口通信模块，核心业务逻辑为：
1. 接收http_upload_stream模块的GET_FILE_SIZE_REQ消息，向PC端串口请求文件大小
2. 接收http_upload_stream模块的GET_FILE_DATA_REQ消息，向PC端串口请求分片数据
3. 将串口接收到的数据通过GET_FILE_SIZE_RESP/GET_FILE_DATA_RESP消息返回给http_upload_stream

PC端串口协议：
  - 模组发送 "getSize\r\n"     → PC端返回文件大小（数字字符串）
  - 模组发送 "getData,{index}\r\n" → PC端返回从index位置开始的文件数据（二进制）

本文件没有对外接口，直接在main.lua中require "uart_app"就可以加载运行
]]

local UART_ID = 1
-- 串口接收数据缓冲区大小，内核固件最大支持16384字节
local RX_BUFF_SIZE = 16384

-- 串口接收数据缓冲区模式（模拟器仅支持STRING模式）
-- "ZBUFF"：使用zbuff缓冲区，大数据接收效率高
-- "STRING"：使用字符串缓冲区，大数据接收效率低
local rx_mode = "ZBUFF"
if rtos.bsp() == "PC" then
    rx_mode = "STRING"
end
local is_zbuff = (rx_mode == "ZBUFF")

local rxbuff = ""
if rx_mode == "ZBUFF" then
    rxbuff = zbuff.create(RX_BUFF_SIZE)
end

-- 状态机: "IDLE"空闲 / "GET_FILE_SIZE"等待文件大小 / "GET_FILE_DATA"等待文件数据
local state = "IDLE"

-- 串口接收超时处理：将缓冲区数据通过消息发布给http_upload_stream模块
local function concat_timeout_func()
    local data_len = is_zbuff and rxbuff:used() or rxbuff:len()
    log.info("uart_app", "concat_timeout_func", data_len, state)

    if data_len > 0 then
        if state == "GET_FILE_SIZE" then
            local size_str = is_zbuff and rxbuff:toStr(0, data_len) or rxbuff
            sys.publish("GET_FILE_SIZE_RESP", tonumber(size_str))
        elseif state == "GET_FILE_DATA" then
            sys.publish("GET_FILE_DATA_RESP", rxbuff)
        end
    end 
    state = "IDLE"
end

-- 请求PC端返回文件大小
local function get_file_size_req()
    if is_zbuff then
        uart.rxClear(UART_ID)
    end
    
    uart.write(UART_ID, "getSize\r\n")

    if is_zbuff then
        rxbuff:seek(0)
    else
        rxbuff = ""
    end
    
    state = "GET_FILE_SIZE"
end

-- 请求PC端返回从index位置开始的文件数据
local function get_file_data_req(index)
    if is_zbuff then
        uart.rxClear(UART_ID)
    end
    uart.write(UART_ID, "getData," .. index .. "\r\n")
    if is_zbuff then
        rxbuff:seek(0)
    else
        rxbuff = ""
    end
    state = "GET_FILE_DATA"
end

-- UART数据接收中断处理函数
-- 采用50ms超时拼接策略：串口大数据包会拆成多次中断，等待50ms无新数据后视为一包完整数据
local function read(id)
    local temp_buff 
    if is_zbuff then
        temp_buff = zbuff.create(RX_BUFF_SIZE)
    end
    while true do
        if is_zbuff then
            local len = uart.rx(id, temp_buff)
            log.info("uart_app", "read len", len, temp_buff:used())
            if len <= 0 then
                sys.timerStart(concat_timeout_func, 500)
                break
            end
            rxbuff:copy(nil, temp_buff)
            temp_buff:seek(0)
        else
            local s = uart.read(id, RX_BUFF_SIZE)
            log.info("uart_app", "read len", id, len, s:len())
            if s:len() <= 0 then
                sys.timerStart(concat_timeout_func, 500)
                break
            end
            rxbuff = rxbuff..s
        end
    end
    if is_zbuff then
        temp_buff:free()
    end
end

-- 初始化UART
uart.setup(UART_ID, 115200, 8, 1, uart.NONE, uart.LSB, RX_BUFF_SIZE)
uart.on(UART_ID, "receive", read)

-- 订阅http_upload_stream模块的消息
sys.subscribe("GET_FILE_SIZE_REQ", get_file_size_req)
sys.subscribe("GET_FILE_DATA_REQ", get_file_data_req)
