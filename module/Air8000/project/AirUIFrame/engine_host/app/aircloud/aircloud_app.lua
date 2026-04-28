--[[
@module  aircloud_app
@summary excloud云平台测试应用模块
@version 1.0
@date    2025.09.22
@author  孟伟
@usage
本demo演示了excloud扩展库的完整使用流程，包括：
1. 设备连接与认证
2. 数据上报与接收
3. 运维日志管理
4. 文件上传功能
5. 心跳保活机制

本文件为核心业务逻辑模块，主要功能：
- 初始化excloud配置并开启服务
- 注册回调函数处理云平台事件
- 主任务循环等待网络就绪，定期上报传感器数据
- 处理服务器下发的控制命令并回复
]]
-- 导入excloud库
local excloud = require "excloud"

--[[
用户回调函数，处理excloud所有事件

@local
@function on_excloud_event
@param event string 事件类型，如"connect_result", "auth_result", "message", "disconnect", "reconnect_failed", "send_result", "mtn_log_upload_start", "mtn_log_upload_progress", "mtn_log_upload_complete"
@param data table 事件数据，不同事件包含不同字段
@return nil

@usage
-- 内部使用，由excloud.on注册
-- 根据事件类型打印日志并处理对应逻辑
]]
local function on_excloud_event(event, data)
    log.info("用户回调函数", event, json.encode(data))

    if event == "connect_result" then
        if data.success then
            log.info("连接成功")
            sys.publish("aircloud_connected")
        else
            log.info("连接失败: " .. (data.error or "未知错误"))
        end
    elseif event == "auth_result" then
        if data.success then
            log.info("认证成功")
        else
            log.info("认证失败: " .. data.message)
        end
    elseif event == "message" then
        log.info("收到消息, 流水号: " .. data.header.sequence_num)

        -- 处理服务器下发的消息
        for _, tlv in ipairs(data.tlvs) do
            log.info("TLV字段", "含义:", tlv.field, "类型:", tlv.type, "值:", tlv.value)

            if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND then
                log.info("收到控制命令: " .. tostring(tlv.value))

                -- 处理控制命令并发送响应
                local response_ok, err_msg = excloud.send({
                    {
                        field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
                        data_type = excloud.DATA_TYPES.UNICODE,
                        value = "命令执行成功"
                    }
                }, false)

                if not response_ok then
                    log.info("发送控制响应失败: " .. err_msg)
                end
            end
        end
    elseif event == "disconnect" then
        log.warn("与服务器断开连接")
    elseif event == "reconnect_failed" then
        log.info("重连失败，已尝试 " .. data.count .. " 次")
    elseif event == "send_result" then
        if data.success then
            log.info("发送成功，流水号: " .. data.sequence_num)
        else
            log.info("发送失败: " .. data.error_msg)
        end
    elseif event == "mtn_log_upload_start" then
        log.info("运维日志上传开始", "文件数量:", data.file_count)
    elseif event == "mtn_log_upload_progress" then
        log.info("运维日志上传进度",
            "当前文件:", data.current_file,
            "总数:", data.total_files,
            "文件名:", data.file_name,
            "状态:", data.status)
    elseif event == "mtn_log_upload_complete" then
        log.info("运维日志上传完成",
            "成功:", data.success_count,
            "失败:", data.failed_count,
            "总计:", data.total_files)
    end
end

-- 注册回调
excloud.on(on_excloud_event)

--[[
数据上报队列 - 用于缓存各模块上报的数据
支持多模块并发上报，解耦数据生产与消费
]]
local report_queue = {}
local queue_max_size = 100  -- 队列最大长度，防止内存溢出

