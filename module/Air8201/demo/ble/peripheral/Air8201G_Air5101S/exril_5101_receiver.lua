--[[
@module  exril_5101_receiver
@summary BLE 数据接收应用功能模块
@version 1.1
@date    2026.03.02
@author  王世豪
@usage
本文件为BLE 数据接收应用功能模块，核心业务逻辑为：
1. 处理接收到的BLE写入请求数据
2. 发布"RECV_BLE_DATA"消息供其他模块订阅

本文件的对外接口有1个：
1. exril_5101_receiver.proc(mode, data): 处理接收到的BLE数据
]]

local exril_5101_receiver = {}

-- 处理接收到的BLE数据
function exril_5101_receiver.proc(mode, data)
    log.info("exril_5101_receiver", "收到数据 [模式:" .. mode .. "]:", data)
    
    -- 发布消息供其他模块订阅
    sys.publish("RECV_BLE_DATA", mode, data)
end

return exril_5101_receiver
