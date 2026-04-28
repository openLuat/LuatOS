--[[
@module  bluetooth_sim
@summary 模拟bluetooth库，用于PC模拟器环境
@version 1.0.0
@date    2026.04.22
]]

local bluetooth_sim = {}

-- 模拟常量定义
bluetooth_sim.PUBLIC = 0
bluetooth_sim.RANDOM = 1
bluetooth_sim.CHNLS_ALL = 0x07
bluetooth_sim.FLAGS = 0x01
bluetooth_sim.COMPLETE_LOCAL_NAME = 0x09
bluetooth_sim.MANUFACTURER_SPECIFIC_DATA = 0xFF

-- 事件常量
bluetooth_sim.EVENT_ADV_START = 1
bluetooth_sim.EVENT_ADV_STOP = 2
bluetooth_sim.EVENT_CONN = 3
bluetooth_sim.EVENT_DISCONN = 4
bluetooth_sim.EVENT_SCAN_INIT = 5
bluetooth_sim.EVENT_SCAN_REPORT = 6
bluetooth_sim.EVENT_SCAN_STOP = 7
bluetooth_sim.EVENT_WRITE = 8
bluetooth_sim.EVENT_READ = 9

-- 扫描模式
bluetooth_sim.SCAN_ACTIVE = 1

-- 全局变量
local g_callback = nil
local g_ble_device = nil
local g_scan_callback = nil
local g_data_callback = nil
local g_connected_device = nil
local g_is_scanning = false

-- adv_create 方法
local function ble_device_adv_create(self, config)
    log.info("bluetooth_sim", "ble_device:adv_create() called")
    local adv = {
        config = config,
        started = false
    }
    return adv
end

-- 延迟触发广告开始事件
local function ble_device_adv_start_timer()
    if g_callback then
        g_callback(g_ble_device, bluetooth_sim.EVENT_ADV_START)
    end
end

-- adv_start 方法
local function ble_device_adv_start(self, adv)
    log.info("bluetooth_sim", "ble_device:adv_start() called")
    if adv then
        adv.started = true
    end
    sys.timerStart(ble_device_adv_start_timer, 100)
    return true
end

-- adv_stop 方法
local function ble_device_adv_stop(self, adv)
    log.info("bluetooth_sim", "ble_device:adv_stop() called")
    if adv then
        adv.started = false
    end
    if g_callback then
        g_callback(g_ble_device, bluetooth_sim.EVENT_ADV_STOP)
    end
    return true
end

