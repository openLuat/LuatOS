--[[
@module  myble
@summary 蓝牙模块
@version 1.1
@date    2026.05.27
@description
    实现蓝牙广播和通信功能，支持iBeacon模式和数据传输
    本版本已移除 config 依赖与 fskv 写入，所有参数硬编码在顶部常量。
]]

local myble = {}

-- ========== 硬编码常量（原 config 默认值） ==========
local BLE_ENABLED            = true   -- 是否启用蓝牙
local BLE_ADVERTISE_INTERVAL = 1000   -- 默认广播间隔(毫秒)
local IBEACON_UUID           = "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0"
local IBEACON_MAJOR          = 1
local IBEACON_MINOR          = 1
local IBEACON_TX_POWER       = -59
-- ===================================================

-- 状态
local ble_enabled = BLE_ENABLED
local bluetooth_device = nil
local ble_device = nil
local is_advertising = false
local advertise_interval = BLE_ADVERTISE_INTERVAL

-- 蓝牙事件回调
local ble_event_callback = nil

-- 蓝牙事件处理
local function ble_event_cb(evt, param)
    log.info("BLE", "Event received:", evt, json.encode(param))

    if evt == bluetooth.EVENT_ADV_START then
        log.info("BLE", "Advertising started")
        is_advertising = true

    elseif evt == bluetooth.EVENT_ADV_STOP then
        log.info("BLE", "Advertising stopped")
        is_advertising = false

    elseif evt == bluetooth.EVENT_WRITE then
        log.info("BLE", "Write request received:", param)
        if ble_event_callback then
            ble_event_callback("write", param)
        end

    elseif evt == bluetooth.EVENT_CONNECT then
        log.info("BLE", "Connected")
        if ble_event_callback then
            ble_event_callback("connect", param)
        end

    elseif evt == bluetooth.EVENT_DISCONNECT then
        log.info("BLE", "Disconnected")
        if ble_event_callback then
            ble_event_callback("disconnect", param)
        end
    end
end

-- 初始化蓝牙模块
function myble.init()
    log.info("BLE", "Initializing Bluetooth module...")

    if not ble_enabled then
        log.info("BLE", "Bluetooth is disabled")
        return
    end

    bluetooth_device = bluetooth.init()
    if not bluetooth_device then
        log.error("BLE", "Failed to initialize bluetooth core")
        return
    end

    ble_device = bluetooth_device:ble(ble_event_cb)
    if not ble_device then
        log.error("BLE", "Failed to initialize BLE")
        return
    end

    ble_device:adv_create({
        interval_min = 1600,
        interval_max = 1600,
        adv_type = bluetooth.ADV_TYPE_ADV_IND,
        own_addr_type = bluetooth.PUBLIC,
        direct_addr_type = bluetooth.PUBLIC,
        direct_addr = nil,
        channel_map = 7,
        filter_policy = bluetooth.ADV_FILTER_ALLOW_ALL
    })

    local ibeacon_data = bluetooth.make_ibeacon_data(
        IBEACON_UUID,
        IBEACON_MAJOR,
        IBEACON_MINOR,
        IBEACON_TX_POWER
    )

    ble_device:adv_data(ibeacon_data)

    log.info("BLE", "Initialization complete")
end

-- 设置事件回调
function myble.set_callback(callback)
    ble_event_callback = callback
end

-- 启动蓝牙广播
function myble.start_advertise(interval)
    if not ble_enabled or not ble_device then
        log.warn("BLE", "Bluetooth not enabled or not initialized")
        return false
    end

    if interval then
        advertise_interval = interval
        ble_device:adv_create({
            interval_min = interval * 1.6,
            interval_max = interval * 1.6,
            adv_type = bluetooth.ADV_TYPE_ADV_IND,
            own_addr_type = bluetooth.PUBLIC,
            direct_addr_type = bluetooth.PUBLIC,
            direct_addr = nil,
            channel_map = 7,
            filter_policy = bluetooth.ADV_FILTER_ALLOW_ALL
        })
    end

    log.info("BLE", "Starting advertise with interval:", advertise_interval)
    local ok, err = ble_device:adv_start()

    if ok then
        is_advertising = true
        log.info("BLE", "Advertise started successfully")
        return true
    else
        log.error("BLE", "Failed to start advertise:", err)
        return false
    end
end

-- 停止蓝牙广播
function myble.stop_advertise()
    if not ble_device then
        return
    end

    log.info("BLE", "Stopping advertise")
    ble_device:adv_stop()
    is_advertising = false
end

-- 停止蓝牙（关闭广播并释放资源）
function myble.stop()
    myble.stop_advertise()
    log.info("BLE", "Bluetooth stopped")
end

-- 启动蓝牙（初始化并启动广播）
function myble.start()
    if not bluetooth_device then
        myble.init()
    end
    myble.start_advertise()
end

-- 设置广播间隔（仅运行期生效，不持久化）
function myble.set_advertise_interval(interval)
    log.info("BLE", "Setting advertise interval to:", interval)
    advertise_interval = interval

    if is_advertising then
        myble.stop_advertise()
        myble.start_advertise(interval)
    end
end

-- 获取蓝牙状态
function myble.get_status()
    return {
        enabled = ble_enabled,
        advertising = is_advertising,
        interval = advertise_interval
    }
end

-- 发送数据给已连接设备
function myble.send(data)
    if not ble_device or not is_advertising then
        log.warn("BLE", "Cannot send, not advertising or not initialized")
        return false
    end

    log.info("BLE", "Sending data:", data)
    return true
end

-- 更新iBeacon参数
function myble.update_ibeacon(uuid, major, minor, tx_power)
    if not ble_device then
        return false
    end

    local ibeacon_data = bluetooth.make_ibeacon_data(uuid, major, minor, tx_power)
    ble_device:adv_data(ibeacon_data)

    log.info("BLE", "iBeacon updated:", uuid, major, minor)
    return true
end

return myble
