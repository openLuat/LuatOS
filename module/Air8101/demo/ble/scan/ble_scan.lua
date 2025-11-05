--[[
@module  ble_ibeacon
@summary Air8101演示scan功能模块
@version 1.0
@date    2025.10.21
@author  王世豪
@usage
本文件为Air8101核心板演示scan功能的代码示例，核心业务逻辑为：
观察者模式(scan)的基本流程(概要描述)
1. 初始化蓝牙框架
2. 创建BLE对象
local ble_device = bluetooth_device:ble(ble_event_cb)
3.设置扫描模式
ble_device:scan_create() -- 使用默认参数, addr_mode=0, scan_interval=100, scan_window=100
4. 开始扫描
ble_device:scan_start()
5. 在回调函数中处理扫描事件, 如接收设备信息等
6. 按需停止扫描
ble_device:scan_stop()
]]

-- 扫描状态
local scan_state = false

-- 处理扫描报告事件
local function handle_scan_report(ble_device, ble_param)
    -- 基础设备信息
    log.info("ble_scan", "发现设备", 
            "RSSI:", ble_param.rssi, 
            "地址:", ble_param.adv_addr:toHex(),
            "数据:", ble_param.data:toHex())
    
    -- -- 解析广播数据
    -- local adv_data = ble_device:adv_decode(ble_param.data)
    
    -- if adv_data then
    --     for k, v in pairs(adv_data) do
    --         -- log.info("ble_scan", "广播数据", "长度:", v.len, "类型:", v.tp, "数据:", v.data:toHex())
            
    --         -- 以下是演示如何筛选ibeacon广播数据
    --         -- 检查Manufacturer Specific Data (类型0xFF)
    --         if v.tp == 0xFF then
    --             local mfg_data = v.data
    --             -- iBeacon格式检查
    --             if mfg_data:len() >= 25 then
    --                 local company_id = mfg_data:byte(1) + mfg_data:byte(2) * 256
    --                 local beacon_type = mfg_data:byte(3)      -- 0x02
    --                 local data_length = mfg_data:byte(4)      -- 0x15 (21字节)
                    
    --                 if beacon_type == 0x02 and data_length == 0x15 then
    --                     log.info("ble_scan", "发现iBeacon设备")
                        
    --                     -- 解析iBeacon数据
    --                     local uuid = mfg_data:sub(5, 20):toHex()
    --                     local major = mfg_data:byte(21) * 256 + mfg_data:byte(22)
    --                     local minor = mfg_data:byte(23) * 256 + mfg_data:byte(24)
    --                     local tx_power_byte = mfg_data:byte(25)
    --                     local tx_power
    --                     if tx_power_byte > 127 then
    --                         tx_power = tx_power_byte - 256
    --                     else
    --                         tx_power = tx_power_byte
    --                     end
                        
    --                     log.info("ble_scan", "iBeacon详情", 
    --                             "UUID:", uuid,
    --                             "Major:", major,
    --                             "Minor:", minor,
    --                             "TxPower:", tx_power.. " dBm",
    --                             "RSSI:", ble_param.rssi .. " dBm")
    --                 end
    --             end
    --         end
    --     end
    -- end
end

-- 事件回调函数
local function ble_callback(ble_device, ble_event, ble_param)
    -- 扫描初始化事件
    if ble_event == ble.EVENT_SCAN_INIT then
        log.info("ble_scan", "scan init")
        scan_state = true
    -- 扫描报告事件
    elseif ble_event == ble.EVENT_SCAN_REPORT then
        handle_scan_report(ble_device, ble_param)
    -- 停止扫描事件
    elseif ble_event == ble.EVENT_SCAN_STOP then
        log.info("ble_scan", "scan stop")
        scan_state = false
        -- 在这里可以添加自己的扫描停止后的处理逻辑
    end
end

function ble_scan_task_func()
    while true do
        -- 初始化蓝牙核心
        bluetooth_device = bluetooth_device or bluetooth.init()
        if not bluetooth_device then
            log.error("BLE", "蓝牙初始化失败")
            goto EXCEPTION_PROC
        end

        -- 初始化BLE功能
        ble_device = ble_device or bluetooth_device:ble(ble_callback)
        if not ble_device then
            log.error("BLE", "当前固件不支持完整的BLE")
            goto EXCEPTION_PROC
        end

        -- 创建扫描
        if not ble_device:scan_create() then
            log.error("BLE", "BLE创建扫描失败")
            goto EXCEPTION_PROC
        end

        log.info("ble_scan", "开始扫描")
        if not ble_device:scan_start() then
            log.error("ble_scan", "扫描启动失败")
            goto EXCEPTION_PROC
        end

        scan_state  = true

        -- 等待直到扫描停止
        while scan_state do
            sys.wait(1000)
        end
        ::EXCEPTION_PROC::

        log.info("ble_scan", "检测到扫描异常，准备重新初始化")
        -- 停止扫描
        if ble_device then
            ble_device:scan_stop()
            ble_device = nil
        end

        -- 5秒后跳转到循环体开始位置，重新扫描
        sys.wait(5000)
    end
end

-- 启动扫描任务
sys.taskInit(ble_scan_task_func)
