
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ble"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

log.info("main", "project name is ", PROJECT, "version is ", VERSION)

-- 通过boot按键方便刷Air8000S
function PWR8000S(val)
    gpio.set(23, val)
end

gpio.debounce(0, 1000)
gpio.setup(0, function()
    sys.taskInit(function()
        log.info("复位Air8000S")
        PWR8000S(0)
        sys.wait(20)
        PWR8000S(1)
    end)
end, gpio.PULLDOWN)

local function ble_callback(ble_device, ble_event, ble_param)
    if ble_event == ble.EVENT_SCAN_INIT then
        log.info("ble", "scan init")
    elseif ble_event == ble.EVENT_SCAN_REPORT then
        log.info("ble", "scan report", ble_param.rssi, ble_param.adv_addr:toHex(), ble_param.data:toHex())
    elseif ble_event == ble.EVENT_SCAN_STOP then
        log.info("ble", "scan stop")
    end
end

local bt_scan = false   -- 是否扫描蓝牙

sys.taskInit(function()
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

    sys.wait(15000)
    log.info("停止扫描")
    ble_device:scan_stop()

end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
