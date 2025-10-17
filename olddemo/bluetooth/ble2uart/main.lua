
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ble2uart"
VERSION = "1.0.0"

log.info("main", "project name is ", PROJECT, "version is ", VERSION)


local QUEUE_MAX_LEN = 10
local txQueue = {}
local rxQueue = {}
local txTaskName = "TX_TRANS_TASK"
local rxTaskName = "RX_TRANS_TASK"
local MAX_MTU = 240 -- TODO, 根据实际MTU大小变化

local uartId = 1
local uartBaudrate = 115200


local ble_isconnected = false
local scan_count = 0

local function ble_callback(ble_device, ble_event, ble_param)
    if ble_event == ble.EVENT_CONN then
        log.info("ble", "connect 成功")
    elseif ble_event == ble.EVENT_DISCONN then
        log.info("ble", "disconnect", ble_param.reason)
        ble_isconnected = false
        sys.timerStart(function() ble_device:scan_start() end, 1000)
    elseif ble_event == ble.EVENT_WRITE then
        log.info("ble", "write", ble_param.handle,ble_param.uuid_service:toHex(),ble_param.uuid_characteristic:toHex())
        log.info("ble", "data", ble_param.data:toHex())
    elseif ble_event == ble.EVENT_READ_VALUE then
        log.info("ble", "read", ble_param.handle,ble_param.uuid_service:toHex(),ble_param.uuid_characteristic:toHex(),ble_param.data:toHex())
        table.insert(rxQueue, ble_param.data)
        sys.sendMsg(rxTaskName)
    elseif ble_event == ble.EVENT_SCAN_REPORT then
        log.info("ble scan report", ble_param.addr_type,ble_param.rssi,ble_param.adv_addr:toHex(),ble_param.data:toHex())
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
        ble_isconnected = true
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
end)



uart.setup(uartId, uartBaudrate)
uart.on(uartId,"receive", function(id, len)
    while 1 do
        local data = uart.read(id, 1024)
        if not data or #data == 0 then
            break
        end
        if #txQueue > QUEUE_MAX_LEN then
            table.revmoe(txQueue, 1)
        end
        table.insert(txQueue, data)
        sys.sendMsg(txTaskName)
    end
end)

local function txTransTask()
    while 1 do
        sys.waitMsg(txTaskName)
        if ble_isconnected then
            while 1 do
                if #txQueue <= 0 then
                    break
                end
                local data = table.remove(txQueue, 1)
                while 1 do
                    local tmp = data:sub(1, MAX_MTU)
                    log.info("tmp长度", #tmp)
                    if tmp and #tmp > 0 then
                        local wt = {uuid_service = string.fromHex("FA00"), uuid_characteristic = string.fromHex("EA02")}
                        ble_device:write_value(wt, tmp)
                    else
                        break 
                    end
                    data = data:sub(MAX_MTU + 1)
                end
            end
        end
    end
end

local function rxTransTask()
    while 1 do
        sys.waitMsg(rxTaskName)
        while 1 do
            if #rxQueue <= 0 then
                break
            end
            local data = table.remove(rxQueue, 1)
            uart.write(uartId, data)
        end
    end
end
sys.taskInitEx(txTransTask, txTaskName, nil)
sys.taskInitEx(rxTransTask, rxTaskName, nil)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
