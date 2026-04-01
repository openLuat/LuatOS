--[[
@module  uart_sender
@summary 串口发送测试模块
@version 1.0
@date    2025.03.31
@author  拓毅恒
@usage

注意：
- 本模块需要配合uart_protocol.lua协议定义文件使用
- 支持发送文本数据和文件数据
- 文件数据会被分割成512字节的帧进行发送

本模块用于发送符合协议格式的数据帧，支持以下功能：
1. 发送文本数据
2. 发送文件数据
3. 自动计算校验和并封装协议帧
4. 支持大文件分帧传输
]]

local tag = "uart_sender"

local uart_protocol = require "uart_protocol"

-- 获取协议定义
local protocol = uart_protocol.protocol
local protocol_utils = uart_protocol.protocol_utils

-- 串口配置
local uart_id = 1
local uart_baud = 115200

-- 发送文件路径
local file_path = "/luadb/test_photo.jpg"

-- 初始化串口
local function uart_init()
    log.info(tag, "初始化串口", uart_id)
    log.info(tag, "波特率:", uart_baud)
    
    local res = uart.setup(
                uart_id,
                uart_baud,
                8,          -- 数据位
                1,          -- 停止位
                uart.none   -- 校验位
    )
    
    if res == 0 then
        log.info(tag, "串口初始化完成")
        return true
    else
        log.info(tag, "串口初始化失败")
        return false
    end
end

-- 发送一帧数据
local function send_frame(data)
    local frame = protocol_utils.pack_frame(data)
    uart.write(uart_id, frame)
    log.info(tag, "发送帧，数据长度:", #data)
end

-- 发送文件
local function send_file(path)
    log.info(tag, "开始发送文件:", path)
    
    local fd = io.open(path, "rb")
    if not fd then
        log.error(tag, "文件打开失败:", path)
        return false
    end
    
    -- 获取文件大小
    local file_size = io.fileSize(path)
    log.info(tag, "文件大小:", file_size)
    
    -- 读取并分片发送
    local chunk_size = 512  -- 每帧数据最大512字节
    local total_sent = 0
    local chunk_num = 0
    
    while total_sent < file_size do
        -- 读取一块数据
        local chunk = fd:read(chunk_size)
        if not chunk or #chunk == 0 then
            break
        end
        
        chunk_num = chunk_num + 1
        send_frame(chunk)
        total_sent = total_sent + #chunk
        
        log.info(tag, "已发送:", total_sent, "/", file_size, "字节")
        
        -- 等待一小段时间，避免串口缓冲区溢出
        sys.wait(50)
    end
    
    fd:close()
    log.info(tag, "文件发送完成，共发送", chunk_num, "帧")
    return true
end

-- 发送任务主函数
local function sender_task()
    -- 模块初始化
    log.info(tag, "发送模块初始化开始")

    -- 初始化串口
    if not uart_init() then
        return
    end
    
    -- 检查文件是否存在
    if io.fileSize(file_path) and io.fileSize(file_path) > 0 then
        -- 发送文件
        send_file(file_path)
    else
        -- 发送测试数据
        log.info(tag, "文件不存在，发送测试数据")
        local count = 0
        while true do
            sys.wait(3000)
            count = count + 1
            local test_data = string.format("Test data from sender, count=%d", count)
            send_frame(test_data)
        end
    end
end

-- 启动发送任务
sys.taskInit(sender_task)
