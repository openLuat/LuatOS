--[[
@module  uart_to_http
@summary 串口数据接收并通过HTTP上传
@version 1.0
@date    2025.03.31
@author  拓毅恒
@usage

注意：
- 本模块需要配合uart_protocol.lua协议定义文件使用
- 使用excloud.upload_image上传图片到云平台
- 需要启用excloud的getip服务才能上传文件
- 数据接收完成后会自动上传到服务器

本模块实现以下功能：
1. 根据uart_protocol.lua定义的协议格式解析数据
2. 使用zbuff存储接收到的数据，支持缓冲区动态扩展
3. 通过excloud.upload_image上传图片文件到云平台
]]

-- 模块标识符，用于日志输出
local tag = "uart_to_http"

-- 加载依赖库
local uart_protocol = require "uart_protocol"
local excloud = require "excloud"  -- 使用excloud上传文件

-- 获取协议定义
local protocol = uart_protocol.protocol  -- 协议配置
local protocol_utils = uart_protocol.protocol_utils  -- 协议工具函数

-- 接收状态机状态
local state_wait_head1 = 0  -- 等待帧头第一个字节
local state_wait_head2 = 1  -- 等待帧头第二个字节
local state_wait_len_low = 2  -- 等待数据长度低字节
local state_wait_len_high = 3  -- 等待数据长度高字节
local state_wait_data = 4  -- 等待数据内容
local state_wait_checksum = 5  -- 等待校验和
local state_wait_tail1 = 6  -- 等待帧尾第一个字节
local state_wait_tail2 = 7  -- 等待帧尾第二个字节

-- 接收缓冲区和工作变量
local rx_state = state_wait_head1  -- 当前状态机状态
local rx_len = 0  -- 已接收数据长度
local rx_data_len = 0  -- 期望接收的数据总长度
local rx_checksum = 0  -- 接收到的校验和
local rx_buff = nil  -- 接收缓冲区
local frame_count = 0  -- 成功接收的帧计数器

-- 文件接收相关变量
local file_buff = nil  -- 文件数据缓冲区
local file_total_size = 0  -- 文件总大小
local file_received_size = 0  -- 已接收文件大小
local is_receiving_file = false  -- 是否正在接收文件

-- 初始化zbuff缓冲区
local function init_rx_buff()
    local buff_size = protocol.limits.rx_buff_size  -- 从协议配置获取缓冲区大小

    -- 如果缓冲区已存在，重新调整大小
    if rx_buff then
        rx_buff:resize(buff_size) 
    else
        rx_buff = zbuff.create(buff_size)  -- 创建新的zbuff缓冲区
    end
    rx_buff:seek(0)  -- 重置缓冲区指针到开头
end

-- 初始化文件接收缓冲区
local function init_file_buff()
    file_buff = zbuff.create(65536)  -- 创建64KB初始缓冲区
    file_buff:seek(0)  -- 重置缓冲区指针
    file_total_size = 0  -- 重置文件总大小
    file_received_size = 0  -- 重置已接收大小
    is_receiving_file = true  -- 标记为正在接收文件状态
    log.info(tag, "开始接收文件数据")
end

-- 将接收到的数据追加到文件缓冲区，自动扩展缓冲区大小
local function append_to_file_buff(data_buff, data_len)
    -- 检查缓冲区是否需要扩展
    local current_pos = file_buff:used()  -- 获取当前已使用位置
    local available = file_buff:len() - current_pos  -- 计算剩余可用空间
    
    if available < data_len then
        -- 缓冲区不足，需要扩展
        local new_size = file_buff:len() + 65536  -- 每次扩展64KB
        file_buff:resize(new_size)  -- 调整缓冲区大小
        log.info(tag, "缓冲区扩展到:", new_size)
    end
    
    -- 写入数据到缓冲区
    file_buff:seek(current_pos)  -- 定位到缓冲区末尾
    file_buff:write(data_buff:query(0, data_len))  -- 写入数据
    file_received_size = file_received_size + data_len  -- 更新已接收大小
    
    log.info(tag, "文件接收中:", file_received_size, "字节")
end

-- excloud数据接收回调函数
local function excloud_data_cb(data)
    log.info(tag, "excloud收到数据:", data)
end

