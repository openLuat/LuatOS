--[[
@module  ble_manager
@summary BLE从机管理器
@version 1.0.0
@date    2026.04.09
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

-- ==================== 常量定义 ====================
local SERVICE_UUID = "FA00"
local CHAR_UUID_1 = "EA01"  -- Notify + Read + Write
local CHAR_UUID_2 = "EA02"  -- Write
local CHAR_UUID_3 = "EA03"  -- Read

-- ==================== BLE设备对象 ====================
local ble_device = nil
local adv_create = nil
local gatt_create = nil

-- ==================== 状态变量 ====================
local adv_state = false
local conn_state = false
local rx_count = 0
local tx_count = 0

-- ==================== 配置参数 ====================
local config = {
    adv_interval = 100,  -- 广播间隔(ms)
    device_name = "LuatOS_BLE"
}

-- ==================== GATT数据库 ====================
local att_db = { 
    string.fromHex(SERVICE_UUID),
    -- Characteristic 1: Notify + Read + Write
    {
        string.fromHex(CHAR_UUID_1),
        ble.NOTIFY | ble.READ | ble.WRITE
    },
    -- Characteristic 2: Write + Write Without Response
    {
        string.fromHex(CHAR_UUID_2),
        ble.WRITE | ble.WRITE_CMD
    },
    -- Characteristic 3: Read
    {
        string.fromHex(CHAR_UUID_3),
        ble.READ
    }
}

-- ==================== BLE事件回调 ====================
local function ble_callback(ble_obj, event, param)
    log.info("BLE", "事件:", event)
    
    if event == ble.EVENT_ADV_START then
        log.info("BLE", "广播已启动")
        adv_state = true
        -- 通知UI更新
        if ble_manager.on_state_change then
            ble_manager.on_state_change("adv", true)
        end
    elseif event == ble.EVENT_ADV_STOP then
        log.info("BLE", "广播已停止")
        adv_state = false
        if ble_manager.on_state_change then
            ble_manager.on_state_change("adv", false)
        end
    elseif event == ble.EVENT_CONN then
        log.info("BLE", "已连接")
        conn_state = true
        if ble_manager.on_state_change then
            ble_manager.on_state_change("conn", true)
        end
    elseif event == ble.EVENT_DISCONN then
        log.info("BLE", "已断开连接")
        conn_state = false
        -- 断开连接后广播通常也会停止，同步更新广播状态
        if adv_state then
            log.info("BLE", "断开连接，同步更新广播状态为停止")
            adv_state = false
            if ble_manager.on_state_change then
                ble_manager.on_state_change("adv", false)
            end
        end
        if ble_manager.on_state_change then
            ble_manager.on_state_change("conn", false)
        end
    elseif event == ble.EVENT_WRITE then
        local received_data = param and param.data
        log.info("BLE", "收到写入:", received_data)
        if received_data then
            rx_count = rx_count + 1
            if ble_manager.on_data then
                ble_manager.on_data("rx", received_data)
            end
        end
    elseif event == ble.EVENT_READ then
        log.info("BLE", "收到读取请求")
        tx_count = tx_count + 1
        if ble_manager.on_data then
            ble_manager.on_data("tx", nil)
        end
    else
        log.info("BLE", "未处理事件:", event)
    end
end

-- ==================== BLE核心功能 ====================

-- 初始化BLE
function ble_manager.init()
    log.info("BLE", "===== 初始化BLE管理器 =====")
    log.info("BLE", "检查bluetooth模块: ", bluetooth ~= nil)
    
    -- 初始化蓝牙
    local bluetooth_device = bluetooth.init()
    if not bluetooth_device then
        log.error("BLE", "蓝牙初始化失败")
        return false
    end
    
    -- 初始化BLE功能
    ble_device = bluetooth_device:ble(ble_callback)
    if not ble_device then
        log.error("BLE", "BLE功能初始化失败")
        return false
    end
    
    -- 创建GATT服务
    gatt_create = ble_device:gatt_create(att_db)
    if not gatt_create then
        log.error("BLE", "GATT服务创建失败")
        return false
    end
    
    log.info("BLE", "BLE管理器初始化成功")
    return true
end

-- 开始广播
function ble_manager.start_adv()
    log.info("BLE", "===== 启动广播 =====")
    
    if not ble_device then
        log.error("BLE", "BLE设备未初始化")
        return false
    end
    
    if adv_state then
        log.warn("BLE", "广播已在运行中")
        return true
    end
    
    -- 创建广播配置
    adv_create = ble_device:adv_create({
        addr_mode = ble.PUBLIC,
        channel_map = ble.CHNLS_ALL,
        intv_min = config.adv_interval,
        intv_max = config.adv_interval,
        adv_data = {
            {ble.FLAGS, string.char(0x06)},
            {ble.COMPLETE_LOCAL_NAME, config.device_name},
        }
    })
    
    if not adv_create then
        log.error("BLE", "广播配置创建失败")
        return false
    end
    
    -- 启动广播
    local result = ble_device:adv_start()
    if not result then
        log.error("BLE", "广播启动失败")
        return false
    end
    
    log.info("BLE", "广播启动成功")
    return true
end

-- 停止广播
function ble_manager.stop_adv()
    log.info("BLE", "停止广播")
    
    if not ble_device then
        log.error("BLE", "BLE设备未初始化")
        return false
    end
    
    if not adv_state then
        log.warn("BLE", "广播未在运行")
        return true
    end
    
    local result = ble_device:adv_stop()
    if not result then
        log.error("BLE", "广播停止失败")
        return false
    end
    
    adv_state = false
    log.info("BLE", "广播已停止")
    return true
end

-- 获取广播状态
function ble_manager.get_adv_state()
    return adv_state
end

-- 获取连接状态
function ble_manager.get_conn_state()
    return conn_state
end

-- 获取数据计数
function ble_manager.get_data_count()
    return rx_count, tx_count
end

-- 获取配置
function ble_manager.get_config()
    return config
end

-- ==================== 配置持久化 ====================

-- fskv键定义
local fskv_keys = {
    adv_interval = "ble_slave_adv_interval",
    device_name = "ble_slave_device_name"
}

-- fskv初始化
function ble_manager.fskv_init()
    if not fskv then
        log.error("BLE", "fskv不可用")
        return false
    end
    return true
end

-- 加载配置从fskv
local function load_config()
    local loaded_config = {
        adv_interval = config.adv_interval,
        device_name = config.device_name
    }

    if not fskv then
        log.warn("BLE", "fskv不可用，使用默认配置")
        return loaded_config
    end

    ble_manager.fskv_init()

    local adv_interval = fskv.get(fskv_keys.adv_interval)
    if adv_interval then
        loaded_config.adv_interval = tonumber(adv_interval) or loaded_config.adv_interval
    end

    local device_name = fskv.get(fskv_keys.device_name)
    if device_name and device_name ~= "" then
        loaded_config.device_name = device_name
    end

    return loaded_config
end

-- 保存配置到fskv
function ble_manager.save_config(new_config)
    if not fskv then
        log.error("BLE", "fskv不可用，保存失败")
        return false
    end

    if not ble_manager.fskv_init() then
        return false
    end

    -- 更新内存中的配置
    if new_config.adv_interval then
        config.adv_interval = new_config.adv_interval
    end
    if new_config.device_name then
        config.device_name = new_config.device_name
    end

    -- 保存到fskv
    local ok = true
    ok = ok and fskv.set(fskv_keys.adv_interval, tostring(config.adv_interval))
    ok = ok and fskv.set(fskv_keys.device_name, config.device_name)

    if ok then
        log.info("BLE", "配置保存成功")
    else
        log.error("BLE", "配置保存失败")
    end

    return ok
end

-- 加载配置（启动时调用）
do
    if fskv then
        config = load_config()
    end
end

-- ==================== 数据传输功能 ====================

-- 发送数据到指定特征值
function ble_manager.send_data(data, char_uuid, char_props)
    if not ble_device or not conn_state then
        log.error("BLE", "未连接，无法发送数据")
        return false
    end
    
    -- 使用指定的特征值UUID，默认为EA01
    local target_uuid = char_uuid or "EA01"
    local props = char_props or (0x40 | 0x08 | 0x10)  -- 默认EA01的属性
    log.info("BLE", "发送数据到特征值:", target_uuid, "属性:", string.format("0x%02X", props))
    
    local params = {
        uuid_service = string.fromHex("FA00"),
        uuid_characteristic = string.fromHex(target_uuid)
    }
    
    local has_notify = (props & 0x40) ~= 0
    local has_read = (props & 0x08) ~= 0
    
    local result = false
    
    if has_notify then
        -- 有Notify属性：直接通知主机
        result = ble_device:write_notify(params, data)
        log.info("BLE", "使用write_notify通知主机:", result)
    elseif has_read then
        -- 只有Read属性：设置特征值，等主机来读取
        result = ble_device:write_value(params, data)
        log.info("BLE", "使用write_value设置特征值(等主机读取):", result)
    else
        log.error("BLE", "特征值不支持发送操作（需要Notify或Read属性）")
        return false
    end
    
    if result then
        tx_count = tx_count + 1
    end
    return result
end

-- ==================== 连接管理 ====================

-- 断开连接
function ble_manager.disconnect()
    log.info("BLE", "===== 断开连接 =====")
    
    if not ble_device then
        log.error("BLE", "BLE设备未初始化")
        return false
    end
    
    if not conn_state then
        log.warn("BLE", "当前未连接")
        return true
    end
    
    -- 调用BLE断开连接API
    local result = ble_device:disconnect()
    if not result then
        log.error("BLE", "断开连接请求失败")
        return false
    end
    
    log.info("BLE", "断开连接请求已发送")
    return true
end

-- 停止广播，断开连接
function ble_manager.deinit()
    -- 停止广播
    if adv_state then
        ble_manager.stop_adv()
    end
    
    -- 断开连接
    if conn_state then
        ble_manager.disconnect()
    end
end

-- ==================== 回调函数 ====================

-- 设置状态变化回调
ble_manager.on_state_change = nil

-- 设置数据接收回调
ble_manager.on_data = nil

-- ==================== 模块导出 ====================
return ble_manager
