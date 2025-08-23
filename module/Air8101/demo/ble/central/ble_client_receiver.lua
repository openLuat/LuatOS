-- --[[
-- @module  ble_client_receiver
-- @summary BLE client 数据接收应用功能模块
-- @version 1.0
-- @date    2025.08.20
-- @author  王世豪
-- @usage
-- 本文件为BLE client 数据接收应用功能模块，核心业务逻辑为：
-- 1. 处理接收到的BLE通知数据和主动读取到的数据，根据特征值类型（Notify或Read）进行分类处理。

-- 本文件的对外接口有3个：
-- 1. ble_client_receiver.proc(service_uuid, char_uuid, data): 处理接收到的BLE通知数据和主动读取数据。
-- 2. sys.publish("RECV_BLE_NOTIFY_DATA", service_uuid, char_uuid, data): 发布收到的通知数据给其他模块处理。
-- 3. sys.publish("RECV_BLE_READ_DATA", service_uuid, char_uuid, data): 发布读取到的数据给其他模块处理。
-- ]]

local ble_client_receiver = {}

-- 处理接收到的BLE通知数据和主动读取数据，根据特征值类型（Notify或Read）进行分类处理。
function ble_client_receiver.proc(service_uuid, char_uuid, data)
    -- 判断数据类型（主动读取或通知）
    -- 通知数据
    if char_uuid == config.target_notify_char then
        log.info("ble_client_receiver", "收到通知数据", service_uuid, char_uuid, data)
        -- 发布数据给其他模块
        sys.publish("RECV_BLE_NOTIFY_DATA", service_uuid, char_uuid, data)
        
    -- 主动读取数据
    elseif char_uuid == config.target_read_char then
        log.info("ble_client_receiver", "处理主动读取的数据", service_uuid, char_uuid, data)
        -- 发布数据给其他模块
        sys.publish("RECV_BLE_READ_DATA", service_uuid, char_uuid, data)
    end
end

return ble_client_receiver