-- 上传文件到服务器
local function upload_file()
    -- 等待文件接收完成消息
    sys.waitUntil("DATA_DONE")

    -- 检查是否有数据可上传
    if not file_buff or file_received_size == 0 then
        log.error(tag, "没有数据可上传")
        return
    end

    log.info(tag, "准备上传文件，大小:", file_received_size)
    
    -- 重置zbuff位置到开头
    file_buff:seek(0)
    
    local retry_count = 0  -- 重试计数器
    local max_retry = 3  -- 最大重试次数
    
    -- 重试循环，最多重试max_retry次
    while retry_count < max_retry do
        -- 检查网络是否就绪
        while not socket.adapter(socket.dft()) do
            log.warn(tag, "等待网络就绪...")
            sys.waitUntil("IP_READY", 5000)
        end
        
        -- 因服务器URL仅支持单文件上传，并且上传的文件name必须使用"uploadFile"
        -- 将zbuff数据保存为临时文件方式上传
        local temp_file = "/temp_upload.jpg"  -- 临时文件路径
        local file_content = file_buff:read(file_received_size)  -- 从缓冲区读取数据
        
        -- 保存到文件系统
        local f = io.open(temp_file, "wb")  -- 打开文件
        if f then
            f:write(file_content)  -- 写入数据
            f:close()
        else
            log.error(tag, "无法创建临时文件")
            return
        end
        
        log.info(tag, "开始上传，大小:", file_received_size, "重试:", retry_count)
        
        -- 使用excloud上传图片
        local file_name = "uart_image_" .. os.time() .. ".jpg"
        local ok, err = excloud.upload_image(temp_file, file_name)
        
        -- 上传完成后删除临时文件
        os.remove(temp_file)

        -- 检查上传结果
        if ok then
            log.info(tag, "文件上传成功!")
            frame_count = frame_count + 1  -- 增加成功计数器
            log.info(tag, "累计上传:", frame_count, "个文件")
            log.info(tag, "上传文件名:", file_name)
            break
        else
            log.error(tag, "上传失败, 错误:", err)
            retry_count = retry_count + 1
            if retry_count < max_retry then
                log.info(tag, "5秒后重试...")
                sys.wait(5000)
            end
        end
    end
    
    if retry_count >= max_retry then
        log.error(tag, "上传失败，已达最大重试次数")
    end
    
    -- 清理缓冲区
    file_buff = nil  -- 释放缓冲区
    is_receiving_file = false  -- 重置接收状态
    file_received_size = 0  -- 重置已接收大小
    file_total_size = 0  -- 重置总大小
end

-- 启动上传文件到服务器任务
sys.taskInit(upload_file)

-- 解析并处理数据
local function process_frame(data_buff, data_len)
    log.info(tag, "收到帧, 数据长度:", data_len)
    
    -- 如果是文件传输的第一帧，初始化文件缓冲区
    if not is_receiving_file then
        init_file_buff()  -- 初始化文件缓冲区
    end
    
    -- 追加数据到文件缓冲区
    append_to_file_buff(data_buff, data_len)  -- 将数据添加到文件缓冲区
    
    -- 检查是否接收完成（最后一帧数据长度小于512字节）
    if data_len < 512 then
        log.info(tag, "文件接收完成，总大小:", file_received_size)
    
        -- 发布文件接收完成消息，通知上传任务
        sys.publish("DATA_DONE")
    end
end

