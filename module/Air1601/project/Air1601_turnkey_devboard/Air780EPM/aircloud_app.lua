-- 云平台连接模块

local excloud = require "excloud"


-- 传感器数据存储
local sensor_data = {
    temperature = nil,
    humidity = nil,
    voc = nil
}

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
function on_excloud_event(event, data)
    log.info("用户回调函数", event, json.encode(data))

    if event == "connect_result" then
        if data.success then
            log.info("连接成功")
            sys.publish("aircloud_connected")
            -- 连接成功后尝试获取二维码信息
            if excloud.get_qrinfo then
                local qrinfo = excloud.get_qrinfo()
                if qrinfo and qrinfo.url then
                    log.info("二维码URL:", qrinfo.url)
                    sys.publish("aircloud_qrinfo", qrinfo.url)
                else
                    log.info("连接成功后未获取到二维码信息")
                end
            end
        else
            log.info("连接失败: " .. (data.error or "未知错误"))
        end
    elseif event == "auth_result" then
        if data.success then
            log.info("认证成功")
            -- 认证成功后获取二维码信息
            if excloud.get_qrinfo then
                local qrinfo = excloud.get_qrinfo()
                if qrinfo and qrinfo.url then
                    log.info("二维码URL:", qrinfo.url)
                    sys.publish("aircloud_qrinfo", qrinfo.url)
                else
                    log.info("未获取到二维码信息")
                end
            end
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

-- 初始化excloud
local function init_excloud()
    log.info("excloud", "初始化excloud")
    
    -- 检查excloud模块是否存在
    if not excloud then
        log.error("excloud模块不存在")
        return false
    end
    
    -- 注册回调
    if excloud.on then
        excloud.on(on_excloud_event)
        log.info("excloud回调已注册")
    else
        log.warn("excloud模块没有on方法")
    end
    
    -- 检查excloud是否有setup方法
    if not excloud.setup then
        log.error("excloud模块没有setup方法")
        return false
    end
    
    -- 配置excloud参数
    local device_type = 1 -- 4G设备
    local ok, err_msg = excloud.setup({
        use_getip = true,        -- 使用getip服务
        device_type = device_type,         -- 4G设备
        -- auth_key = "PBhJ2G6mn9ffDsJBRD6OVJT3zmfWLKBC", -- 项目key
        transport = "tcp",       -- 使用TCP传输
        auto_reconnect = true,   -- 自动重连
        reconnect_interval = 10, -- 重连间隔(秒)
        max_reconnect = 5,       -- 最大重连次数
        -- virtual_phone_number ="10012345678",--PC模拟器使用11位手机号
        -- mtn_log_enabled = true,  -- 启用运维日志
        -- mtn_log_blocks = 1,      -- 日志文件块数
        -- mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE  -- 缓存写入方式
    })

    if not ok then
        log.error("excloud配置失败:", err_msg)
        return false
    end
    log.info("excloud配置成功")
    
    -- 检查excloud是否有init方法
    if excloud.init then
        -- 初始化excloud模块
        local ok, err_msg = excloud.init()
        if not ok then
            log.error("excloud初始化失败:", err_msg)
            return false
        end
        log.info("excloud初始化成功")
    else
        log.warn("excloud模块没有init方法")
    end
    
    -- 检查excloud是否有open方法
    if not excloud.open then
        log.error("excloud模块没有open方法")
        return false
    end
    
    -- 开启excloud服务
    local ok, err_msg = excloud.open()
    if not ok then
        log.error("开启excloud服务失败:", err_msg)
        return false
    end
    log.info("excloud服务已开启")
    
    -- 检查excloud是否有start_heartbeat方法
    if excloud.start_heartbeat then
        -- 启动自动心跳，默认5分钟一次的心跳
        excloud.start_heartbeat()
        log.info("自动心跳已启动")
    else
        log.warn("excloud模块没有start_heartbeat方法")
    end
    
    return true
end