--[[
订阅数据上报请求 - 各模块通过发布此消息上报数据

@usage
-- 其他模块上报数据示例：
sys.publish("AIRCLOUD_REPORT_DATA", {
    { field_meaning = excloud.FIELD_MEANINGS.TEMPERATURE, data_type = excloud.DATA_TYPES.FLOAT, value = 25.5 },
    { field_meaning = excloud.FIELD_MEANINGS.HUMIDITY, data_type = excloud.DATA_TYPES.FLOAT, value = 60.0 }
})
]]
sys.subscribe("AIRCLOUD_REPORT_DATA", function(data_items)
    if type(data_items) ~= "table" then
        log.warn("AIRCLOUD_REPORT_DATA 数据格式错误，期望table类型")
        return
    end
    
    -- 检查队列长度，防止溢出
    if #report_queue >= queue_max_size then
        log.warn("上报队列已满，丢弃最旧的数据")
        table.remove(report_queue, 1)  -- 移除最旧的数据
    end
    
    -- 将数据加入队列
    for _, item in ipairs(data_items) do
        table.insert(report_queue, item)
    end
    
    log.info("数据已加入上报队列", "当前队列长度:", #report_queue)
    sys.publish("AIRCLOUD_DATA_QUEUED")
end)

--[[
主任务函数，负责网络等待、excloud初始化、开启服务和数据上报

@local
@function excloud_task_func
@return nil

@usage
-- 作为系统任务启动，执行以下操作：
-- 1. 等待默认网卡就绪
-- 2. 根据设备类型设置device_type
-- 3. 配置excloud参数并开启服务
-- 4. 启动自动心跳
-- 5. 获取并发布二维码信息
-- 6. 循环等待传感器数据并上报
]]
local function excloud_task_func()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("excloud_task_func", "wait IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    local device_type
    if rtos.bsp() == "PC" then
        device_type = 9
    elseif rtos.bsp() ~= "Air8101" then
        -- 加载“4G网卡”驱动模块
        device_type = 1
    else
        -- 加载“wifi”驱动网卡
        device_type = 2
    end

    -- 配置excloud参数
    local ok, err_msg = excloud.setup({
        use_getip = true,                    -- 使用getip服务
        device_type = device_type,           -- 设备类型
        auth_key = PROJECT_KEY,              -- 项目key
        transport = "tcp",                   -- 使用TCP传输
        auto_reconnect = true,               -- 自动重连
        reconnect_interval = 10,             -- 重连间隔(秒)
        max_reconnect = 5,                   -- 最大重连次数
        virtual_phone_number = "10012345678", --PC模拟器使用11位手机号
        -- mtn_log_enabled = true,  -- 启用运维日志
        -- mtn_log_blocks = 1,      -- 日志文件块数
        -- mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE  -- 缓存写入方式
    })

    if not ok then
        log.info("初始化失败: " .. err_msg)
        return
    end
    log.info("excloud初始化成功")

    -- 开启excloud服务
    local ok, err_msg = excloud.open()
    if not ok then
        log.info("开启excloud服务失败: " .. err_msg)
        return
    end
    log.info("excloud服务已开启")
    -- 启动自动心跳，默认5分钟一次的心跳
    excloud.start_heartbeat()
    log.info("自动心跳已启动")

    -- 获取并打印二维码信息
    local qrinfo = excloud.get_qrinfo()
    if qrinfo and qrinfo.url then
        log.info("二维码URL:", qrinfo.url)
        sys.publish("AIRCLOUD_QRINFO", qrinfo.url)
    else
        log.info("未获取到二维码信息")
    end

    -- 主循环：消息队列模式上报数据
    -- 支持多模块通过 AIRCLOUD_REPORT_DATA 消息上报数据
    while true do
        -- 等待数据入队或30秒超时（定时上报）
        sys.waitUntil("AIRCLOUD_DATA_QUEUED", 30000)
        
        -- 检查连接状态
        local status = excloud.status()
        if not status.is_connected then
            log.warn("设备未连接，跳过数据上报，队列长度:", #report_queue)
            -- 队列不清空，等待连接恢复后上报
        elseif #report_queue > 0 then
            -- 构建TLV列表，包含时间戳
            local tlv_list = {
                { field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP, data_type = excloud.DATA_TYPES.INTEGER, value = os.time() }
            }
            
            -- 合并队列中的所有数据
            for _, item in ipairs(report_queue) do
                table.insert(tlv_list, item)
            end
            
            -- 清空队列
            local queue_len = #report_queue
            report_queue = {}
            
            -- 发送数据
            local ok, err_msg = excloud.send(tlv_list, false)
            if ok then
                log.info("数据上报成功", "数据项:", queue_len + 1)  -- +1 for timestamp
            else
                log.error("数据上报失败:", err_msg, "数据项:", queue_len + 1)
            end
        else
            -- 队列为空，发送仅包含时间戳的心跳数据
            local tlv_list = {
                { field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP, data_type = excloud.DATA_TYPES.INTEGER, value = os.time() }
            }
            local ok, err_msg = excloud.send(tlv_list, false)
            if ok then
                log.info("心跳数据上报成功")
            else
                log.error("心跳数据上报失败:", err_msg)
            end
        end
    end
end

-- 启动主任务
sys.taskInit(excloud_task_func)
