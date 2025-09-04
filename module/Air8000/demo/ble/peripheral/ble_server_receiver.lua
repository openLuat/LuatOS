--[[
@module  ble_server_receiver
@summary BLE server 数据接收应用功能模块
@version 1.0
@date    2025.08.29
@author  王世豪
@usage
本文件为BLE server 数据接收应用功能模块，核心业务逻辑为：
1. 处理接收到的BLE写入请求数据。

本文件的对外接口有1个：
1. ble_server_receiver.proc(service_uuid, char_uuid, data): 处理接收到的BLE写入请求数据
]]

local ble_server_receiver = {}

-- 处理接收到的BLE写入请求数据
function ble_server_receiver.proc(service_uuid, char_uuid, data)
    log.info("ble_server_receiver", "收到写入数据", service_uuid:toHex(), char_uuid:toHex(), data:toHex())

    sys.publish("RECV_BLE_WRITE_DATA", service_uuid, char_uuid, data)
end

return ble_server_receiver