-- 上传传感器数据
local function upload_sensor_data()
    -- 检查excloud模块是否存在
    if not excloud then
        log.error("excloud模块不存在")
        return
    end
    
    -- 检查excloud是否有status方法
    if not excloud.status then
        log.error("excloud模块没有status方法")
        return
    end
    
    -- 检查连接状态
    local status = excloud.status()
    if not status or not status.is_connected then
        log.warn("设备未连接，跳过数据上报")
        return
    end
    
    -- 构建TLV列表
    local tlv_list = {}
    
    -- 添加信号强度
    local csq = mobile.csq()
    if csq and csq >= 0 then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.SIGNAL_STRENGTH_4G,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = csq
        })
        log.info("[excloud]构建发送数据", "SIGNAL_STRENGTH_4G", 0, csq)
    end
    
    -- 添加IMEI
    local imei = mobile.imei()
    if imei and imei ~= "" then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.SIM_ICCID,
            data_type = excloud.DATA_TYPES.ASCII,
            value = imei
        })
        log.info("[excloud]构建发送数据", "SIM_ICCID", 3, imei)
    end
    
    -- 添加时间戳
    local timestamp = os.time()
    if timestamp then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = timestamp
        })
        log.info("[excloud]构建发送数据", "TIMESTAMP", 0, timestamp)
    end
    
    -- 添加传感器数据
    if sensor_data.temperature ~= nil then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.TEMPERATURE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = sensor_data.temperature
        })
        log.info("[excloud]构建发送数据", "TEMPERATURE", 1, sensor_data.temperature)
    end
    
    if sensor_data.humidity ~= nil then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.HUMIDITY,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = sensor_data.humidity
        })
        log.info("[excloud]构建发送数据", "HUMIDITY", 1, sensor_data.humidity)
    end
    
    if sensor_data.voc ~= nil then
        table.insert(tlv_list, {
            field_meaning = excloud.FIELD_MEANINGS.PARTICULATE,
            data_type = excloud.DATA_TYPES.FLOAT,
            value = sensor_data.voc
        })
        log.info("[excloud]构建发送数据", "PARTICULATE", 1, sensor_data.voc)
    end
    
    -- 检查TLV列表是否为空
    if #tlv_list == 0 then
        log.warn("TLV列表为空，跳过数据上报")
        return
    end
    
    -- 检查excloud是否有send方法
    if not excloud.send then
        log.error("excloud模块没有send方法")
        return
    end
    
    -- 发送数据
    local ok, err_msg = excloud.send(tlv_list, false)
    if ok then
        log.info("传感器数据上报成功")
    else
        log.error("传感器数据上报失败:", err_msg)
    end
end

-- 处理传感器数据
local function handle_sensor_data(data)
    log.info("aircloud", "收到传感器数据:", data)
    
    -- 解析传感器数据
    -- 格式: "SENSOR_DATA:temp=25.5,hum=60.0,voc=100"
    local temp = data:match("temp=([%d%.]+)")
    local hum = data:match("hum=([%d%.]+)")
    local voc = data:match("voc=([%d%.]+)")
    
    if temp then
        sensor_data.temperature = tonumber(temp)
        log.info("aircloud", "温度:", sensor_data.temperature)
    end
    if hum then
        sensor_data.humidity = tonumber(hum)
        log.info("aircloud", "湿度:", sensor_data.humidity)
    end
    if voc then
        sensor_data.voc = tonumber(voc)
        log.info("aircloud", "VOC:", sensor_data.voc)
    end
    
    -- 上传传感器数据
    upload_sensor_data()
end

-- 主任务
local function excloud_task()
    -- 订阅传感器数据事件
    sys.subscribe("AIRLINK_SDATA", function(data)
        if type(data) == "string" and data:find("SENSOR_DATA:") then
            handle_sensor_data(data)
        end
    end)
    
    -- 等待网络就绪
    while not socket.adapter(socket.dft()) do
        log.warn("excloud_task", "等待网络就绪", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    
    -- 初始化excloud
    if not init_excloud() then
        log.error("excloud初始化失败，退出任务")
        return
    end
    
    -- 主循环
    while true do
        sys.wait(60000) -- 每分钟检查一次连接状态
        if excloud and excloud.status then
            local status = excloud.status()
            if not status or not status.is_connected then
                log.warn("excloud连接已断开，尝试重连")
                init_excloud()
            end
        end
    end
end

-- 启动任务
sys.taskInit(excloud_task)
