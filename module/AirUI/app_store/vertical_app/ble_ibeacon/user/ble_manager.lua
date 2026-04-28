--[[
@module  ble_manager
@summary BLE管理器，负责iBeacon广播功能
@version 1.0.0
@date    2026.04.07
@author  王世豪
]]

-- PC模拟器环境检测，加载模拟蓝牙库
if rtos ~= nil and rtos.bsp ~= nil then
    local bsp_name = rtos.bsp()
    if bsp_name == "PC" then
        local bluetooth = require "bluetooth_sim"
    end
end

local ble_manager = {}

-- 广播状态
local adv_state = false
local ble_device = nil
local adv_create = nil

-- iBeacon配置参数（默认值）
-- 开发测试ID: 0xFFFF
local ibeacon_config = {
    manufacturer_id = 0xFFFF,  -- 默认使用开发测试ID
    uuid = "01020304-0506-0708-090A-0B0C0D0E0F10",
    major = 1,
    minor = 2,
    tx_power = -64,  -- TX Power，单位dBm（-64 = 0xC0 补码）
    adv_interval = 120
}

-- fskv键定义
local KEY_IBEACON_MANUFACTURER_ID = "ibeacon_manuf_id"
local KEY_IBEACON_UUID = "ibeacon_uuid"
local KEY_IBEACON_MAJOR = "ibeacon_major"
local KEY_IBEACON_MINOR = "ibeacon_minor"
local KEY_IBEACON_TX_POWER = "ibeacon_tx_power"
local KEY_IBEACON_ADV_INTERVAL = "ibeacon_adv_int"

-- 初始化fskv
local function fskv_init()
    if not fskv then
        return false
    end
    local ok, err = pcall(fskv.init)
    if not ok then
        log.error("BLE", "fskv初始化失败:", err)
        return false
    end
    return true
end

-- 从fskv加载配置
local function load_config_from_fskv()
    if not fskv then
        log.warn("BLE", "fskv不可用，跳过fskv加载")
        return false
    end
    
    if not fskv_init() then
        return false
    end
    
    local manufacturer_id = fskv.get(KEY_IBEACON_MANUFACTURER_ID)
    if manufacturer_id then
        ibeacon_config.manufacturer_id = tonumber(manufacturer_id) or ibeacon_config.manufacturer_id
    end
    
    local uuid = fskv.get(KEY_IBEACON_UUID)
    if uuid then
        ibeacon_config.uuid = uuid
    end
    
    local major = fskv.get(KEY_IBEACON_MAJOR)
    if major then
        ibeacon_config.major = tonumber(major) or ibeacon_config.major
    end
    
    local minor = fskv.get(KEY_IBEACON_MINOR)
    if minor then
        ibeacon_config.minor = tonumber(minor) or ibeacon_config.minor
    end
    
    local tx_power = fskv.get(KEY_IBEACON_TX_POWER)
    if tx_power then
        ibeacon_config.tx_power = tonumber(tx_power) or ibeacon_config.tx_power
    end
    
    local adv_interval = fskv.get(KEY_IBEACON_ADV_INTERVAL)
    if adv_interval then
        ibeacon_config.adv_interval = tonumber(adv_interval) or ibeacon_config.adv_interval
    end
    
    log.info("BLE", "从fskv加载配置成功")
    return true
end

