--[[
@module  bluetooth_sim
@summary 模拟bluetooth库，用于PC模拟器环境
@version 1.0.0
@date    2026.04.09
@author  王世豪
]]

local bluetooth_sim = {}

-- 模拟常量定义
bluetooth_sim.PUBLIC = 0
bluetooth_sim.RANDOM = 1
bluetooth_sim.CHNLS_ALL = 0x07
bluetooth_sim.FLAGS = 0x01
bluetooth_sim.COMPLETE_LOCAL_NAME = 0x09
bluetooth_sim.MANUFACTURER_SPECIFIC_DATA = 0xFF
bluetooth_sim.EVENT_ADV_START = 1
bluetooth_sim.EVENT_ADV_STOP = 2
bluetooth_sim.EVENT_CONNECT = 12
bluetooth_sim.EVENT_DISCONNECT = 13
bluetooth_sim.EVENT_WRITE = 5
bluetooth_sim.EVENT_READ = 6

-- 全局事件回调
local g_callback = nil
local g_ble_device = nil

-- adv_create 方法
local function ble_device_adv_create(self, config)
    log.info("bluetooth_sim", "ble_device:adv_create() called")
    log.info("bluetooth_sim", "config: " .. json.encode(config))
    local adv = {
        config = config,
        started = false
    }
    return adv
end

-- 延迟触发广告开始事件回调
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
    -- 模拟延迟触发广告开始事件
    sys.timerStart(ble_device_adv_start_timer, 100)
    return true
end

-- adv_stop 方法
local function ble_device_adv_stop(self, adv)
    log.info("bluetooth_sim", "ble_device:adv_stop() called")
    if adv then
        adv.started = false
    end
    -- 触发广告停止事件
    if g_callback then
        g_callback(g_ble_device, bluetooth_sim.EVENT_ADV_STOP)
    end
    return true
end

-- gatt_create 方法
local function ble_device_gatt_create(self, att_db)
    log.info("bluetooth_sim", "ble_device:gatt_create() called")
    log.info("bluetooth_sim", "att_db size: " .. tostring(#att_db))
    local gatt = {
        att_db = att_db
    }
    return gatt
end

-- notify 方法
local function ble_device_notify(self, uuid, data)
    log.info("bluetooth_sim", "ble_device:notify() called")
    log.info("bluetooth_sim", "uuid: " .. (uuid and uuid:toHex() or "nil"))
    log.info("bluetooth_sim", "data: " .. (data or "nil"))
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
        notify = ble_device_notify
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

-- 创建 ble 对象（包含 GATT 特征属性常量）
local ble_constants = {
    READ = 0x02,
    WRITE = 0x08,
    WRITE_CMD = 0x04,
    NOTIFY = 0x10,
    INDICATE = 0x20
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
    log.info("bluetooth_sim", "ble 常量已导出: READ=0x02, WRITE=0x08, WRITE_CMD=0x04, NOTIFY=0x10, INDICATE=0x20")
end

-- 自动检测并加载
if rtos ~= nil and rtos.bsp ~= nil then
    local bsp_name = rtos.bsp()
    log.info("bluetooth_sim", "当前BSP: " .. bsp_name)
    if bsp_name == "PC" then
        log.info("bluetooth_sim", "检测到PC模拟器环境，加载模拟bluetooth库")
        export_to_global()
    end
end

return bluetooth_sim
