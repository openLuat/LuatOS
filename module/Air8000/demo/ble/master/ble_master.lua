--[[
@module  ble_ibeacon
@summary Air8000演示ibeacon功能模块
@version 1.0
@date    2025.07.01
@author  wangshihao
@usage
本文件为Air8000核心板演示master功能的代码示例，核心业务逻辑为：
1. 初始化蓝牙底层框架
    bluetooth_device = bluetooth.init()
2. 创建BLE对象实例
    local ble_device = bluetooth_device:ble(ble_event_cb)
3. 创建BLE扫描
    ble_device:scan_create({})
4. 开始BLE扫描
    ble_device:scan_start()
5. 在回调函数中处理事件
    a. 扫描报告事件（ble.EVENT_SCAN_REPORT）
        - 每收到一个扫描report，计数器'scan_count'加1。
        - 如果扫描次数超过100次，停止扫描，15秒后重新开始（防止过度扫描）。
        - 检查扫描到的设备广播数据中是否包含"LuatOS"字符串，并且地址类型为0（公开地址）。如果满足条件，停止扫描并尝试连接该设备。
    b. 连接事件（ble.EVENT_CONN）
        - 连接成功，打印日志。
    c. 断开连接事件（ble.EVENT_DISCONN）
        - 打印日志，重新开始扫描。
    d. 读写数据事件（ble.EVENT_READ_VALUE, ble.EVENT_WRITE）
        - 打印日志。
    e. 通知事件（ble.EVENT_NOTIFY）
        - 打印日志。
    f. GATT事件（ble.EVENT_GATT_ITEM, ble.EVENT_GATT_DONE）
        - 开启指定服务（UUID:FA00）和特征值（UUID:EA01）的通知功能。
        - 向特征值（UUID:EA02）写入数据（十六进制数据"1234"）。
        - 读取特征值（UUID:EA03）的数据。
]]

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
    elseif ble_event == ble.EVENT_GATT_ITEM then
        -- 读取GATT完成, 打印出来
        log.info("ble", "gatt item", ble_param)
    elseif ble_event == ble.EVENT_GATT_DONE then
        log.info("ble", "gatt done", ble_param.service_num)
        local wt = {uuid_service = string.fromHex("FA00"), uuid_characteristic = string.fromHex("EA01")}
        ble_device:notify_enable(wt, true) -- 开启通知

        -- 主动写入数据, 但不带通知, 带通知是 write_notify
        local wt = {uuid_service = string.fromHex("FA00"), uuid_characteristic = string.fromHex("EA02")}
        ble_device:write_value(wt,string.fromHex("1234"))

        local wt = {uuid_service = string.fromHex("FA00"), uuid_characteristic = string.fromHex("EA03")}
        ble_device:read_value(wt)
    end
end

function ble_master()
    log.info("开始初始化蓝牙核心")
    bluetooth_device = bluetooth.init()
    log.info("初始化BLE功能")
    ble_device = bluetooth_device:ble(ble_callback)

    -- master
    ble_device:scan_create({})
    ble_device:scan_start()
    -- ble_device:scan_stop()
end

sys.taskInit(ble_master)