-- 生成iBeacon数据包
function ble_manager.generate_ibeacon_data()
    -- 解析UUID字符串为字节数组
    local uuid_bytes = {}
    local uuid_str = ibeacon_config.uuid:gsub("-", "")
    for i = 1, #uuid_str, 2 do
        local byte_str = uuid_str:sub(i, i+1)
        table.insert(uuid_bytes, tonumber(byte_str, 16))
    end

    -- 分解Manufacturer ID为两个字节
    local manuf_id = ibeacon_config.manufacturer_id or 0xFFFF
    local manuf_id_low = manuf_id % 256
    local manuf_id_high = math.floor(manuf_id / 256)

    -- TX Power是有符号字节，需要转换为无符号字节（补码）
    local tx_power_byte = ibeacon_config.tx_power
    if tx_power_byte < 0 then
        tx_power_byte = tx_power_byte + 256
    end

    -- 构建iBeacon数据包
    local ibeacon_data = string.char(
        manuf_id_low, manuf_id_high, -- Manufacturer ID (小端序)
        0x02, -- iBeacon类型
        0x15, -- 数据长度 (21 bytes)
        uuid_bytes[1], uuid_bytes[2], uuid_bytes[3], uuid_bytes[4], -- UUID部分
        uuid_bytes[5], uuid_bytes[6], uuid_bytes[7], uuid_bytes[8],
        uuid_bytes[9], uuid_bytes[10], uuid_bytes[11], uuid_bytes[12],
        uuid_bytes[13], uuid_bytes[14], uuid_bytes[15], uuid_bytes[16],
        math.floor(ibeacon_config.major / 256), ibeacon_config.major % 256, -- Major
        math.floor(ibeacon_config.minor / 256), ibeacon_config.minor % 256, -- Minor
        tx_power_byte -- Tx Power（转换为无符号字节）
    )

    return ibeacon_data
end

-- BLE事件回调函数
local function ble_callback(ble_device, ble_event)
    log.info("BLE", "===== BLE事件回调 =====")
    log.info("BLE", "ble_event=", ble_event)
    
    -- 使用全局变量 _G.ibeacon_win
    local win = _G.ibeacon_win
    log.info("BLE", "检查 _G.ibeacon_win: ", win ~= nil)
    
    if ble_event == ble.EVENT_ADV_START then
        log.info("BLE", "收到 EVENT_ADV_START 事件")
        adv_state = true
        -- 通知UI更新状态
        if win and win.update_broadcast_status then
            win.update_broadcast_status(true)
        else
            log.error("BLE", "_G.ibeacon_win 或 update_broadcast_status 不存在")
        end
    elseif ble_event == ble.EVENT_ADV_STOP then
        log.info("BLE", "收到 EVENT_ADV_STOP 事件")
        adv_state = false
        -- 通知UI更新状态
        if win and win.update_broadcast_status then
            win.update_broadcast_status(false)
        else
            log.error("BLE", "_G.ibeacon_win 或 update_broadcast_status 不存在")
        end
    else
        log.info("BLE", "其他BLE事件: ", ble_event)
    end
end

-- 初始化BLE管理器
function ble_manager.init()
    log.info("BLE", "===== 初始化BLE管理器 =====")
    log.info("BLE", "检查bluetooth模块: ", bluetooth ~= nil)

    -- 加载配置：从fskv加载配置
    load_config_from_fskv()

    log.info("BLE", "当前配置 - Manufacturer ID: ", string.format("0x%04X", ibeacon_config.manufacturer_id))
    log.info("BLE", "当前配置 - UUID: ", ibeacon_config.uuid)
    log.info("BLE", "当前配置 - Major: ", ibeacon_config.major)
    log.info("BLE", "当前配置 - Minor: ", ibeacon_config.minor)
    log.info("BLE", "当前配置 - TX Power: ", ibeacon_config.tx_power)
    log.info("BLE", "当前配置 - Adv Interval: ", ibeacon_config.adv_interval)

    -- 初始化蓝牙
    local bluetooth_device = bluetooth.init()
    if not bluetooth_device then
        log.error("BLE", "蓝牙初始化失败 - bluetooth.init() 返回 nil")
        return false
    end
    log.info("BLE", "bluetooth.init() 成功: ", bluetooth_device ~= nil)

    -- 初始化BLE功能
    ble_device = bluetooth_device:ble(ble_callback)
    if not ble_device then
        log.error("BLE", "BLE功能初始化失败 - bluetooth_device:ble() 返回 nil")
        return false
    end
    log.info("BLE", "bluetooth_device:ble() 成功: ", bluetooth_device ~= nil)

    log.info("BLE", "BLE管理器初始化成功")
    return true
end

