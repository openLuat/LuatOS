--[[
@module  ble_manager
@summary 蓝牙文件传输管理模块
@version 1.0.1
@date    2026.04.30
@usage
蓝牙文件传输核心功能：
1. BLE主从模式管理
2. 全二进制传输协议，无JSON开销
3. ACK确认机制，提高可靠性
4. 优化包大小，充分利用MTU 256字节
5. 接收文件存储到"/"目录
6. 传输状态回调

协议格式（所有包都是二进制）：
通用包头：[1字节类型][2字节数据长度(大端)]

类型定义：
0x01 = 数据包: [1][2][4字节偏移量(大端)][N字节数据][2字节CRC16]
0x02 = 文件开始: [2][2][2字节文件名长度(大端)][文件名][4字节文件大小(大端)][2字节CRC16]
0x03 = 文件结束: [3][2][2字节CRC16]
0x04 = ACK确认: [4][2][1字节状态(0=ok,1=resend,2=error)][4字节偏移量(大端)][2字节CRC16]
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

-- 协议常量（全二进制）
local PACKET_TYPE_DATA = 0x01      -- 数据包
local PACKET_TYPE_FILE_START = 0x02 -- 文件开始
local PACKET_TYPE_FILE_END = 0x03   -- 文件结束
local PACKET_TYPE_ACK = 0x04        -- ACK确认

-- ACK状态
local ACK_STATUS_OK = 0x00
local ACK_STATUS_RESEND = 0x01
local ACK_STATUS_ERROR = 0x02

-- MTU和包大小配置（Air8101 MTU=256）
-- BLE协议开销：L2CAP(4) + ATT(3) = 7字节
-- 实际可用约249字节，但为了安全，数据包控制在200字节左右
local CHUNK_SIZE = 200             -- 纯数据块大小

-- ACK超时配置
local ACK_TIMEOUT_MS = 5000        -- ACK超时时间5秒
local MAX_RETRY_COUNT = 3          -- 最大重试次数
local ACK_WAIT_INTERVAL = 10       -- ACK等待轮询间隔(ms)

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

-- 模块运行状态
local is_running = true  -- 模块是否正在运行（用于防止应用关闭后访问已销毁的UI）

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

-- 发送状态（用于ACK机制）
local send_state = {
    waiting_ack = false,
    last_packet = nil,
    retry_count = 0,
    ack_received = false,
    ack_offset = 0
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

-- ==================== CRC16工具函数 ====================

-- CRC16计算表
local CRC16_TABLE = {}
local CRC16_POLYNOMIAL = 0xA001

-- 初始化CRC16表
local function init_crc16_table()
    for i = 0, 255 do
        local crc = i
        for _ = 0, 7 do
            if (crc & 1) ~= 0 then
                crc = (crc >> 1) ~ CRC16_POLYNOMIAL
            else
                crc = crc >> 1
            end
        end
        CRC16_TABLE[i] = crc
    end
end

-- 计算CRC16
local function crc16(data)
    if #CRC16_TABLE == 0 then
        init_crc16_table()
    end
    local crc = 0xFFFF
    for i = 1, #data do
        local byte = string.byte(data, i)
        crc = (crc >> 8) ~ CRC16_TABLE[(crc ~ byte) & 0xFF]
    end
    return crc & 0xFFFF
end

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
        -- 打印param的详细结构
        log.info("ble_transfer", "EVENT_CONN param类型:", type(param))
        if type(param) == "table" then
            log.info("ble_transfer", "EVENT_CONN param内容:")
            for k, v in pairs(param) do
                log.info("ble_transfer", "  ", k, "=", v, "类型:", type(v))
            end
        else
            log.info("ble_transfer", "EVENT_CONN param值:", param)
        end
        
        -- 提取连接句柄（conn_handle可能是table或直接的handle值）
        if type(param) == "table" then
            -- 优先使用conn_handle，如果它是数字
            if param.conn_handle and type(param.conn_handle) == "number" then
                connected_device = param.conn_handle
            elseif param.handle and type(param.handle) == "number" then
                connected_device = param.handle
            else
                -- 如果都不是数字，尝试直接使用param作为句柄（某些固件可能直接返回句柄table）
                connected_device = param
                log.warn("ble_transfer", "conn_handle不是数字，存储整个param")
            end
        else
            connected_device = param
        end
        log.info("ble_transfer", "BLE连接成功, conn_handle:", connected_device, "类型:", type(connected_device))
        
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
        -- 检查模块是否还在运行，防止应用关闭后访问已销毁的UI
        if is_running and callbacks.on_disconnect then
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
        log.info("ble_transfer", "EVENT_WRITE 触发, param:", param and "有数据" or "无数据")
        local received_data = param and param.data
        if received_data then
            log.info("ble_transfer", "收到写入数据，长度:", #received_data)
            ble_manager.handle_received_data(received_data)
        else
            log.warn("ble_transfer", "EVENT_WRITE 但无数据")
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
    
    if not connected_device then
        log.error("ble_transfer", "未连接设备，无法发送数据")
        return false
    end
    
    -- 提取有效的conn_handle
    -- 注意：某些固件直接返回table作为句柄，需要直接使用
    local conn_handle = connected_device
    if type(connected_device) == "table" then
        -- 首先尝试提取数字类型的句柄
        if connected_device.conn_handle and type(connected_device.conn_handle) == "number" then
            conn_handle = connected_device.conn_handle
            log.info("ble_transfer", "从table中提取conn_handle:", conn_handle)
        elseif connected_device.handle and type(connected_device.handle) == "number" then
            conn_handle = connected_device.handle
            log.info("ble_transfer", "从table中提取handle:", conn_handle)
        else
            -- 如果没有数字字段，直接使用table（某些固件需要这样）
            conn_handle = connected_device
            log.info("ble_transfer", "使用table作为conn_handle")
        end
    end
    
    local params = {
        conn_handle = conn_handle,
        uuid_service = string.fromHex(SERVICE_UUID),
        uuid_characteristic = string.fromHex(CHAR_UUID_DATA)
    }
    
    log.info("ble_transfer", "发送数据，角色:", current_role, "长度:", #data, "conn_handle:", conn_handle)
    
    local result = false
    
    if current_role == "slave" then
        -- 从机模式：使用write_notify发送notify给主机
        log.info("ble_transfer", "从机模式发送notify...")
        -- 从机模式下发送notify，需要指定conn_handle
        local notify_params = {
            conn_handle = conn_handle,
            uuid_service = string.fromHex(SERVICE_UUID),
            uuid_characteristic = string.fromHex(CHAR_UUID_DATA)
        }
        result = ble_device:write_notify(notify_params, data)
        log.info("ble_transfer", "write_notify结果:", result)
        if not result then
            log.warn("ble_transfer", "write_notify失败，尝试write_value")
            result = ble_device:write_value(notify_params, data)
            log.info("ble_transfer", "write_value结果:", result)
        end
    else
        -- 主机模式：使用write_value
        log.info("ble_transfer", "主机模式发送write...")
        result = ble_device:write_value(params, data)
    end
    
    if result then
        log.info("ble_transfer", "数据发送成功")
    else
        log.error("ble_transfer", "数据发送失败")
    end
    
    return result
end

-- ==================== 二进制协议构建函数 ====================

-- 构建通用包头 [1字节类型][2字节数据长度(大端)]
local function build_packet_header(packet_type, data_len)
    local header = string.char(packet_type)
    header = header .. string.char((data_len >> 8) & 0xFF)
    header = header .. string.char(data_len & 0xFF)
    return header
end

-- 构建数据包 [1][2][4字节偏移量][N字节数据][2字节CRC16]
local function build_data_packet(offset, data)
    local data_len = #data
    -- 数据部分 = 偏移量(4) + 数据(N)
    local payload = string.char((offset >> 24) & 0xFF)
    payload = payload .. string.char((offset >> 16) & 0xFF)
    payload = payload .. string.char((offset >> 8) & 0xFF)
    payload = payload .. string.char(offset & 0xFF)
    payload = payload .. data
    
    -- 包头 + 数据 + CRC16
    local packet = build_packet_header(PACKET_TYPE_DATA, #payload)
    packet = packet .. payload
    
    -- CRC16（计算整个包除CRC本身外的内容）
    local crc = crc16(packet)
    packet = packet .. string.char((crc >> 8) & 0xFF)
    packet = packet .. string.char(crc & 0xFF)
    
    return packet
end

-- 构建文件开始包 [2][2][2字节文件名长度][文件名][4字节文件大小][2字节CRC16]
local function build_file_start_packet(file_name, file_size)
    local name_len = #file_name
    -- 数据部分 = 文件名长度(2) + 文件名 + 文件大小(4)
    local payload = string.char((name_len >> 8) & 0xFF)
    payload = payload .. string.char(name_len & 0xFF)
    payload = payload .. file_name
    payload = payload .. string.char((file_size >> 24) & 0xFF)
    payload = payload .. string.char((file_size >> 16) & 0xFF)
    payload = payload .. string.char((file_size >> 8) & 0xFF)
    payload = payload .. string.char(file_size & 0xFF)
    
    -- 包头 + 数据 + CRC16
    local packet = build_packet_header(PACKET_TYPE_FILE_START, #payload)
    packet = packet .. payload
    
    local crc = crc16(packet)
    packet = packet .. string.char((crc >> 8) & 0xFF)
    packet = packet .. string.char(crc & 0xFF)
    
    return packet
end

-- 构建文件结束包 [3][2][0字节数据][2字节CRC16]
local function build_file_end_packet()
    local packet = build_packet_header(PACKET_TYPE_FILE_END, 0)
    local crc = crc16(packet)
    packet = packet .. string.char((crc >> 8) & 0xFF)
    packet = packet .. string.char(crc & 0xFF)
    return packet
end

-- 构建ACK包 [4][2][1字节状态][4字节偏移量][2字节CRC16]
local function build_ack_packet(status, offset)
    -- 数据部分 = 状态(1) + 偏移量(4)
    local payload = string.char(status)
    payload = payload .. string.char((offset >> 24) & 0xFF)
    payload = payload .. string.char((offset >> 16) & 0xFF)
    payload = payload .. string.char((offset >> 8) & 0xFF)
    payload = payload .. string.char(offset & 0xFF)
    
    -- 包头 + 数据 + CRC16
    local packet = build_packet_header(PACKET_TYPE_ACK, #payload)
    packet = packet .. payload
    
    local crc = crc16(packet)
    packet = packet .. string.char((crc >> 8) & 0xFF)
    packet = packet .. string.char(crc & 0xFF)
    
    return packet
end

-- 发送ACK响应（全二进制）
local function send_ack(status, offset)
    local packet = build_ack_packet(status, offset)
    return send_data(packet)
end

-- 解析通用包头，返回：type, data_len, payload_start_pos
local function parse_packet_header(packet)
    if #packet < 3 then
        return nil, nil, nil, "包头长度不足"
    end
    local packet_type = string.byte(packet, 1)
    local data_len = (string.byte(packet, 2) << 8) | string.byte(packet, 3)
    return packet_type, data_len, 4, nil  -- payload从第4字节开始
end

-- 验证CRC，返回：success, error_msg
local function verify_crc(packet)
    if #packet < 5 then  -- 至少要有包头(3) + CRC(2)
        return false, "包长度不足"
    end
    local data_part = string.sub(packet, 1, #packet - 2)
    local received_crc = (string.byte(packet, #packet - 1) << 8) | string.byte(packet, #packet)
    local calculated_crc = crc16(data_part)
    if received_crc ~= calculated_crc then
        return false, "CRC校验失败"
    end
    return true, nil
end

-- 等待ACK确认（带超时和重试）
-- 返回：success, status, offset
local function wait_for_ack(timeout_ms)
    local start_time = mcu.ticks()
    send_state.ack_received = false
    send_state.ack_offset = 0
    send_state.ack_status = nil
    
    while (mcu.ticks() - start_time) < timeout_ms do
        if send_state.ack_received then
            -- 根据ack_status返回对应的状态字符串
            local status_str = "ok"
            if send_state.ack_status == ACK_STATUS_RESEND then
                status_str = "resend"
            elseif send_state.ack_status == ACK_STATUS_ERROR then
                status_str = "error"
            end
            return true, status_str, send_state.ack_offset
        end
        sys.wait(ACK_WAIT_INTERVAL)
    end
    
    return false, "timeout", 0
end

-- 发送单个数据包（带ACK机制）
local function send_data_packet_with_ack(offset, data)
    local packet = build_data_packet(offset, data)
    
    for retry = 1, MAX_RETRY_COUNT do
        -- 发送数据包
        local send_result = send_data(packet)
        if not send_result then
            log.error("ble_transfer", "发送数据包失败，偏移量:", offset)
            if retry < MAX_RETRY_COUNT then
                sys.wait(100)
            end
        else
            -- 等待ACK
            local ack_success, ack_status, ack_offset = wait_for_ack(ACK_TIMEOUT_MS)
            
            if ack_success and ack_status == "ok" then
                -- ACK确认成功
                return true
            elseif ack_success and ack_status == "resend" then
                -- 需要重传
                log.warn("ble_transfer", "收到重传请求，偏移量:", ack_offset)
                -- 根据ack_offset调整发送位置
                if ack_offset ~= offset then
                    return false, "offset_mismatch", ack_offset
                end
            else
                -- ACK超时或错误
                log.warn("ble_transfer", "ACK超时或错误，重试:", retry)
                if retry < MAX_RETRY_COUNT then
                    sys.wait(100)
                end
            end
        end
    end
    
    return false, "max_retry_exceeded", 0
end

-- 发送文件数据包（使用ACK机制）
local function send_file_packets_with_ack(file, file_size, file_name)
    local total_sent = 0
    
    while total_sent < file_size do
        local chunk = file:read(CHUNK_SIZE)
        if not chunk then
            break
        end
        
        -- 发送数据包并等待ACK
        local success, error_code, ack_offset = send_data_packet_with_ack(total_sent, chunk)
        
        if not success then
            if error_code == "offset_mismatch" then
                -- 偏移量不匹配，需要调整文件指针
                log.warn("ble_transfer", "偏移量不匹配，调整文件指针到:", ack_offset)
                file:seek("set", ack_offset)
                total_sent = ack_offset
            else
                log.error("ble_transfer", "发送数据失败，已达到最大重试次数")
                return false, total_sent
            end
        else
            -- 发送成功
            total_sent = total_sent + #chunk
            transfer_state.transferred_size = total_sent
            
            -- 进度回调
            if callbacks.on_transfer_progress then
                local progress = math.floor((total_sent / file_size) * 100)
                callbacks.on_transfer_progress(progress, total_sent, file_size, "send")
            end
        end
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
    
    -- 初始化CRC表
    init_crc16_table()
    
    is_initialized = true
    log.info("ble_transfer", "BLE管理器初始化成功")
    return true
end

----- 设置回调函数
function ble_manager.set_callback(event, callback)
    log.info("ble_transfer", "设置回调: event=", event, "callback=", callback and "存在" or "nil")
    -- 允许设置任何回调，包括 nil（用于取消回调）
    callbacks[event] = callback
    log.info("ble_transfer", "回调设置完成: callbacks[", event, "]=", callbacks[event] and "存在" or "nil")
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
    
    -- 先停止之前的广播（如果有）
    if adv_state then
        ble_device:adv_stop()
        adv_state = false
        sys.wait(100)
    end
    
    local adv_create = ble_device:adv_create({
        addr_mode = ble.PUBLIC,
        channel_map = ble.CHNLS_ALL,
        intv_min = 160,
        intv_max = 160,
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
        callbacks.on_transfer_start(file_name, file_size, "send")
    end
    
    log.info("ble_transfer", "开始发送文件:", file_name, "大小:", file_size)
    
    -- 发送文件头（二进制格式）
    local header_packet = build_file_start_packet(file_name, file_size)
    local header_sent = false
    for i = 1, MAX_RETRY_COUNT do
        send_data(header_packet)
        local ack_success, ack_status = wait_for_ack(ACK_TIMEOUT_MS)
        if ack_success and ack_status == "ok" then
            header_sent = true
            break
        end
    end
    
    if not header_sent then
        log.error("ble_transfer", "发送文件头失败")
        file:close()
        transfer_state.is_transferring = false
        if callbacks.on_transfer_error then
            callbacks.on_transfer_error("发送文件头失败")
        end
        return false
    end
    
    -- 发送文件数据（使用ACK机制）
    local success, total_sent = send_file_packets_with_ack(file, file_size, file_name)
    file:close()
    
    if not success then
        transfer_state.is_transferring = false
        if callbacks.on_transfer_error then
            callbacks.on_transfer_error("发送失败")
        end
        return false
    end
    
    -- 发送文件结束标记（二进制格式）
    local footer_packet = build_file_end_packet()
    for i = 1, MAX_RETRY_COUNT do
        send_data(footer_packet)
        local ack_success, ack_status = wait_for_ack(ACK_TIMEOUT_MS)
        if ack_success and ack_status == "ok" then
            break
        end
    end
    
    transfer_state.is_transferring = false
    
    local duration = (mcu.ticks() - transfer_state.start_time) / 1000
    local speed = total_sent / duration / 1024
    log.info("ble_transfer", "文件发送完成，大小:", total_sent, "字节，耗时:", duration, "秒，速度:", string.format("%.2f", speed), "KB/s")
    
    if callbacks.on_transfer_complete then
        callbacks.on_transfer_complete(file_name, total_sent)
    end
    
    return true
end

-- 处理接收到的数据（全二进制协议）
function ble_manager.handle_received_data(data)
    if not data or #data == 0 then
        return
    end
    
    log.info("ble_transfer", "收到数据，长度:", #data)
    
    -- 解析包头
    local packet_type, data_len, payload_start, err = parse_packet_header(data)
    if not packet_type then
        log.warn("ble_transfer", "解析包头失败:", err)
        return
    end
    
    -- 验证CRC
    local crc_ok, crc_err = verify_crc(data)
    if not crc_ok then
        log.warn("ble_transfer", "CRC校验失败:", crc_err)
        return
    end
    
    log.info("ble_transfer", "包类型:", packet_type, "数据长度:", data_len)
    
    -- 根据包类型处理
    if packet_type == PACKET_TYPE_DATA then
        -- 数据包: [1][2][4字节偏移量][N字节数据]
        if #data < 3 + 4 + 2 then
            log.warn("ble_transfer", "数据包长度不足")
            return
        end
        
        -- 解析偏移量（大端4字节）
        local offset = (string.byte(data, payload_start) << 24) |
                       (string.byte(data, payload_start + 1) << 16) |
                       (string.byte(data, payload_start + 2) << 8) |
                       string.byte(data, payload_start + 3)
        
        -- 提取数据（payload从偏移后开始，到CRC前结束）
        local payload_data = string.sub(data, payload_start + 4, #data - 2)
        
        log.info("ble_transfer", "收到数据包，偏移量:", offset, "数据长度:", #payload_data)
        log.info("ble_transfer", "传输状态: is_transferring=", transfer_state.is_transferring, "direction=", transfer_state.direction)
        
        if not transfer_state.is_transferring or transfer_state.direction ~= "receive" then
            log.warn("ble_transfer", "未开始传输却收到数据, is_transferring=", transfer_state.is_transferring, "direction=", transfer_state.direction)
            return
        end
        
        -- 校验偏移量
        if offset ~= transfer_state.expected_offset then
            log.warn("ble_transfer", "偏移量不匹配，期望:", transfer_state.expected_offset, "实际:", offset)
            send_ack(ACK_STATUS_RESEND, transfer_state.expected_offset)
            return
        end
        
        -- 保存数据
        table.insert(transfer_state.receive_buffer, payload_data)
        transfer_state.transferred_size = transfer_state.transferred_size + #payload_data
        transfer_state.expected_offset = transfer_state.expected_offset + #payload_data
        
        -- 发送ACK
        send_ack(ACK_STATUS_OK, transfer_state.expected_offset)
        
        -- 进度回调
        log.info("ble_transfer", "准备调用进度回调: transferred_size=", transfer_state.transferred_size, "file_size=", transfer_state.file_size)
        if callbacks.on_transfer_progress then
            local progress = math.floor((transfer_state.transferred_size / transfer_state.file_size) * 100)
            log.info("ble_transfer", "调用 on_transfer_progress 回调: progress=", progress)
            callbacks.on_transfer_progress(progress, transfer_state.transferred_size, transfer_state.file_size, "receive")
        else
            log.warn("ble_transfer", "on_transfer_progress 回调为 nil")
        end
        
    elseif packet_type == PACKET_TYPE_FILE_START then
        -- 文件开始包: [2][2][2字节文件名长度][文件名][4字节文件大小]
        if data_len < 6 then
            log.warn("ble_transfer", "文件开始包数据长度不足")
            return
        end
        
        -- 解析文件名长度（大端2字节）
        local name_len = (string.byte(data, payload_start) << 8) | string.byte(data, payload_start + 1)
        
        -- 提取文件名
        local file_name = string.sub(data, payload_start + 2, payload_start + 1 + name_len)
        
        -- 解析文件大小（大端4字节）
        local size_start = payload_start + 2 + name_len
        local file_size = (string.byte(data, size_start) << 24) |
                          (string.byte(data, size_start + 1) << 16) |
                          (string.byte(data, size_start + 2) << 8) |
                          string.byte(data, size_start + 3)
        
        log.info("ble_transfer", "开始接收文件:", file_name, "大小:", file_size)
        
        if file_size > MAX_FILE_SIZE then
            log.error("ble_transfer", "文件过大")
            send_ack(ACK_STATUS_ERROR, 0)
            return
        end
        
        transfer_state = {
            is_transferring = true,
            direction = "receive",
            file_name = file_name,
            file_size = file_size,
            transferred_size = 0,
            start_time = mcu.ticks(),
            receive_buffer = {},
            expected_offset = 0
        }
        
        -- 发送ACK并确认发送成功
        log.info("ble_transfer", "正在发送文件开始ACK...")
        local ack_result = send_ack(ACK_STATUS_OK, 0)
        log.info("ble_transfer", "文件开始ACK发送结果:", ack_result)
        
        log.info("ble_transfer", "准备调用 on_transfer_start 回调, callbacks.on_transfer_start=", callbacks.on_transfer_start and "存在" or "nil")
        if callbacks.on_transfer_start then
            log.info("ble_transfer", "调用 on_transfer_start 回调: file_name=", file_name, "file_size=", file_size)
            callbacks.on_transfer_start(file_name, file_size, "receive")
        else
            log.warn("ble_transfer", "on_transfer_start 回调为 nil")
        end
        
    elseif packet_type == PACKET_TYPE_FILE_END then
        -- 文件结束包: [3][2][0字节数据]
        log.info("ble_transfer", "收到文件结束包")
        
        if not transfer_state.is_transferring then
            return
        end
        
        -- 校验文件大小
        if transfer_state.transferred_size ~= transfer_state.file_size then
            log.error("ble_transfer", "文件大小不匹配，期望:", transfer_state.file_size, "实际:", transfer_state.transferred_size)
            send_ack(ACK_STATUS_ERROR, transfer_state.expected_offset)
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
            local speed = total_written / duration / 1024
            log.info("ble_transfer", "文件接收完成，大小:", total_written, "字节，耗时:", duration, "秒，速度:", string.format("%.2f", speed), "KB/s")
            
            send_ack(ACK_STATUS_OK, transfer_state.expected_offset)
            
            if callbacks.on_file_received then
                callbacks.on_file_received(RECEIVE_DIR .. transfer_state.file_name, transfer_state.file_name, total_written)
            end
            if callbacks.on_transfer_complete then
                callbacks.on_transfer_complete(transfer_state.file_name, total_written)
            end
        else
            send_ack(ACK_STATUS_ERROR, transfer_state.expected_offset)
            if callbacks.on_transfer_error then
                callbacks.on_transfer_error("保存失败")
            end
        end
        
        transfer_state.is_transferring = false
        transfer_state.receive_buffer = nil
        
    elseif packet_type == PACKET_TYPE_ACK then
        -- ACK包: [4][2][1字节状态][4字节偏移量]
        if data_len < 5 then
            log.warn("ble_transfer", "ACK包数据长度不足")
            return
        end
        
        local status = string.byte(data, payload_start)
        local offset = (string.byte(data, payload_start + 1) << 24) |
                       (string.byte(data, payload_start + 2) << 16) |
                       (string.byte(data, payload_start + 3) << 8) |
                       string.byte(data, payload_start + 4)
        
        log.info("ble_transfer", "收到ACK，状态:", status, "偏移量:", offset)
        
        send_state.ack_received = true
        send_state.ack_offset = offset
        send_state.ack_status = status
        
    else
        log.warn("ble_transfer", "未知的包类型:", packet_type)
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

-- 模块清理函数（应用关闭时调用）
function ble_manager.cleanup()
    log.info("ble_transfer", "ble_manager cleanup 开始")
    is_running = false
    
    -- 停止传输
    if transfer_state.is_transferring then
        transfer_state.is_transferring = false
    end
    
    -- 断开BLE连接
    if is_connected and ble_device then
        pcall(function()
            ble_device.disconnect()
        end)
    end
    
    -- 停止广播
    if adv_state and ble_device then
        pcall(function()
            ble_device.stop_adv()
        end)
    end
    
    -- 停止扫描
    if is_scanning and ble_device then
        pcall(function()
            ble_device.stop_scan()
        end)
    end
    
    -- 清理回调
    callbacks = {}
    
    log.info("ble_transfer", "ble_manager cleanup 完成")
end

return ble_manager
