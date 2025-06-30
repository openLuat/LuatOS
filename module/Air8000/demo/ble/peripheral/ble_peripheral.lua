--[[
本文件为Air8000核心板演示peripheral功能的代码示例，核心业务逻辑为：
从机模式(peripheral)的基本流程(概要描述)
1. 初始化蓝牙框架
2. 创建BLE对象
    local ble_device = bluetooth_device:ble(ble_event_cb)
3. 创建GATT描述
    local att_db = {xxx}
4. 创建广播信息
    ble_device:adv_create(adv_data)
5. 开始广播
    ble_device:adv_start()
6. 等待连接
7. 在回调函数中处理连接事件, 如接收数据, 发送数据等
]]

local att_db = { -- Service
    string.fromHex("FA00"), -- Service UUID
    -- Characteristic
    { -- Characteristic 1
        string.fromHex("EA01"), -- Characteristic UUID Value
        ble.NOTIFY | ble.READ | ble.WRITE -- Properties
    }, { -- Characteristic 2
        string.fromHex("EA02"), ble.WRITE
    }, { -- Characteristic 3
        string.fromHex("EA03"), ble.READ
    }, { -- Characteristic 4
        string.fromHex("EA04"), ble.IND | ble.READ
    }
}

ble_stat = false

local function ble_callback(dev, evt, param)
    if evt == ble.EVENT_CONN then
        log.info("ble", "connect 成功", param, param and param.addr and param.addr:toHex() or "unknow")
        ble_stat = true
    elseif evt == ble.EVENT_DISCONN then
        log.info("ble", "disconnect")
        ble_stat = false
        -- 1秒后重新开始广播
        sys.timerStart(function() dev:adv_start() end, 1000)
    elseif evt == ble.EVENT_WRITE then
        -- 收到写请求
        log.info("ble", "接收到写请求", param.uuid_service:toHex(), param.uuid_characteristic:toHex(), param.data:toHex())
    end
end

local bt_scan = false -- 是否扫描蓝牙

function ble_peripheral()
    local ret = 0
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

    log.info('开始创建GATT')
    ret = ble_device:gatt_create(att_db)
    log.info("创建的GATT", ret)

    sys.wait(100)
    log.info("开始设置广播内容")
    ble_device:adv_create({
        addr_mode = ble.PUBLIC,
        channel_map = ble.CHNLS_ALL,
        intv_min = 120,
        intv_max = 120,
        adv_data = {
            {ble.FLAGS, string.char(0x06)},
            {ble.COMPLETE_LOCAL_NAME, "LuatOS123"},
            {ble.SERVICE_DATA, string.fromHex("FE01")},
            {ble.MANUFACTURER_SPECIFIC_DATA, string.fromHex("05F0")}
        }
    })

    sys.wait(100)
    log.info("开始广播")
    ble_device:adv_start()

        
    -- 放入预设值, 注意是有READ属性的特性才能读取
    -- 手机APP设置MTU到256
    local wt = {
        uuid_service = string.fromHex("FA00"),
        uuid_characteristic = string.fromHex("EA01"), 
    }
    ble_device:write_value(wt, "12345678901234567890")

    while 1 do
        sys.wait(3000)
        if ble_stat then
            local wt = {
                uuid_service = string.fromHex("FA00"),
                uuid_characteristic = string.fromHex("EA01"), 
            }
            local result = ble_device:write_notify(wt, "123456" .. os.date())
            log.info("ble", "发送数据", result)
        else
            -- log.info("等待连接成功之后发送数据")
        end
        
        local wt = {
            uuid_service = string.fromHex("FA00"),
            uuid_characteristic = string.fromHex("EA03"), 
        }
        ble_device:write_value(wt, "8888 123454")
    end
end

sys.taskInit(ble_peripheral)