-- 启动iBeacon广播
function ble_manager.start_broadcast()
    log.info("BLE", "===== 启动iBeacon广播 =====")
    log.info("BLE", "当前adv_state: ", adv_state)
    log.info("BLE", "检查ble_device: ", ble_device ~= nil)
    
    if adv_state then
        log.warn("BLE", "广播已在运行中")
        return true
    end
    
    if not ble_device then
        log.error("BLE", "BLE设备未初始化")
        return false
    end
    
    -- 生成iBeacon数据
    log.info("BLE", "生成iBeacon数据包")
    local ibeacon_data = ble_manager.generate_ibeacon_data()
    log.info("BLE", "iBeacon数据长度: ", #ibeacon_data .. " 字节")
    
    -- 检查ble模块
    log.info("BLE", "检查ble模块: ", ble ~= nil)
    
    -- 创建广播配置
    log.info("BLE", "调用 ble_device:adv_create()")
    adv_create = ble_device:adv_create({
        addr_mode = ble.PUBLIC,
        channel_map = ble.CHNLS_ALL,
        intv_min = ibeacon_config.adv_interval,
        intv_max = ibeacon_config.adv_interval,
        adv_data = {
            {ble.FLAGS, string.char(0x06)},
            {ble.MANUFACTURER_SPECIFIC_DATA, ibeacon_data},
        }
    })
    
    if not adv_create then
        log.error("BLE", "创建广播配置失败 - ble_device:adv_create() 返回 nil")
        return false
    end
    log.info("BLE", "adv_create 创建成功: ", adv_create ~= nil)
    
    -- 启动广播
    log.info("BLE", "调用 ble_device:adv_start()")
    local start_result = ble_device:adv_start()
    if not start_result then
        log.error("BLE", "启动广播失败 - ble_device:adv_start() 返回 false")
        return false
    end
    log.info("BLE", "ble_device:adv_start() 返回: ", start_result)
    
    adv_state = true
    log.info("BLE", "iBeacon广播启动成功，adv_state=", adv_state)
    return true
end

-- 停止iBeacon广播
function ble_manager.stop_broadcast()
    if not adv_state then
        log.warn("BLE", "广播已停止")
        return true
    end
    
    if not adv_create then
        log.error("BLE", "广播对象不存在")
        return false
    end
    
    -- 停止广播（正确API：ble_device:adv_stop()）
    log.info("BLE", "调用 ble_device:adv_stop()")
    local stop_result = ble_device:adv_stop()
    if not stop_result then
        log.error("BLE", "停止广播失败 - ble_device:adv_stop() 返回 false")
        return false
    end
    log.info("BLE", "ble_device:adv_stop() 返回: ", stop_result)

    log.info("BLE", "iBeacon广播已停止，adv_state=", adv_state)
    adv_state = false
    return true
end

-- 获取广播状态
function ble_manager.get_broadcast_status()
    return adv_state
end

-- 更新iBeacon配置
function ble_manager.update_config(config)
    if config.uuid then
        ibeacon_config.uuid = config.uuid
    end
    if config.major then
        ibeacon_config.major = config.major
    end
    if config.minor then
        ibeacon_config.minor = config.minor
    end
    if config.tx_power then
        ibeacon_config.tx_power = config.tx_power
    end
    if config.adv_interval then
        ibeacon_config.adv_interval = config.adv_interval
    end
    
    log.info("BLE", "iBeacon配置已更新")
    return true
end

-- 获取当前配置
function ble_manager.get_config()
    return {
        manufacturer_id = ibeacon_config.manufacturer_id,
        uuid = ibeacon_config.uuid,
        major = ibeacon_config.major,
        minor = ibeacon_config.minor,
        tx_power = ibeacon_config.tx_power,
        adv_interval = ibeacon_config.adv_interval
    }
end

-- 获取fskv键定义（供config_win使用）
function ble_manager.get_fskv_keys()
    return {
        manufacturer_id = KEY_IBEACON_MANUFACTURER_ID,
        uuid = KEY_IBEACON_UUID,
        major = KEY_IBEACON_MAJOR,
        minor = KEY_IBEACON_MINOR,
        tx_power = KEY_IBEACON_TX_POWER,
        adv_interval = KEY_IBEACON_ADV_INTERVAL
    }
end

-- fskv初始化（供config_win使用）
function ble_manager.fskv_init()
    return fskv_init()
end

return ble_manager