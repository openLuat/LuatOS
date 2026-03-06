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
local excloud = require("excloud")

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

-- 主任务函数
function excloud_task_func()
    -- 如果当前时间点设置的默认网卡还没有连接成功，一直在这里循环等待
    while not socket.adapter(socket.dft()) do
        log.warn("excloud_task_func", "wait IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    -- 配置excloud参数
    local ok, err_msg = excloud.setup({
        use_getip = true,        -- 使用getip服务
        device_type = 1,         -- 4G设备
        -- auth_key = "89SKSPwYBo0kIiDETV0nUXUAPgPDHsin",
        transport = "tcp",      -- 使用TCP传输
        auto_reconnect = true,   -- 自动重连
        reconnect_interval = 10, -- 重连间隔(秒)
        max_reconnect = 5,       -- 最大重连次数
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
        sys.publish("aircloud_qrinfo",qrinfo.url)
    else
        log.info("未获取到二维码信息")
    end

    -- 主循环：定期上报数据
    while true do
        local result, temp_val, hum_val, voc_val = sys.waitUntil("read_sht30_voc_rsp")

        -- 检查连接状态
        local status = excloud.status()
        if not status.is_connected then
            log.warn("设备未连接，跳过数据上报")
        else
            -- 构建TLV列表（仅包含非nil的传感器数据）
            local tlv_list = {
                { field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G, data_type = excloud.DATA_TYPES.INTEGER, value = mobile.csq() },
                { field_meaning = excloud.FIELD_MEANINGS.SIM_ICCID,          data_type = excloud.DATA_TYPES.ASCII,   value = mobile.imei() },
                { field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,          data_type = excloud.DATA_TYPES.INTEGER, value = os.time() }
            }

            if temp_val ~= nil then
                table.insert(tlv_list,
                    { field_meaning = excloud.FIELD_MEANINGS.TEMPERATURE, data_type = excloud.DATA_TYPES.FLOAT, value =
                    temp_val })
            end
            if hum_val ~= nil then
                table.insert(tlv_list,
                    { field_meaning = excloud.FIELD_MEANINGS.HUMIDITY, data_type = excloud.DATA_TYPES.FLOAT, value =
                    hum_val })
            end
            if voc_val ~= nil then
                table.insert(tlv_list,
                    { field_meaning = excloud.FIELD_MEANINGS.PARTICULATE, data_type = excloud.DATA_TYPES.FLOAT, value =
                    voc_val })
            end

            local ok, err_msg = excloud.send(tlv_list, false)
            if ok then
                log.info("基础数据上报成功")
            else
                log.error("基础数据上报失败:", err_msg)
            end
        end
    end
end

-- 启动主任务
sys.taskInit(excloud_task_func)