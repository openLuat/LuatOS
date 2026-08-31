--[[
@module  aircloud
@summary AirCloud 功能模块
@version 2.0
@date    2026.10.16
@author  王城钧
@usage
本模块为智能寄存柜项目添加 AirCloud 功能，实现设备连接服务器、数据上报、控制指令接收等功能。
依赖 excloud 库，通过 excloud.on(callback) 注册事件回调。
]]


-- 声明 aircloud 模块
local aircloud = {}

-- 版本标记：用于确认设备上烧录的是修复后的版本（2026-08-31 sequence兼容修复）
log.info("aircloud", "AIRCLOUD_V2_OK sequence兼容修复已生效")

-- 导入 excloud 库
local excloud = require("excloud")

-- 存储开柜码和柜子号的对应关系
aircloud.pickup_code_map = {}

-- 初始化时从 fskv 中加载已保存的取件码
local function load_pickup_codes_from_fskv()
    local iter = fskv.iter()
    local key = fskv.next(iter)
    while key do
        if string.sub(key, 1, #"pickup_code_") == "pickup_code_" then
            local box_num = tonumber(fskv.get(key))
            local code = string.sub(key, #"pickup_code_" + 1)
            aircloud.pickup_code_map[code] = box_num
            log.info("aircloud", "从 fskv 加载取件码: " .. code .. " → 柜子" .. box_num)
        end
        key = fskv.next(iter)
    end
end

-- 保存取件码到 fskv
local function save_pickup_code_to_fskv(code, box_num)
    local key = "pickup_code_" .. code
    fskv.set(key, tostring(box_num))
    log.info("aircloud", "保存取件码到 fskv: " .. code .. " → 柜子" .. box_num)
end

-- 从 fskv 删除取件码
local function delete_pickup_code_from_fskv(code)
    local key = "pickup_code_" .. code
    fskv.del(key)
    log.info("aircloud", "从 fskv 删除取件码: " .. code)
end

-- AirCloud 事件回调函数
function on_excloud_event(event, data)
    log.info("AirCloud 事件", event, json.encode(data))

    if event == "connect_result" then
        if data.success then
            log.info("AirCloud 连接成功")
            sys.publish("AIRCloud_CONNECTED")
        else
            log.error("AirCloud 连接失败: " .. (data.error or "未知错误"))
        end
    elseif event == "auth_result" then
        if data.success then
            log.info("AirCloud 认证成功")
        else
            log.error("AirCloud 认证失败: " .. data.message)
        end
    elseif event == "message" then
        log.info("收到消息, 流水号: " .. tostring(data.header.sequence_num or data.header.sequence))

        -- 处理服务器下发的消息
        for _, tlv in ipairs(data.tlvs) do
            log.info("TLV字段", "含义:", tlv.field, "类型:", tlv.type, "值:", tlv.value)

            -- 检查是否是控制命令或随机数据字段（服务器可能使用 RANDOM_DATA 字段发送命令）
            if tlv.field == excloud.FIELD_MEANINGS.CONTROL_COMMAND or tlv.field == excloud.FIELD_MEANINGS.RANDOM_DATA then
                log.info("收到命令消息: " .. tostring(tlv.value))
                
                -- 解析命令格式: save,1,228072
                local cmd_str = tostring(tlv.value)
                local cmd_parts = {}
                for part in cmd_str:gmatch("[^,]+") do
                    table.insert(cmd_parts, part)
                end
                
                if #cmd_parts >= 3 and cmd_parts[1] == "save" then
                    local box_num = tonumber(cmd_parts[2])
                    local open_code = cmd_parts[3]
                    log.info("解析到存件命令: 柜子号=" .. tostring(box_num) .. ", 开柜码=" .. open_code)
                    log.debug("aircloud", "cmd_parts[3] 类型: " .. type(open_code) .. ", 值: " .. tostring(open_code))
                    
                    -- 保存开柜码和柜子号的对应关系
                    aircloud.pickup_code_map[open_code] = box_num
                    save_pickup_code_to_fskv(open_code, box_num)
                    log.info("已保存开柜码: " .. open_code .. " 对应柜子号: " .. box_num)
                    log.debug("aircloud", "pickup_code_map 内容: " .. json.encode(aircloud.pickup_code_map))
                    
                    -- 发送响应
                    local response_ok, err_msg = excloud.send({
                        {
                            field_meaning = excloud.FIELD_MEANINGS.CONTROL_RESPONSE,
                            data_type = excloud.DATA_TYPES.UNICODE,
                            value = "开柜码已保存，柜子" .. tostring(box_num) .. "准备完毕"
                        }
                    }, false)

                    if not response_ok then
                        log.info("发送控制响应失败: " .. err_msg)
                    end
                else
                    log.warn("收到无法识别的命令格式: " .. cmd_str)
                end
            end
        end
    elseif event == "disconnect" then
        log.warn("AirCloud 与服务器断开连接")
    elseif event == "reconnect_failed" then
        log.error("AirCloud 重连失败，已尝试 " .. data.count .. " 次")
    elseif event == "send_result" then
        if data.success then
            log.info("AirCloud 发送成功，流水号: " .. data.sequence_num)
        else
            log.error("AirCloud 发送失败: " .. data.error_msg)
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
    -- 加载已保存的取件码
    load_pickup_codes_from_fskv()
    
    -- 等待网络连接成功
    while not socket.adapter(socket.dft()) do
        log.warn("excloud_task_func", "等待网络连接", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    
    -- 新版 excloud 库会根据模组型号自动识别设备类型（Air1601 → MCU主控类型3），
    -- 不再需要应用层手动配置 use_getip / device_type / auth_key
    local ok, err_msg = excloud.setup({
        transport = "tcp",       -- 使用 TCP 传输
        auto_reconnect = true,   -- 自动重连
        reconnect_interval = 10, -- 重连间隔(秒)
        max_reconnect = 5,       -- 最大重连次数
        mtn_log_enabled = true,  -- 启用运维日志
        mtn_log_blocks = 1,      -- 日志文件块数
        mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE  -- 缓存写入方式
    })

    if not ok then
        log.error("excloud 配置失败: " .. err_msg)
        return
    end
    
    log.info("excloud 配置成功")
    
    -- 启动 excloud 服务
    excloud.open()
    log.info("AirCloud 连接成功，已停止定期数据上报")

     -- 启动自动心跳，默认5分钟一次的心跳
    excloud.start_heartbeat()
    log.info("自动心跳已启动")
end

-- 根据开柜码获取对应的柜子号
function aircloud.get_box_num_by_pickup_code(code)
    -- 先从内存中查找
    local box_num = aircloud.pickup_code_map[code]
    
    -- 如果内存中没有找到，从 fskv 中查找
    if not box_num then
        local key = "pickup_code_" .. code
        local stored = fskv.get(key)
        if stored then
            box_num = tonumber(stored)
            aircloud.pickup_code_map[code] = box_num
            log.info("aircloud", "从 fskv 加载取件码: " .. code .. " → 柜子" .. box_num)
        end
    end
    
    return box_num
end

-- 删除取件码记录（取件成功后调用）
function aircloud.delete_pickup_code(code)
    -- 从内存中删除
    aircloud.pickup_code_map[code] = nil
    
    -- 从 fskv 中删除
    delete_pickup_code_from_fskv(code)
end

-- 启动 AirCloud 主任务
sys.taskInit(excloud_task_func)

-- 存件操作数据上报
function aircloud.report_send_package(data)
    -- 注意：官方 FIELD_MEANINGS 中没有 OPERATION_TYPE/BOX_NUMBER/OPERATION_TIME/PACKAGE_SIZE 业务字段，
    -- 旧代码使用这些不存在的字段会导致 build_tlv(nil, ...) 上报一直失败。
    -- 这里改用官方标准字段 BUSINESS_SN(1282) 承载组合业务数据，TIMESTAMP(1280) 承载时间戳。
    local status_ok, err_msg = excloud.send({
        {
            field_meaning = excloud.FIELD_MEANINGS.BUSINESS_SN,
            data_type = excloud.DATA_TYPES.ASCII,
            value = string.format("save,%s,%d,%s",
                tostring(data.box_number),
                os.time(),
                tostring(data.package_size or ""))
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = os.time()
        }
    }, false)
    
    if status_ok then
        log.info("AirCloud 存件数据上报成功")
    else
        log.error("AirCloud 存件数据上报失败: " .. err_msg)
    end
end

-- 取件操作数据上报
function aircloud.report_receive_package(data)
    -- 与存件上报同理，使用官方标准字段 BUSINESS_SN(1282) 承载组合业务数据
    local status_ok, err_msg = excloud.send({
        {
            field_meaning = excloud.FIELD_MEANINGS.BUSINESS_SN,
            data_type = excloud.DATA_TYPES.ASCII,
            value = string.format("receive,%s,%d,%s",
                tostring(data.box_number),
                os.time(),
                tostring(data.password or ""))
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.TIMESTAMP,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = os.time()
        }
    }, false)
    
    if status_ok then
        log.info("AirCloud 取件数据上报成功")
    else
        log.error("AirCloud 取件数据上报失败: " .. err_msg)
    end
end

-- 测试接口：模拟服务器下发存件命令
function aircloud.test_send_save_command(box_num, open_code)
    log.debug("aircloud", "模拟服务器下发存件命令: save," .. box_num .. "," .. open_code)
    
    -- 保存开柜码和柜子号的对应关系
    aircloud.pickup_code_map[open_code] = box_num
    save_pickup_code_to_fskv(open_code, box_num)
    log.info("aircloud", "已保存开柜码: " .. open_code .. " 对应柜子号: " .. box_num)
    log.debug("aircloud", "pickup_code_map 内容: " .. (json.encode(aircloud.pickup_code_map) or "空"))
end

-- 返回模块
return aircloud
