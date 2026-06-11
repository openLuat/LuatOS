--[[
@module  excloud_test
@summary excloud测试文件
@version 1.0
@date    2025.09.22
@author  孟伟
@usage
本demo演示的功能为：
本demo演示了excloud扩展库的完整使用流程，包括：
1. 设备连接与认证
2. 数据上报与接收
3. 运维日志管理
4. 文件上传功能
5. 心跳保活机制
]]
-- 导入excloud库
-- 注册回调函数
-- 注册回调函数
function on_excloud_event(event, data)
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
                local response_ok, err_msg = excloud.send({{
                    field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
                    data_type = excloud.DATA_TYPES.UNICODE,
                    value = "命令执行成功"
                }}, false)

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
        log.info("运维日志上传进度", "当前文件:", data.current_file, "总数:", data.total_files,
            "文件名:", data.file_name, "状态:", data.status)

    elseif event == "mtn_log_upload_complete" then
        log.info("运维日志上传完成", "成功:", data.success_count, "失败:", data.failed_count, "总计:",
            data.total_files)
    end
end

-- 注册回调
excloud.on(on_excloud_event)
-- 主任务函数
function excloud_task_func()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("excloud_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    -- -- 配置excloud参数
    local ok, err_msg = excloud.setup({
        use_getip = true, -- 使用getip服务
        device_type = 1, -- 4G设备
        auth_key = "YOUR_AUTH_KEY_HERE",
        transport = "tcp", -- 使用TCP传输
        auto_reconnect = true, -- 自动重连
        reconnect_interval = 10, -- 重连间隔(秒)
        max_reconnect = 5, -- 最大重连次数
        mtn_log_enabled = true, -- 启用运维日志
        mtn_log_blocks = 1, -- 日志文件块数
        mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE -- 缓存写入方式
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
    led_util.led1_green()
    -- 启动3分钟一次的心跳，可配置自定义内容
    -- excloud.start_heartbeat(180, {
    --     { field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
    --     data_type = excloud.DATA_TYPES.INTEGER,
    --     value = os.time() }
    -- })

    -- 停止自动心跳
    -- excloud.stop_heartbeat()
    -- 记录启动日志
    -- excloud.mtn_log("system", "设备启动完成", "version", "1.0.0")

    -- 主循环：定期上报数据

    while true do
        -- 每30秒上报一次数据
        sys.wait(1000)
        -- -- 检查连接状态
        local status = excloud.status()
        if not status.is_connected then
            log.warn("excloud未连接")
            config.device_status = config.device_status_mode.no_mqtt
            while not socket.adapter() do
                log.warn("excloud_task_func", "wait IP_READY")
                sys.waitUntil("IP_READY", 1000)
                config.device_status = config.device_status_mode.no_network
            end
        else
            config.device_status = config.device_status_mode.mqtt_online
        end

    end
end

-- -- 启动主任务
sys.taskInit(excloud_task_func)