-- 状态机处理接收到的字节
local function state_machine_process(byte)
    if rx_state == state_wait_head1 then
        -- 等待帧头第一个字节
        if byte == protocol.frame_head[1] then
            rx_state = state_wait_head2  -- 匹配成功，进入下一状态
        end
        
    elseif rx_state == state_wait_head2 then
        -- 等待帧头第二个字节
        if byte == protocol.frame_head[2] then
            rx_state = state_wait_len_low  -- 匹配成功，进入长度低字节状态
            rx_len = 0  -- 重置已接收长度
        else
            rx_state = state_wait_head1  -- 匹配失败，重新等待帧头
        end
        
    elseif rx_state == state_wait_len_low then
        -- 等待数据长度低字节
        rx_data_len = byte  -- 保存长度低字节
        rx_state = state_wait_len_high  -- 进入长度高字节状态
        
    elseif rx_state == state_wait_len_high then
        -- 等待数据长度高字节，并组合完整长度
        rx_data_len = protocol_utils.parse_length(rx_data_len, byte)  -- 组合高低字节得到完整长度
        if rx_data_len > protocol.limits.max_data_len then
            log.warn(tag, "数据长度超出限制:", rx_data_len)
            rx_state = state_wait_head1  -- 重置状态机
        elseif rx_data_len == 0 then
            rx_state = state_wait_checksum  -- 零长度数据，直接进入校验和状态
        else
            rx_buff:seek(0)  -- 重置缓冲区指针
            rx_state = state_wait_data  -- 进入数据接收状态
        end
        
    elseif rx_state == state_wait_data then
        -- 接收数据内容
        rx_buff:write(byte)  -- 写入数据到缓冲区
        rx_len = rx_len + 1  -- 增加已接收长度
        if rx_len >= rx_data_len then
            rx_state = state_wait_checksum  -- 数据接收完成，进入校验和状态
        end
        
    elseif rx_state == state_wait_checksum then
        -- 等待校验和字节
        rx_checksum = byte  -- 保存校验和
        rx_state = state_wait_tail1  -- 进入帧尾第一字节状态
        
    elseif rx_state == state_wait_tail1 then
        -- 等待帧尾第一个字节
        if byte == protocol.frame_tail[1] then
            rx_state = state_wait_tail2  -- 匹配成功，进入帧尾第二字节状态
        else
            log.warn(tag, "帧尾1错误")  -- 记录帧尾错误
            rx_state = state_wait_head1  -- 重置状态机
        end
        
    elseif rx_state == state_wait_tail2 then
        -- 等待帧尾第二个字节
        if byte == protocol.frame_tail[2] then
            -- 验证校验和
            if protocol.checksum.enable then
                local calc_sum = protocol_utils.calc_checksum(rx_buff, rx_data_len)  -- 计算校验和
                if calc_sum == rx_checksum then
                    process_frame(rx_buff, rx_data_len)  -- 校验通过，处理数据帧
                else
                    log.warn(tag, "校验和错误, 计算:", calc_sum, "接收:", rx_checksum)
                end
            else
                process_frame(rx_buff, rx_data_len)  -- 不校验，直接处理数据帧
            end
        else
            log.warn(tag, "帧尾2错误")
        end
        rx_state = state_wait_head1  -- 无论成功失败，都重置状态机
    end
end

-- 串口数据接收回调，处理接收到的数据
local function uart_rx_cb(id, len)
    local data
    repeat
        data = uart.read(id, 128)  -- 每次读取128字节
        if #data > 0 then
            -- 逐字节处理接收到的数据
            for i = 1, #data do
                state_machine_process(string.byte(data, i))  -- 将字节传递给状态机处理
            end
        end
    until data == ""  -- 循环直到没有更多数据
end

-- 串口发送完成回调
local function uart_tx_cb(id)
    log.debug(tag, "串口", id, "数据发送完成")
end

-- 初始化串口
local function uart_init()
    log.info(tag, "初始化串口")
    
    -- 配置串口参数
    uart.setup(
        1,          -- 串口ID
        115200,     -- 波特率
        8,          -- 数据位
        1,          -- 停止位
        uart.none   -- 校验位
    )
    
    -- 注册串口回调函数
    uart.on(1, "receive", uart_rx_cb)  -- 接收回调
    uart.on(1, "sent", uart_tx_cb)    -- 发送完成回调
    
    log.info(tag, "串口初始化完成")
end

-- 模块初始化任务
local function module_init_task()
    log.info(tag, "模块初始化开始")
    
    init_rx_buff()  -- 初始化接收缓冲区
    log.info(tag, "缓冲区大小:", rx_buff:len())
    uart_init()  -- 初始化串口
    
    -- 初始化excloud（用于文件上传）
    log.info(tag, "初始化excloud...")
    local setup_ok, setup_err = excloud.setup({
        use_getip = true, -- 使用getip服务
        device_type = 1,   -- 4G设备
        auth_key = "8nNYAt12345678912345678912345", --填入自己IOT平台的项目key
        transport = "tcp",       -- 使用TCP传输
        auto_reconnect = true,   -- 自动重连
        reconnect_interval = 10, -- 重连间隔(秒)
        max_reconnect = 5,       -- 最大重连次数
        mtn_log_enabled = true,  -- 启用运维日志
        mtn_log_blocks = 2,      -- 日志文件块数
        mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE  -- 缓存写入方式
    })
    if setup_ok then
        log.info(tag, "excloud初始化成功")
        -- 注册回调函数
        excloud.on(excloud_data_cb)
        -- 开启excloud服务
        local open_ok, open_err = excloud.open()
        if open_ok then
            log.info(tag, "excloud服务已开启")
        else
            log.error(tag, "excloud开启失败:", open_err)
        end
    else
        log.error(tag, "excloud初始化失败:", setup_err)
    end
    
    log.info(tag, "模块初始化完成")
    log.info(tag, "等待串口数据...")
end

-- 启动初始化任务
sys.taskInit(module_init_task)