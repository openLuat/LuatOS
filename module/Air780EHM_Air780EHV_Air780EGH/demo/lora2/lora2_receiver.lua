--[[
@module  lora2_receiver
@summary lora数据接收应用功能模块
@version 1.1
@date    2026.3.10
@author  王世豪
@usage
本文件为lora数据接收应用功能模块，核心业务逻辑为：
1. 处理接收到的lora数据。

本文件的对外接口有：
1. lora2_receiver.proc(data, size, rssi, snr): 处理接收到的lora数据。
2. sys.publish("LORA_RECV_DATA", {data=data, size=size, rssi=rssi, snr=snr}): 发布包含信号强度信息的数据给其他模块处理。
]]

local lora2_receiver = {}

-- 处理接收到的lora数据
function lora2_receiver.proc(data, size, rssi, snr)
    log.info("lora2_receiver", "收到数据:", data, "RSSI:", rssi, "dBm", "SNR:", snr, "dB")
    -- 发布包含信号强度信息的数据给其他模块
    sys.publish("LORA_RECV_DATA", {data=data, size=size, rssi=rssi, snr=snr})
end

return lora2_receiver