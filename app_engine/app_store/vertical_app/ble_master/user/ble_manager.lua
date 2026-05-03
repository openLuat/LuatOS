--[[
@module  ble_manager
@summary BLE主机管理器
@version 1.0.0
@date    2026.04.10
@author  王世豪
]]

-- ==================== 模块导入 ====================
-- PC模拟器环境检测，加载模拟蓝牙库
if rtos ~= nil and rtos.bsp ~= nil then
    local bsp_name = rtos.bsp()
    if bsp_name == "PC" then
        require "bluetooth_sim"
    end
end

-- ==================== 模块定义 ====================
local ble_manager = {}

-- ==================== BLE设备对象 ====================
local bluetooth_device = nil
local ble_device = nil
local scan_create = nil

-- ==================== 状态变量 ====================
local scan_state = false
local conn_state = false
local rx_count = 0
local tx_count = 0

-- ==================== 扫描配置 ====================
local scan_config = {
    scan_interval = 1600,  -- 扫描间隔(0.625ms单位)
    scan_window = 160,     -- 扫描窗口(0.625ms单位)
    scan_mode = ble.SCAN_ACTIVE  -- 主动扫描
}

-- ==================== 发现的设备列表 ====================
local discovered_devices = {}
local connected_device = nil

-- ==================== GATT服务和特征值 ====================
local discovered_services = {}
local discovered_characteristics = {}
local service_char_map = {}
local notify_enabled_map = {}

-- ==================== 回调函数注册 ====================
local callbacks = {}

