--[[
@module  ble_manager
@summary 蓝牙文件传输管理模块
@version 1.0.0
@date    2026.04.23
@usage
蓝牙文件传输核心功能：
1. BLE主从模式管理
2. 文件分块传输协议
3. 接收文件存储到"/"目录
4. 传输状态回调

代码结构：
- 常量定义区：UUID、配置参数
- 状态变量区：蓝牙状态、传输状态
- 回调函数区：BLE事件处理
- 工具函数区：数据发送、文件操作
- 对外接口区：供UI调用的API
]]

local ble_manager = {}

-- ==================== 常量定义区 ====================

-- GATT服务和特征值UUID
local SERVICE_UUID = "FFF0"
local CHAR_UUID_DATA = "FFF1"  -- 数据传输特征值 (Notify + Write)
local CHAR_UUID_CTRL = "FFF2"  -- 控制特征值 (Write)

-- 文件存储配置
local RECEIVE_DIR = "/"  -- 直接保存到持久化存储目录（映射到 app路径/data/）
local MAX_FILE_SIZE = 1024 * 1024  -- 1MB限制

-- 分块传输配置
local CHUNK_SIZE = 130  -- Air8101的MTU是256，每包数据控制在200字节以内

-- GATT数据库（从机模式使用）
local ATT_DB = {
    string.fromHex(SERVICE_UUID),
    {string.fromHex(CHAR_UUID_DATA), ble.NOTIFY | ble.WRITE},
    {string.fromHex(CHAR_UUID_CTRL), ble.WRITE}
}

-- 扫描配置
local SCAN_CONFIG = {
    scan_interval = 3200,  -- 扫描间隔(0.625ms单位)
    scan_window = 160,     -- 扫描窗口(0.625ms单位)
    scan_mode = ble.SCAN_ACTIVE  -- 主动扫描
}

-- ==================== 状态变量区 ====================

-- 蓝牙状态
local is_initialized = false
local is_connected = false
local current_role = "slave"  -- "master" 或 "slave"
local ble_device = nil
local adv_state = false
local connected_device = nil
local gatt_create = nil

-- GATT发现信息（主机模式使用）
local discovered_services = {}
local service_char_map = {}

-- 扫描状态
local scan_callback = nil
local is_scanning = false
local scan_config_obj = nil

-- 文件传输状态
local transfer_state = {
    is_transferring = false,
    direction = nil,  -- "send" 或 "receive"
    file_name = nil,
    file_size = 0,
    transferred_size = 0,
    start_time = 0,
    receive_buffer = nil,
    expected_offset = 0
}

-- 接收文件缓存
local received_files_cache = {}

-- 回调函数表
local callbacks = {
    on_connect = nil,
    on_disconnect = nil,
    on_transfer_start = nil,
    on_transfer_progress = nil,
    on_transfer_complete = nil,
    on_transfer_error = nil,
    on_file_received = nil
}

-- ==================== 回调函数区 ====================

-- 处理扫描报告事件
-- 解析广播数据，提取设备名称
local function handle_scan_report(ble_obj, param)
    if not is_scanning or not scan_callback then
        return
    end
    
    local mac = param.adv_addr and param.adv_addr:toHex() or "Unknown"
    local rssi = param.rssi or -100
    local device_name = "Unknown"
    
    -- 解析设备名称
    if ble_obj and param.data then
        local adv_data = ble_obj:adv_decode(param.data)
        if adv_data then
            for _, v in pairs(adv_data) do
                if v.tp == 0x08 or v.tp == 0x09 then  -- 短名称或完整名称
                    device_name = string.fromHex(v.data:toHex())
                    break
                end
            end
        end
    end
    
    log.info("ble_transfer", "扫描发现设备:", device_name, "(" .. mac .. ")", "RSSI:", rssi)
    scan_callback({addr = mac, name = device_name, rssi = rssi})
end

