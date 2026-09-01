--[[
@module  aircloud
@summary AirCloud 功能模块
@version 1.0
@date    2026.10.16
@author  王城钧
@usage
本模块为智能寄存柜项目添加 AirCloud 功能，实现设备连接服务器、数据上报、控制指令接收等功能。
]]

-- 声明 aircloud 模块
local aircloud = {}

-- 导入 excloud 库
local excloud = require("excloud")
local server_api = require "server_api"

-- 存储开柜码和柜子号的对应关系
aircloud.pickup_code_map = {}

-- 初始化时从 fskv 中加载已保存的取件码
local function load_pickup_codes_from_fskv()
    local iter = fskv.iter()
    local key = fskv.next(iter)
    while key do
        if string.sub(key, 1, #"pickup_code_") == "pickup_code_" then
            -- 类型保护：fskv 值可能是 number/string/table/boolean，仅接受可转为数字的
            local stored = fskv.get(key)
            local box_num = nil
            if type(stored) == "number" then
                box_num = stored
            elseif type(stored) == "string" then
                box_num = tonumber(stored)
            end
            if box_num then
                local code = string.sub(key, #"pickup_code_" + 1)
                aircloud.pickup_code_map[code] = box_num
                log.info("aircloud", "从 fskv 加载取件码: " .. code .. " → 柜子" .. box_num)
            end
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

-- 根据当前默认网卡自动判断 excloud 的 device_type
-- excloud 内部按 device_type 决定从哪个硬件源生成设备ID与鉴权信息：
--   1 = 4G   → 使用 mobile.imei() + mobile.muid()
--   2 = WIFI → 使用 wlan.getMac()
--   4 = 以太网 → 使用 netdrv.mac(socket.LWIP_ETH)
-- 因此必须与 netdrv_device 中启用的网卡匹配，本函数会自动适配
-- 如果识别失败（未启用任何已知网卡），返回 nil，由调用方终止 excloud 初始化
local function get_device_type_by_adapter()
    local adapter = socket.dft()
    if adapter == socket.LWIP_GP_GW then     -- 4G(AirLink)
        return 1
    elseif adapter == socket.LWIP_STA then   -- WIFI
        return 2
    elseif adapter == socket.LWIP_ETH then   -- 以太网
        return 4
    else
        return nil
    end
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
            log.error("AirCloud 认证失败: " .. tostring(data.message or "未知错误"))
        end
    elseif event == "message" then
        -- 注意：header 里是 sequence_num 字段（非 sequence），且可能是 nil，需 tostring 防护
        log.info("收到消息, 流水号: " .. tostring(data.header and data.header.sequence_num))

        -- 处理服务器下发的消息
        if data.tlvs and type(data.tlvs) == "table" then
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
    
    -- 自动判断设备类型
    local device_type = get_device_type_by_adapter()
    if not device_type then
        log.error("无法识别当前设备类型，无法初始化AirCloud")
        return
    end
    log.info("excloud_task_func", "自动识别设备类型为", device_type)
    
    -- 配置 excloud 参数
    local ok, err_msg = excloud.setup({
        use_getip = true,         -- 使用 getip 服务
        device_type = device_type, -- 自动识别的设备类型
        auth_key = "JQtKg5M7h8HTMw8CgqMpRh77hySLlUwx",
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

-- 按柜号删除对应的取件码记录（人脸取件成功后，释放柜子占用时调用）
function aircloud.delete_pickup_code_by_box(box_num)
    if not box_num then return end
    local box_num = tonumber(box_num)
    local found = nil
    for code, b in pairs(aircloud.pickup_code_map or {}) do
        if tonumber(b) == box_num then
            found = code
            break
        end
    end
    if found then
        aircloud.delete_pickup_code(found)
        log.info("aircloud", "删除柜子" .. box_num .. "对应的取件码: " .. found)
    end
end

-- 启动 AirCloud 主任务
sys.taskInit(excloud_task_func)

-- 存件操作数据上报
function aircloud.report_send_package(data)
    local status_ok, err_msg = excloud.send({
        {
            field_meaning = excloud.FIELD_MEANINGS.OPERATION_TYPE,
            data_type = excloud.DATA_TYPES.ASCII,
            value = "S"  -- S 表示存件
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.BOX_NUMBER,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = data.box_number
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.OPERATION_TIME,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = os.time()
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.PACKAGE_SIZE,
            data_type = excloud.DATA_TYPES.ASCII,
            value = data.package_size
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
    local status_ok, err_msg = excloud.send({
        {
            field_meaning = excloud.FIELD_MEANINGS.OPERATION_TYPE,
            data_type = excloud.DATA_TYPES.ASCII,
            value = "R"  -- R 表示取件
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.BOX_NUMBER,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = data.box_number
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.OPERATION_TIME,
            data_type = excloud.DATA_TYPES.INTEGER,
            value = os.time()
        },
        {
            field_meaning = excloud.FIELD_MEANINGS.PASSWORD,
            data_type = excloud.DATA_TYPES.ASCII,
            value = data.password
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

--[[
轮询消费服务器 store_commands（服务器驱动的存件命令）
服务器在用户小程序存件(POST /store)时，把命令压入 store_commands 队列；
设备定时轮询 /status 取到命令 → 开柜 → 保存取件码 → 向服务器确认(POST /store_ack)。
]]
local function poll_store_commands_task()
    -- 等待5秒让网络初始化完成（首次轮询时避免网络未就绪直接跳过）
    sys.wait(5000)
    while true do
        -- 每10秒轮询一次：降低airlink UART桥接通道负载，
        sys.wait(10000)
        -- 网络未就绪则跳过
        if socket.adapter(socket.dft()) then
            -- FOTA升级包下载中则跳过：下载会占满airlink通道，
            -- 并发请求会挤爆链路导致下载中断（实测6205掉线、SHA256校验失败）
            local fota = require "fota_manager"
            if fota.downloading then
                log.warn("aircloud", "FOTA下载中，跳过本次轮询")
            else
                -- 业务繁忙（存/取/刷脸操作进行中）则跳过，避免开柜冲突
                local ecb = require "ecbusiness"
                if not ecb.is_busy() then
                    local ok, value = server_api.get_locker_status()
                    if ok and value and value.store_commands and #value.store_commands > 0 then
                        local executed = {}
                        for _, cmd in ipairs(value.store_commands) do
                            local box = cmd.box
                            local code = cmd.pickup_code
                            -- 已存在的取件码跳过（去重，防止重复开柜）
                            if box and code and not aircloud.pickup_code_map[code] then
                                log.info("aircloud", "执行存件命令: 柜" .. tostring(box) .. " 取件码:" .. tostring(code))
                                sys.publish("OPEN_BOX", box)
                                -- 等待开柜结果，成功才确认
                                local open_ok, open_result = sys.waitUntil("BOX_OPEN_RESULT", 3000)
                                if open_ok and open_result and open_result.success then
                                    aircloud.pickup_code_map[code] = box
                                    save_pickup_code_to_fskv(code, box)
                                    table.insert(executed, {box = box, pickup_code = code})
                                else
                                    log.warn("aircloud", "存件命令开柜失败: 柜" .. tostring(box) .. "，下轮重试")
                                end
                            end
                        end
                        -- 向服务器确认已执行
                        if #executed > 0 then
                            server_api.store_ack(executed)
                        end
                    end
                end
            end
        end
    end
end

-- 启动轮询任务
sys.taskInit(poll_store_commands_task)

-- 返回模块
return aircloud