-- ==================== BLE事件回调 ====================
local function ble_callback(ble_obj, event, param)
    log.info("BLE_MASTER", "事件:", event)
    
    if event == ble.EVENT_SCAN_INIT then
        log.info("BLE_MASTER", "扫描初始化成功")
        scan_state = true
        -- 通知UI更新
        for _, cb in ipairs(callbacks) do
            if cb.on_scan_state_change then
                cb.on_scan_state_change(true)
            end
        end
        
    elseif event == ble.EVENT_SCAN_REPORT then
        -- 处理扫描报告
        local mac = param.adv_addr and param.adv_addr:toHex() or "Unknown"
        local rssi = param.rssi or -100
        local addr_type = param.addr_type or 0
        
        -- 解析设备名称
        local device_name = "Unknown"
        local adv_data = ble_obj:adv_decode(param.data)
        if adv_data then
            for k, v in pairs(adv_data) do
                -- 解析设备名称 (类型0x08: 短名称, 0x09: 完整名称)
                if v.tp == 0x08 or v.tp == 0x09 then
                    device_name = v.data:toHex()
                    device_name = string.fromHex(device_name)
                    break
                end
            end
        end
        
        -- 保存设备信息
        discovered_devices[mac] = {
            name = device_name,
            mac = mac,
            rssi = rssi,
            addr_type = addr_type,
            data = param.data,
            timestamp = os.time()
        }
        
        log.info("BLE_MASTER", "发现设备", "名称:", device_name, "MAC:", mac, "RSSI:", rssi)
        
        -- 通知UI更新
        for _, cb in ipairs(callbacks) do
            if cb.on_device_found then
                cb.on_device_found(discovered_devices[mac])
            end
        end
        
    elseif event == ble.EVENT_SCAN_STOP then
        log.info("BLE_MASTER", "扫描已停止")
        scan_state = false
        for _, cb in ipairs(callbacks) do
            if cb.on_scan_state_change then
                cb.on_scan_state_change(false)
            end
        end
        
    elseif event == ble.EVENT_CONN then
        log.info("BLE_MASTER", "已连接")
        conn_state = true
        -- 清空之前发现的GATT服务，准备接收新的
        discovered_services = {}
        discovered_characteristics = {}
        service_char_map = {}
        for _, cb in ipairs(callbacks) do
            if cb.on_conn_state_change then
                cb.on_conn_state_change(true)
            end
        end
        
    elseif event == ble.EVENT_DISCONN then
        log.info("BLE_MASTER", "已断开连接")
        conn_state = false
        connected_device = nil
        for _, cb in ipairs(callbacks) do
            if cb.on_conn_state_change then
                cb.on_conn_state_change(false)
            end
        end
        
    elseif event == ble.EVENT_WRITE then
        local received_data = param and param.data
        log.info("BLE_MASTER", "收到数据:", received_data and received_data:toHex() or "nil")
        if received_data then
            rx_count = rx_count + 1
            for _, cb in ipairs(callbacks) do
                if cb.on_data_received then
                    cb.on_data_received(received_data)
                end
            end
        end
        
    elseif event == ble.EVENT_READ_VALUE then
        -- 读取特征值完成（接收Notify数据）
        log.info("BLE_MASTER", "收到数据:", param and param.data and param.data:toHex() or "nil")
        if param and param.data then
            rx_count = rx_count + 1
            for _, cb in ipairs(callbacks) do
                if cb.on_data_received then
                    cb.on_data_received(param.data, param.uuid_service, param.uuid_characteristic)
                end
            end
        end

    elseif event == ble.EVENT_GATT_ITEM then
        -- GATT服务/特征值发现项
        log.info("BLE_MASTER", "GATT项目发现:", param)
        -- 解析并保存GATT信息
        if param then
            local service_uuid = nil
            local char_uuid = nil
            local properties = nil

            for k, v in pairs(param) do
                if k == 1 and type(v) == 'string' then
                    -- 服务UUID
                    service_uuid = v:toHex()
                    log.info("BLE_MASTER", "  服务UUID:", service_uuid)
                    if not discovered_services then
                        discovered_services = {}
                    end
                    if not service_char_map then
                        service_char_map = {}
                    end
                    table.insert(discovered_services, service_uuid)
                    service_char_map[service_uuid] = {}
                elseif type(v) == 'table' then
                    -- 特征值信息
                    for n, m in pairs(v) do
                        if n == 1 and type(m) == 'string' then
                            char_uuid = m:toHex()
                            log.info("BLE_MASTER", "    特征值UUID:", char_uuid)
                        elseif n == 2 and type(m) == 'number' then
                            properties = m
                            log.info("BLE_MASTER", "    属性:", string.format("0x%02X", m))
                        end
                    end
                    if service_uuid and char_uuid and properties then
                        discovered_characteristics[char_uuid] = {
                            service_uuid = service_uuid,
                            uuid = char_uuid,
                            properties = properties
                        }
                        service_char_map[service_uuid][char_uuid] = properties
                    end
                end
            end
        end

    elseif event == ble.EVENT_GATT_DONE then
        -- GATT发现完成
        log.info("BLE_MASTER", "GATT发现完成，共发现", #discovered_services, "个服务")
        -- 通知UI更新
        for _, cb in ipairs(callbacks) do
            if cb.on_services_discovered then
                cb.on_services_discovered(discovered_services, service_char_map)
            end
        end

    else
        log.info("BLE_MASTER", "未处理事件:", event)
    end
end

-- ==================== BLE核心功能 ====================

-- 从fskv加载扫描配置
local function load_scan_config_from_fskv()
    if not fskv then
        log.error("BLE_MASTER", "fskv不可用，无法加载扫描配置")
        return
    end
    
    log.info("BLE_MASTER", "正在从fskv加载扫描配置...")
    
    local interval = fskv.get("ble_master_scan_interval")
    log.info("BLE_MASTER", "从fskv读取 scan_interval:", interval)
    if interval then
        scan_config.scan_interval = tonumber(interval) or scan_config.scan_interval
        log.info("BLE_MASTER", "scan_interval 已更新为:", scan_config.scan_interval)
    end
    
    local window = fskv.get("ble_master_scan_window")
    log.info("BLE_MASTER", "从fskv读取 scan_window:", window)
    if window then
        scan_config.scan_window = tonumber(window) or scan_config.scan_window
        log.info("BLE_MASTER", "scan_window 已更新为:", scan_config.scan_window)
    end
    
    local scan_type = fskv.get("ble_master_scan_type")
    log.info("BLE_MASTER", "从fskv读取 scan_type:", scan_type)
    if scan_type then
        local st = tonumber(scan_type) or 1
        scan_config.scan_mode = st == 1 and ble.SCAN_ACTIVE or ble.SCAN_PASSIVE
        log.info("BLE_MASTER", "scan_mode 已更新为:", scan_config.scan_mode)
    end
    
    log.info("BLE_MASTER", "扫描配置已加载:", scan_config.scan_interval, scan_config.scan_window, scan_config.scan_mode)
end

-- 初始化BLE
function ble_manager.init()
    log.info("BLE_MASTER", "===== 初始化BLE主机管理器 =====")
    
    -- 从fskv加载扫描配置
    load_scan_config_from_fskv()
    
    -- 初始化蓝牙
    bluetooth_device = bluetooth.init()
    if not bluetooth_device then
        log.error("BLE_MASTER", "蓝牙初始化失败")
        return false
    end
    
    -- 初始化BLE功能
    ble_device = bluetooth_device:ble(ble_callback)
    if not ble_device then
        log.error("BLE_MASTER", "BLE功能初始化失败")
        return false
    end
    
    log.info("BLE_MASTER", "BLE主机管理器初始化成功")
    return true
end

-- 开始扫描
function ble_manager.start_scan()
    log.info("BLE_MASTER", "===== 启动扫描 =====")
    
    if not ble_device then
        log.error("BLE_MASTER", "BLE设备未初始化")
        return false
    end
    
    if scan_state then
        log.warn("BLE_MASTER", "扫描已在运行中")
        return true
    end
    
    -- 清空之前发现的设备
    discovered_devices = {}
    
    -- 创建扫描配置
    scan_create = ble_device:scan_create(
        ble.PUBLIC,
        scan_config.scan_interval,
        scan_config.scan_window,
        scan_config.scan_mode
    )

    log.info("BLE_MASTER", "扫描配置创建成功，interval:", scan_config.scan_interval, "window:", scan_config.scan_window, "mode:", scan_config.scan_mode)
    
    if not scan_create then
        log.error("BLE_MASTER", "扫描配置创建失败")
        return false
    end
    
    -- 启动扫描
    local result = ble_device:scan_start()
    if not result then
        log.error("BLE_MASTER", "扫描启动失败")
        return false
    end
    
    log.info("BLE_MASTER", "扫描启动成功")
    return true
end

-- 停止扫描
function ble_manager.stop_scan()
    log.info("BLE_MASTER", "停止扫描")
    
    if not ble_device then
        log.error("BLE_MASTER", "BLE设备未初始化")
        return false
    end
    
    if not scan_state then
        log.warn("BLE_MASTER", "扫描未在运行")
        return true
    end
    
    local result = ble_device:scan_stop()
    if not result then
        log.error("BLE_MASTER", "扫描停止失败")
        return false
    end
    
    scan_state = false
    log.info("BLE_MASTER", "扫描已停止")
    return true
end

-- 连接设备
function ble_manager.connect_device(mac, addr_type)
    log.info("BLE_MASTER", "连接设备:", mac, "地址类型:", addr_type)
    
    if not ble_device then
        log.error("BLE_MASTER", "BLE设备未初始化")
        return false
    end
    
    if conn_state then
        log.warn("BLE_MASTER", "已有连接，请先断开")
        return false
    end
    
    -- 停止扫描
    if scan_state then
        ble_manager.stop_scan()
    end
    
    -- 连接设备，参数顺序：(mac地址, 地址类型)
    local result = ble_device:connect(string.fromHex(mac), addr_type or ble.PUBLIC)
    if not result then
        log.error("BLE_MASTER", "连接请求失败")
        return false
    end
    
    connected_device = discovered_devices[mac]
    log.info("BLE_MASTER", "连接请求已发送")
    return true
end

-- 断开连接
function ble_manager.disconnect()
    log.info("BLE_MASTER", "断开连接")
    
    if not ble_device then
        log.error("BLE_MASTER", "BLE设备未初始化")
        return false
    end
    
    if not conn_state then
        log.warn("BLE_MASTER", "当前未连接")
        return true
    end
    
    local result = ble_device:disconnect()
    if not result then
        log.error("BLE_MASTER", "断开连接失败")
        return false
    end
    
    log.info("BLE_MASTER", "断开连接请求已发送")
    return true
end

-- ==================== 状态获取 ====================

-- 获取扫描状态
function ble_manager.get_scan_state()
    return scan_state
end

-- 获取连接状态
function ble_manager.get_conn_state()
    return conn_state
end

-- 获取数据计数
function ble_manager.get_data_count()
    return rx_count, tx_count
end

-- 获取发现的设备列表
function ble_manager.get_discovered_devices()
    return discovered_devices
end

-- 获取已连接设备信息
function ble_manager.get_connected_device()
    return connected_device
end

-- 获取设备数量
function ble_manager.get_device_count()
    local count = 0
    for _ in pairs(discovered_devices) do
        count = count + 1
    end
    return count
end

-- ==================== 回调注册 ====================

-- 注册回调
function ble_manager.register_callback(callback)
    if callback then
        table.insert(callbacks, callback)
        log.info("BLE_MASTER", "注册回调成功")
    end
end

-- 注销回调
function ble_manager.unregister_callback(callback)
    for i, cb in ipairs(callbacks) do
        if cb == callback then
            table.remove(callbacks, i)
            log.info("BLE_MASTER", "注销回调成功")
            return
        end
    end
end

-- ==================== GATT服务和特征值发现 ====================

-- 发现GATT服务
-- 注意：LuatOS BLE主机模式下，GATT发现是连接成功后自动进行的
-- 服务和特征值信息通过 EVENT_GATT_ITEM 和 EVENT_GATT_DONE 事件接收
function ble_manager.discover_gatt_services()
    log.info("BLE_MASTER", "获取已发现的GATT服务")

    if not ble_device then
        log.error("BLE_MASTER", "BLE设备未初始化")
        return false
    end

    if not conn_state then
        log.error("BLE_MASTER", "设备未连接，无法获取服务")
        return false
    end

    -- GATT发现是连接成功后自动进行的
    -- 服务和特征值信息已通过 EVENT_GATT_ITEM 和 EVENT_GATT_DONE 事件接收
    log.info("BLE_MASTER", "当前已发现", #discovered_services, "个服务")

    -- 通知UI更新
    for _, cb in ipairs(callbacks) do
        if cb.on_services_discovered then
            cb.on_services_discovered(discovered_services, service_char_map)
        end
    end

    return true
end

-- 获取发现的服务
function ble_manager.get_discovered_services()
    return discovered_services, service_char_map
end

-- ==================== 数据收发功能 ====================

-- 设置Notify使能
function ble_manager.set_notify_enable(service_uuid, char_uuid, enable)
    log.info("BLE_MASTER", "设置Notify:", service_uuid, char_uuid, enable and "开启" or "关闭")
    
    if not ble_device then
        log.error("BLE_MASTER", "BLE设备未初始化")
        return false
    end
    
    if not conn_state then
        log.error("BLE_MASTER", "设备未连接，无法设置Notify")
        return false
    end
    
    local params = {
        uuid_service = string.fromHex(service_uuid),
        uuid_characteristic = string.fromHex(char_uuid)
    }
    
    local result = ble_device:notify_enable(params, enable)
    if result then
        notify_enabled_map[char_uuid] = enable
        log.info("BLE_MASTER", "Notify设置成功")
    else
        log.error("BLE_MASTER", "Notify设置失败")
    end
    
    return result
end

-- 读取特征值
function ble_manager.read_value(service_uuid, char_uuid)
    log.info("BLE_MASTER", "读取特征值:", service_uuid, char_uuid)
    
    if not ble_device then
        log.error("BLE_MASTER", "BLE设备未初始化")
        return nil
    end
    
    if not conn_state then
        log.error("BLE_MASTER", "设备未连接，无法读取")
        return nil
    end
    
    local params = {
        uuid_service = string.fromHex(service_uuid),
        uuid_characteristic = string.fromHex(char_uuid)
    }
    
    local result = ble_device:read_value(params)
    log.info("BLE_MASTER", "读取结果:", result and result:toHex() or "nil")
    
    return result
end

-- 写入特征值
function ble_manager.write_value(service_uuid, char_uuid, data, is_cmd)
    log.info("BLE_MASTER", "写入特征值:", service_uuid, char_uuid, "数据:", data and data:toHex() or "nil")
    
    if not ble_device then
        log.error("BLE_MASTER", "BLE设备未初始化")
        return false
    end
    
    if not conn_state then
        log.error("BLE_MASTER", "设备未连接，无法写入")
        return false
    end
    
    local params = {
        uuid_service = string.fromHex(service_uuid),
        uuid_characteristic = string.fromHex(char_uuid)
    }

    local result
    if is_cmd then
        result = ble_device:write_cmd(params, data)
    else
        result = ble_device:write_value(params, data)
    end
    
    if result then
        log.info("BLE_MASTER", "写入成功")
        tx_count = tx_count + 1
        for _, cb in ipairs(callbacks) do
            if cb.on_data_sent then
                cb.on_data_sent()
            end
        end
    else
        log.error("BLE_MASTER", "写入失败")
    end
    
    return result
end

-- ==================== 配置管理 ====================

-- 获取扫描配置
function ble_manager.get_scan_config()
    return scan_config
end

-- 设置扫描配置
function ble_manager.set_scan_config(config)
    if config.scan_interval then
        scan_config.scan_interval = config.scan_interval
    end
    if config.scan_window then
        scan_config.scan_window = config.scan_window
    end
    if config.scan_mode then
        scan_config.scan_mode = config.scan_mode
    end
    log.info("BLE_MASTER", "扫描配置已更新:", scan_config.scan_interval, scan_config.scan_window, scan_config.scan_mode)
end

-- ==================== 清理 ====================

-- 清理资源
function ble_manager.deinit()
    log.info("BLE_MASTER", "清理BLE资源")

    if scan_state then
        ble_manager.stop_scan()
    end

    if conn_state then
        ble_manager.disconnect()
    end

    callbacks = {}
    discovered_devices = {}
    connected_device = nil
    discovered_services = {}
    discovered_characteristics = {}
    service_char_map = {}
    notify_enabled_map = {}
end

return ble_manager