-- 处理GATT项目发现事件
-- 收集服务和特征值信息
local function handle_gatt_item(param)
    if not param then return end
    
    local service_uuid = nil
    local char_uuid = nil
    local properties = nil
    
    for k, v in pairs(param) do
        if k == 1 and type(v) == 'string' then
            -- 服务UUID
            service_uuid = v:toHex()
            log.info("ble_transfer", "  服务UUID:", service_uuid)
            discovered_services = discovered_services or {}
            service_char_map = service_char_map or {}
            table.insert(discovered_services, service_uuid)
            service_char_map[service_uuid] = {}
        elseif type(v) == 'table' then
            -- 特征值信息
            for n, m in pairs(v) do
                if n == 1 and type(m) == 'string' then
                    char_uuid = m:toHex()
                    log.info("ble_transfer", "    特征值UUID:", char_uuid)
                elseif n == 2 and type(m) == 'number' then
                    properties = m
                    log.info("ble_transfer", "    属性:", string.format("0x%02X", m))
                end
            end
            if service_uuid and char_uuid and properties then
                service_char_map[service_uuid][char_uuid] = properties
            end
        end
    end
end

-- 处理GATT发现完成事件
-- 自动启用notify（如果特征值支持）
local function handle_gatt_done()
    log.info("ble_transfer", "GATT发现完成，共发现", #discovered_services, "个服务")
    
    if current_role ~= "master" or not ble_device or not is_connected then
        return
    end
    
    log.info("ble_transfer", "主机模式，查找支持notify的特征值")
    
    local data_char_props = service_char_map[SERVICE_UUID] and service_char_map[SERVICE_UUID][CHAR_UUID_DATA]
    if not data_char_props then
        log.warn("ble_transfer", "未找到FFF1特征值")
        return
    end
    
    local has_notify = (data_char_props & 0x40) ~= 0
    log.info("ble_transfer", "FFF1特征值属性:", string.format("0x%02X", data_char_props), "支持notify:", has_notify)
    
    if has_notify then
        local notify_params = {
            uuid_service = string.fromHex(SERVICE_UUID),
            uuid_characteristic = string.fromHex(CHAR_UUID_DATA)
        }
        local result = ble_device:notify_enable(notify_params, true)
        log.info("ble_transfer", "notify_enable 结果:", result)
    else
        log.warn("ble_transfer", "FFF1特征值不支持notify")
    end
end

-- BLE事件回调函数
-- 处理所有BLE相关事件
local function ble_callback(ble_obj, event, param)
    log.info("ble_transfer", "BLE事件:", event)
    
    if event == ble.EVENT_ADV_START then
        log.info("ble_transfer", "广播已启动")
    elseif event == ble.EVENT_ADV_STOP then
        log.info("ble_transfer", "广播已停止")
    elseif event == ble.EVENT_CONN then
        -- 连接成功
        is_connected = true
        connected_device = param
        log.info("ble_transfer", "BLE连接成功")
        
        -- 提取MAC地址
        local addr = "未知设备"
        if type(param) == "table" then
            if param.addr and type(param.addr) == "string" then
                addr = param.addr:toHex()
            elseif param.adv_addr then
                addr = param.adv_addr:toHex()
            end
        end
        log.info("ble_transfer", "连接地址:", addr)
        
        if callbacks.on_connect then
            callbacks.on_connect(addr)
        end
    elseif event == ble.EVENT_DISCONN then
        -- 断开连接
        log.info("ble_transfer", "设备已断开")
        is_connected = false
        connected_device = nil
        if adv_state then
            adv_state = false
        end
        -- 清理GATT发现信息
        discovered_services = {}
        service_char_map = {}
        if callbacks.on_disconnect then
            callbacks.on_disconnect(param)
        end
    elseif event == ble.EVENT_SCAN_INIT then
        log.info("ble_transfer", "扫描初始化成功")
        is_scanning = true
    elseif event == ble.EVENT_SCAN_REPORT then
        handle_scan_report(ble_obj, param)
    elseif event == ble.EVENT_SCAN_STOP then
        log.info("ble_transfer", "扫描已停止")
        is_scanning = false
    elseif event == ble.EVENT_WRITE then
        -- 收到写入数据（从机模式）
        local received_data = param and param.data
        if received_data then
            log.info("ble_transfer", "收到写入数据，长度:", #received_data)
            ble_manager.handle_received_data(received_data)
        end
    elseif event == ble.EVENT_READ_VALUE then
        -- 收到notify数据（主机模式）
        local received_data = param and param.data
        if received_data then
            log.info("ble_transfer", "收到notify数据，长度:", #received_data)
            ble_manager.handle_received_data(received_data)
        end
    elseif event == ble.EVENT_READ then
        log.info("ble_transfer", "收到读取请求")
    elseif event == ble.EVENT_GATT_ITEM then
        log.info("ble_transfer", "GATT项目发现:", param)
        handle_gatt_item(param)
    elseif event == ble.EVENT_GATT_DONE then
        handle_gatt_done()
    else
        log.info("ble_transfer", "未处理事件:", event)
    end
end

-- ==================== 工具函数区 ====================

-- 发送数据到对端设备
-- 根据角色自动选择发送方式
local function send_data(data)
    if not ble_device then
        log.error("ble_transfer", "BLE设备未初始化")
        return false
    end
    
    local params = {
        conn_handle = connected_device,
        uuid_service = string.fromHex(SERVICE_UUID),
        uuid_characteristic = string.fromHex(CHAR_UUID_DATA)
    }
    
    local result = false
    
    if current_role == "slave" then
        -- 从机模式：使用write_notify
        result = ble_device:write_notify(params, data)
        if not result then
            result = ble_device:write_value(params, data)
        end
    else
        -- 主机模式：使用write_value
        result = ble_device:write_value(params, data)
    end
    
    return result
end

-- 发送文件数据包
-- 将文件分块并通过BLE发送
local function send_file_packets(file, file_size, file_name)
    local total_sent = 0
    
    while total_sent < file_size do
        local chunk = file:read(CHUNK_SIZE)
        if not chunk then
            break
        end
        
        local data_packet = {
            type = "file_data",
            offset = total_sent,
            data = crypto.base64_encode(chunk)
        }
        
        local send_result = send_data(json.encode(data_packet))
        if not send_result then
            log.error("ble_transfer", "发送数据失败")
            return false, total_sent
        end
        
        total_sent = total_sent + #chunk
        transfer_state.transferred_size = total_sent
        
        -- 进度回调
        if callbacks.on_transfer_progress then
            local progress = math.floor((total_sent / file_size) * 100)
            callbacks.on_transfer_progress(progress, total_sent, file_size)
        end
        
        -- 控制发送速度
        sys.wait(50)
    end
    
    return true, total_sent
end

-- 保存接收到的文件
-- 将缓冲区数据写入文件系统
local function save_received_file()
    local file_path = RECEIVE_DIR .. transfer_state.file_name
    log.info("ble_transfer", "保存文件到:", file_path)
    
    -- 确保目录存在
    io.mkdir(RECEIVE_DIR)
    
    local file, err = io.open(file_path, "wb")
    if not file then
        log.error("ble_transfer", "无法创建文件:", err or "未知错误")
        return false
    end
    
    local total_written = 0
    for _, chunk in ipairs(transfer_state.receive_buffer) do
        file:write(chunk)
        total_written = total_written + #chunk
    end
    file:close()
    
    -- 验证文件
    local exists = io.exists(file_path)
    log.info("ble_transfer", "文件保存完成:", exists and "成功" or "失败")
    
    return exists, total_written
end

-- 更新文件缓存
-- 将新接收的文件添加到缓存
local function update_file_cache(file_name, size, path)
    local file_info = {
        name = file_name,
        size = size,
        time = os.time(),
        path = path
    }
    
    -- 检查是否已存在
    for i, f in ipairs(received_files_cache) do
        if f.name == file_name then
            received_files_cache[i] = file_info
            return
        end
    end
    
    table.insert(received_files_cache, file_info)
end

-- ==================== 对外接口区 ====================

-- 初始化BLE模块
function ble_manager.init()
    if is_initialized then
        return true
    end
    
    log.info("ble_transfer", "初始化BLE管理器...")
    
    local bluetooth_device = bluetooth.init()
    if not bluetooth_device then
        log.error("ble_transfer", "蓝牙初始化失败")
        return false
    end
    
    ble_device = bluetooth_device:ble(ble_callback)
    if not ble_device then
        log.error("ble_transfer", "BLE功能初始化失败")
        return false
    end
    
    gatt_create = ble_device:gatt_create(ATT_DB)
    if not gatt_create then
        log.error("ble_transfer", "GATT服务创建失败")
        return false
    end
    
    is_initialized = true
    log.info("ble_transfer", "BLE管理器初始化成功")
    return true
end

-- 设置回调函数
function ble_manager.set_callback(event, callback)
    if callbacks[event] ~= nil then
        callbacks[event] = callback
    end
end

-- 开始从机模式（广播）
function ble_manager.start_slave(device_name)
    if not is_initialized then
        log.error("ble_transfer", "蓝牙未初始化")
        return false
    end
    
    current_role = "slave"
    device_name = device_name or "LuatOS-BLE-Transfer"
    
    log.info("ble_transfer", "开始从机广播:", device_name)
    
    local adv_create = ble_device:adv_create({
        addr_mode = ble.PUBLIC,
        channel_map = ble.CHNLS_ALL,
        intv_min = 120,
        intv_max = 120,
        adv_data = {
            {ble.FLAGS, string.char(0x06)},
            {ble.COMPLETE_LOCAL_NAME, device_name},
            {0x03, string.fromHex(SERVICE_UUID)}
        }
    })
    
    if not adv_create then
        log.error("ble_transfer", "创建广播失败")
        return false
    end
    
    local result = ble_device:adv_start()
    if result then
        adv_state = true
        log.info("ble_transfer", "广播已启动")
    end
    
    return result
end

-- 停止从机广播
function ble_manager.stop_slave()
    log.info("ble_transfer", "停止广播")
    
    if not ble_device then
        return true
    end
    
    if not adv_state then
        return true
    end
    
    ble_device:adv_stop()
    adv_state = false
    return true
end

-- 开始扫描设备
function ble_manager.start_scan(callback)
    if not is_initialized then
        log.error("ble_transfer", "蓝牙未初始化")
        return false
    end
    
    if is_scanning then
        return true
    end
    
    current_role = "master"
    scan_callback = callback
    
    scan_config_obj = ble_device:scan_create(
        ble.PUBLIC,
        SCAN_CONFIG.scan_interval,
        SCAN_CONFIG.scan_window,
        SCAN_CONFIG.scan_mode
    )
    
    if not scan_config_obj then
        log.error("ble_transfer", "扫描配置创建失败")
        return false
    end
    
    local result = ble_device:scan_start()
    return result
end

-- 停止扫描
function ble_manager.stop_scan()
    if not ble_device or not is_scanning then
        return true
    end
    
    local result = ble_device:scan_stop()
    scan_callback = nil
    return result
end

-- 连接设备
function ble_manager.connect(addr, callback)
    if current_role ~= "master" then
        log.error("ble_transfer", "当前不是主机模式")
        if callback then callback(false) end
        return false
    end
    
    log.info("ble_transfer", "连接设备:", addr)
    
    if not ble_device then
        if callback then callback(false) end
        return false
    end
    
    if callback then
        callbacks.on_connect = function(conn_addr)
            callback(true, conn_addr)
        end
    end
    
    local mac_bin = string.fromHex(addr:gsub(":", ""))
    return ble_device:connect(mac_bin, ble.PUBLIC)
end

-- 断开连接
function ble_manager.disconnect()
    if is_connected and connected_device then
        ble.disconnect(connected_device)
        is_connected = false
        connected_device = nil
        log.info("ble_transfer", "断开连接")
    end
end

-- 发送文件
function ble_manager.send_file(file_path)
    if not is_connected then
        log.error("ble_transfer", "未连接设备")
        return false
    end
    
    local file = io.open(file_path, "rb")
    if not file then
        log.error("ble_transfer", "无法打开文件:", file_path)
        return false
    end
    
    file:seek("end")
    local file_size = file:seek()
    file:seek("set", 0)
    
    if file_size > MAX_FILE_SIZE then
        log.error("ble_transfer", "文件过大")
        file:close()
        return false
    end
    
    local file_name = file_path:match("[^/\\]+$") or "unknown"
    
    transfer_state = {
        is_transferring = true,
        direction = "send",
        file_name = file_name,
        file_size = file_size,
        transferred_size = 0,
        start_time = mcu.ticks()
    }
    
    if callbacks.on_transfer_start then
        callbacks.on_transfer_start(file_name, file_size)
    end
    
    log.info("ble_transfer", "开始发送文件:", file_name, "大小:", file_size)
    
    -- 发送文件头
    local header = {type = "file_start", name = file_name, size = file_size}
    send_data(json.encode(header))
    sys.wait(100)
    
    -- 发送文件数据
    local success, total_sent = send_file_packets(file, file_size, file_name)
    file:close()
    
    if not success then
        transfer_state.is_transferring = false
        if callbacks.on_transfer_error then
            callbacks.on_transfer_error("发送失败")
        end
        return false
    end
    
    -- 发送文件结束标记
    local footer = {type = "file_end", name = file_name}
    send_data(json.encode(footer))
    
    transfer_state.is_transferring = false
    
    local duration = (mcu.ticks() - transfer_state.start_time) / 1000
    log.info("ble_transfer", "文件发送完成，耗时:", duration, "秒")
    
    if callbacks.on_transfer_complete then
        callbacks.on_transfer_complete(file_name, total_sent)
    end
    
    return true
end

-- 处理接收到的数据
function ble_manager.handle_received_data(data)
    if not data or #data == 0 then
        return
    end
    
    log.info("ble_transfer", "收到数据，长度:", #data)
    
    local success, packet = pcall(json.decode, data)
    if not success or not packet then
        log.warn("ble_transfer", "无法解析数据包")
        return
    end
    
    if packet.type == "file_start" then
        -- 开始接收文件
        log.info("ble_transfer", "开始接收文件:", packet.name, "大小:", packet.size)
        
        if packet.size > MAX_FILE_SIZE then
            log.error("ble_transfer", "文件过大")
            send_data(json.encode({type = "file_response", status = "error", message = "文件过大"}))
            return
        end
        
        transfer_state = {
            is_transferring = true,
            direction = "receive",
            file_name = packet.name,
            file_size = packet.size,
            transferred_size = 0,
            start_time = mcu.ticks(),
            receive_buffer = {},
            expected_offset = 0
        }
        
        send_data(json.encode({type = "file_response", status = "ready", name = packet.name}))
        
        if callbacks.on_transfer_start then
            callbacks.on_transfer_start(packet.name, packet.size)
        end
        
    elseif packet.type == "file_data" then
        -- 接收文件数据
        if not transfer_state.is_transferring then
            log.warn("ble_transfer", "未开始传输却收到数据")
            return
        end
        
        -- 校验偏移量
        if packet.offset and packet.offset ~= transfer_state.expected_offset then
            log.warn("ble_transfer", "偏移量不匹配，期望:", transfer_state.expected_offset, "实际:", packet.offset)
            send_data(json.encode({type = "file_response", status = "resend", offset = transfer_state.expected_offset}))
            return
        end
        
        -- 解码并保存数据
        if packet.data then
            local decoded = crypto.base64_decode(packet.data)
            if decoded then
                table.insert(transfer_state.receive_buffer, decoded)
                transfer_state.transferred_size = transfer_state.transferred_size + #decoded
                transfer_state.expected_offset = transfer_state.expected_offset + #decoded
            end
        end
        
        -- 发送进度确认
        local progress = math.floor((transfer_state.transferred_size / transfer_state.file_size) * 100)
        if progress % 10 == 0 then
            send_data(json.encode({type = "file_response", status = "progress", offset = transfer_state.expected_offset, progress = progress}))
        end
        
        if callbacks.on_transfer_progress then
            callbacks.on_transfer_progress(progress, transfer_state.transferred_size, transfer_state.file_size)
        end
        
    elseif packet.type == "file_end" then
        -- 文件传输完成
        if not transfer_state.is_transferring then
            return
        end
        
        log.info("ble_transfer", "文件接收完成，保存文件...")
        
        -- 校验文件大小
        if transfer_state.transferred_size ~= transfer_state.file_size then
            log.error("ble_transfer", "文件大小不匹配")
            send_data(json.encode({type = "file_response", status = "error", message = "文件大小不匹配"}))
            transfer_state.is_transferring = false
            if callbacks.on_transfer_error then
                callbacks.on_transfer_error("文件大小不匹配")
            end
            return
        end
        
        -- 保存文件
        local success, total_written = save_received_file()
        if success then
            update_file_cache(transfer_state.file_name, total_written, RECEIVE_DIR .. transfer_state.file_name)
            
            local duration = (mcu.ticks() - transfer_state.start_time) / 1000
            log.info("ble_transfer", "文件保存成功，耗时:", duration, "秒")
            
            send_data(json.encode({type = "file_response", status = "success", name = transfer_state.file_name}))
            
            if callbacks.on_file_received then
                callbacks.on_file_received(RECEIVE_DIR .. transfer_state.file_name, transfer_state.file_name, total_written)
            end
            if callbacks.on_transfer_complete then
                callbacks.on_transfer_complete(transfer_state.file_name, total_written)
            end
        else
            send_data(json.encode({type = "file_response", status = "error", message = "保存失败"}))
            if callbacks.on_transfer_error then
                callbacks.on_transfer_error("保存失败")
            end
        end
        
        transfer_state.is_transferring = false
        transfer_state.receive_buffer = nil
    end
end

-- 获取接收的文件列表
function ble_manager.get_received_files()
    -- 如果缓存为空，从文件系统读取
    if #received_files_cache == 0 then
        local ret, data = io.lsdir(RECEIVE_DIR, 50, 0)
        if ret and data then
            for i = 1, #data do
                local entry = data[i]
                if entry.type == 0 then
                    table.insert(received_files_cache, {
                        name = entry.name,
                        size = entry.size or 0,
                        time = os.time(),
                        path = RECEIVE_DIR .. entry.name
                    })
                end
            end
        end
    end
    
    -- 复制并排序
    local files = {}
    for _, f in ipairs(received_files_cache) do
        table.insert(files, {name = f.name, size = f.size, time = f.time, path = f.path})
    end
    
    table.sort(files, function(a, b)
        return (a.time or 0) > (b.time or 0)
    end)
    
    return files
end

-- 删除接收的文件
function ble_manager.delete_received_file(file_name)
    local file_path = RECEIVE_DIR .. file_name
    local result = os.remove(file_path)
    
    for i, f in ipairs(received_files_cache) do
        if f.name == file_name then
            table.remove(received_files_cache, i)
            break
        end
    end
    
    return result
end

-- 获取可发送的文件列表
function ble_manager.get_sendable_files()
    local sendable_files = {}
    local ret, data = io.lsdir("/", 50, 0)
    
    if ret and data then
        for i = 1, #data do
            local entry = data[i]
            if entry.type == 0 then
                local ext = (entry.name:match("%.([^%.]+)$") or ""):lower()
                if ext == "txt" or ext == "lua" or ext == "json" or ext == "csv" or ext == "log" or ext == "md" or ext == "zip" then
                    table.insert(sendable_files, {
                        name = entry.name,
                        size = entry.size or 0,
                        path = "/" .. entry.name
                    })
                end
            end
        end
    end
    
    return sendable_files
end

-- 获取传输状态
function ble_manager.get_transfer_state()
    return transfer_state
end

-- 检查是否已连接
function ble_manager.is_connected()
    return is_connected
end

-- 获取当前角色
function ble_manager.get_role()
    return current_role
end

return ble_manager
