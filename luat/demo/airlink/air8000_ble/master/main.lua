
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ble"
VERSION = "1.0.0"

log.info("main", "project name is ", PROJECT, "version is ", VERSION)

-- 通过boot按键方便刷Air8000S
function PWR8000S(val) gpio.set(23, val) end

gpio.debounce(0, 1000)
gpio.setup(0, function()
    sys.taskInit(function()
        log.info("复位Air8000S")
        PWR8000S(0)
        sys.wait(20)
        PWR8000S(1)
    end)
end, gpio.PULLDOWN)

local scan_count = 0

local function ble_callback(ble_device, ble_event, ble_param)
    if ble_event == ble.EVENT_CONN then
        log.info("ble", "connect 成功")
    elseif ble_event == ble.EVENT_DISCONN then
        log.info("ble", "disconnect", ble_param.reason)
        sys.timerStart(function() ble_device:scan_start() end, 1000)
    elseif ble_event == ble.EVENT_WRITE then
        log.info("ble", "write", ble_param.handle,ble_param.uuid_service:toHex(),ble_param.uuid_characteristic:toHex())
        log.info("ble", "data", ble_param.data:toHex())
    elseif ble_event == ble.EVENT_READ_VALUE then
        log.info("ble", "read", ble_param.handle,ble_param.uuid_service:toHex(),ble_param.uuid_characteristic:toHex(),ble_param.data:toHex())
    elseif ble_event == ble.EVENT_SCAN_REPORT then
        print("ble scan report",ble_param.addr_type,ble_param.rssi,ble_param.adv_addr:toHex(),ble_param.data:toHex())
        scan_count = scan_count + 1
        if scan_count > 100 then
            log.info("ble", "扫描次数超过100次, 停止扫描, 15秒后重新开始")
            scan_count = 0
            ble_device:scan_stop()
            sys.timerStart(function() ble_device:scan_start() end, 15000)
        end
        -- 注意, 这里是连接到另外一个设备, 设备名称带LuatOS字样
        if ble_param.addr_type == 0 and ble_param.data:find("LuatOS") then
            log.info("ble", "停止扫描, 连接设备", ble_param.adv_addr:toHex(), ble_param.addr_type)
            ble_device:scan_stop()
            ble_device:connect(ble_param.adv_addr,ble_param.addr_type)
        end
    elseif ble_event == ble.EVENT_GATT_DONE then
        -- 读取GATT完成, 打印出来
        for k, v in pairs(ble_param) do
            log.info("ble", "gatt", k, v[1]:toHex())
        end
        local wt = {uuid_service = string.fromHex("FA00"), uuid_characteristic = string.fromHex("EA02")}
        ble_device:write_value(wt,string.fromHex("1234"))

        local wt = {uuid_service = string.fromHex("FA00"), uuid_characteristic = string.fromHex("EA03")}
        ble_device:read_value(wt)
    end
end


sys.taskInit(function()
    log.info("开始初始化蓝牙核心")
    bluetooth_device = bluetooth.init()
    log.info("初始化BLE功能")
    ble_device = bluetooth_device:ble(ble_callback)

    -- master
    ble_device:scan_create({})
    ble_device:scan_start()
    -- ble_device:scan_stop()
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