-- gatt_create 方法
local function ble_device_gatt_create(self, att_db)
    log.info("bluetooth_sim", "ble_device:gatt_create() called, att_db size: " .. tostring(#att_db))
    local gatt = {
        att_db = att_db
    }
    return gatt
end

-- notify 方法
local function ble_device_notify(self, uuid, data)
    log.info("bluetooth_sim", "ble_device:notify() called")
    return true
end

-- scan_create 方法
local function ble_device_scan_create(self, addr_mode, config)
    log.info("bluetooth_sim", "ble_device:scan_create() called")
    return {}
end

-- 延迟触发扫描开始事件
local function ble_device_scan_start_timer()
    if g_callback then
        g_callback(g_ble_device, bluetooth_sim.EVENT_SCAN_INIT)
    end
    g_is_scanning = true
end

-- scan_start 方法
local function ble_device_scan_start(self)
    log.info("bluetooth_sim", "ble_device:scan_start() called")
    sys.timerStart(ble_device_scan_start_timer, 100)
    return true
end

-- scan_stop 方法
local function ble_device_scan_stop(self)
    log.info("bluetooth_sim", "ble_device:scan_stop() called")
    if g_callback then
        g_callback(g_ble_device, bluetooth_sim.EVENT_SCAN_STOP)
    end
    g_is_scanning = false
    return true
end

-- write_notify 方法
local function ble_device_write_notify(self, params, data)
    log.info("bluetooth_sim", "ble_device:write_notify() called, data len: " .. tostring(#data))
    return true
end

-- write_value 方法
local function ble_device_write_value(self, params, data)
    log.info("bluetooth_sim", "ble_device:write_value() called, data len: " .. tostring(#data))
    return true
end

-- ble 方法
local function bluetooth_device_ble(self, callback)
    log.info("bluetooth_sim", "bluetooth_device:ble() called")
    g_callback = callback
    g_ble_device = {
        callback = callback,
        adv_create = ble_device_adv_create,
        adv_start = ble_device_adv_start,
        adv_stop = ble_device_adv_stop,
        gatt_create = ble_device_gatt_create,
        notify = ble_device_notify,
        scan_create = ble_device_scan_create,
        scan_start = ble_device_scan_start,
        scan_stop = ble_device_scan_stop,
        write_notify = ble_device_write_notify,
        write_value = ble_device_write_value
    }
    return g_ble_device
end

-- 模拟蓝牙设备对象
local bluetooth_device_mt = {
    __index = {
        ble = bluetooth_device_ble
    }
}

-- 初始化蓝牙
function bluetooth_sim.init()
    log.info("bluetooth_sim", "bluetooth.init() called (simulation)")
    local bluetooth_device = {
        ble = bluetooth_device_mt.__index.ble
    }
    setmetatable(bluetooth_device, bluetooth_device_mt)
    return bluetooth_device
end

-- 创建 ble 对象（包含 GATT 特征属性常量和方法）
local ble_constants = {
    READ = 0x02,
    WRITE = 0x08,
    WRITE_CMD = 0x04,
    NOTIFY = 0x10,
    INDICATE = 0x20,
    -- 地址模式
    PUBLIC = 0,
    RANDOM = 1,
    -- 通道
    CHNLS_ALL = 0x07,
    -- 广播数据类型
    FLAGS = 0x01,
    COMPLETE_LOCAL_NAME = 0x09,
    MANUFACTURER_SPECIFIC_DATA = 0xFF,
    -- 事件类型
    EVENT_ADV_START = 1,
    EVENT_ADV_STOP = 2,
    EVENT_CONN = 3,
    EVENT_DISCONN = 4,
    EVENT_SCAN_INIT = 5,
    EVENT_SCAN_REPORT = 6,
    EVENT_SCAN_STOP = 7,
    EVENT_WRITE = 8,
    EVENT_READ = 9,
    -- 扫描模式
    SCAN_ACTIVE = 1,
    -- 扫描方法
    scan = function(callback)
        log.info("bluetooth_sim", "ble.scan() called")
        g_scan_callback = callback
        -- 模拟发现一些设备
        sys.timerStart(function()
            if g_scan_callback then
                g_scan_callback("11:22:33:44:55:66", "模拟设备1", -50)
            end
        end, 500)
        sys.timerStart(function()
            if g_scan_callback then
                g_scan_callback("AA:BB:CC:DD:EE:FF", "模拟设备2", -60)
            end
        end, 1000)
    end,
    -- 连接方法
    connect = function(addr)
        log.info("bluetooth_sim", "ble.connect() called, addr: " .. addr)
        g_connected_device = addr
        -- 模拟连接成功
        sys.timerStart(function()
            if g_callback then
                g_callback(g_ble_device, bluetooth_sim.EVENT_CONN, {conn_id = 1, peer_addr = addr})
            end
        end, 500)
        return true
    end,
    -- 断开连接
    disconnect = function(device)
        log.info("bluetooth_sim", "ble.disconnect() called")
        g_connected_device = nil
        if g_callback then
            g_callback(g_ble_device, bluetooth_sim.EVENT_DISCONN, {conn_id = 1})
        end
        return true
    end,
    -- 数据接收回调
    onData = function(callback)
        log.info("bluetooth_sim", "ble.onData() called")
        g_data_callback = callback
    end
}

-- 导出到全局bluetooth
local function export_to_global()
    if not _G.bluetooth then
        _G.bluetooth = {}
    end

    for k, v in pairs(bluetooth_sim) do
        _G.bluetooth[k] = v
    end

    -- 导出 ble 对象到全局
    _G.ble = ble_constants
    log.info("bluetooth_sim", "模拟bluetooth库已加载到全局")
end

-- 自动检测并加载
if rtos ~= nil and rtos.bsp ~= nil then
    local bsp_name = rtos.bsp()
    if bsp_name == "PC" then
        log.info("bluetooth_sim", "检测到PC模拟器环境，加载模拟bluetooth库")
        export_to_global()
    end
end

return bluetooth_sim
