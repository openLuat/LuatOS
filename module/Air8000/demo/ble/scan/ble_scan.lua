--[[
本文件为Air8000核心板演示peripheral功能的代码示例，核心业务逻辑为：
广播者模式(ibeacon)的基本流程(概要描述)
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

local function ble_callback(ble_device, ble_event, ble_param)
    if ble_event == ble.EVENT_SCAN_INIT then
        log.info("ble", "scan init")
    elseif ble_event == ble.EVENT_SCAN_REPORT then
        log.info("ble", "scan report", ble_param.rssi, ble_param.adv_addr:toHex(), ble_param.data:toHex())
        -- 解析广播数据, 日志很多, 按需使用
        -- local adv_data = ble_device:adv_decode(ble_param.data)
        -- if adv_data then
        --     for k, v in pairs(adv_data) do
        --         log.info("ble", "adv data", v.len, v.tp, v.data:toHex())
        --     end
        -- end
        -- if ble_param.data:byte(1) == 0x1A then
        --     log.info("ble", "ibeacon数据", ble_param.rssi, ble_param.adv_addr:toHex(), ble_param.data:toHex())
        -- end
    elseif ble_event == ble.EVENT_SCAN_STOP then
        log.info("ble", "scan stop")
    end
end

local bt_scan = false   -- 是否扫描蓝牙

function ble_scan()
    sys.wait(500)
    log.info("开始初始化蓝牙核心")
    bluetooth_device = bluetooth.init()
    sys.wait(100)
    log.info("初始化BLE功能")
    ble_device = bluetooth_device:ble(ble_callback)
    if ble_device == nil then
        log.error("当前固件不支持完整的BLE")
        return
    end
    sys.wait(100)
    -- 扫描模式
    sys.wait(1000)
    ble_device:scan_create() -- 使用默认参数, addr_mode=0, scan_interval=100, scan_window=100
    -- ble_device:scan_create(0, 10, 10) -- 使用自定义参数
    sys.wait(100)
    log.info("开始扫描")
    ble_device:scan_start()

    -- sys.wait(15000)
    -- log.info("停止扫描")
    -- ble_device:scan_stop()

end

sys.taskInit(ble_scan)