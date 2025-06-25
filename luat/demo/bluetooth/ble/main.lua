
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ble"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

log.info("main", "project name is ", PROJECT, "version is ", VERSION)

local att_db = {--Service
        string.fromHex("FA00"),             --Service UUID
        -- Characteristic
        { -- Characteristic 1
            0xEA01,                         -- Characteristic UUID Value
            ble.NOTIFY|ble.READ|ble.WRITE,  -- Properties
            string.fromHex("1234")          -- Value

        },
        { -- Characteristic 2
            0xEA02,
            ble.WRITE,
        },
        { -- Characteristic 3
            0xEA03,
            ble.READ,
            string.fromHex("5678")
        },
        { -- Characteristic 4
            0xEA04,
            ble.NOTIFY|ble.READ|ble.WRITE,
        },
    }

local scan_count = 0

local function ble_callback(ble_device, ble_event, ble_param)
    if ble_event == ble.EVENT_CONN then
        log.info("ble", "connect 成功")
    elseif ble_event == ble.EVENT_DISCONN then
        log.info("ble", "disconnect")
        -- 1秒后重新开始广播
        sys.timerStart(function() ble_device:adv_start() end, 1000)
    elseif ble_event == ble.EVENT_WRITE then
        log.info("ble", "write", ble_param.handle,ble_param.uuid_service:toHex(),ble_param.uuid_characteristic:toHex())
        log.info("ble", "data", ble_param.data:toHex())
        -- ble_device:write_notify(ble_param,string.fromHex("123456"))
    elseif ble_event == ble.EVENT_READ_VALUE then
        log.info("ble", "read", ble_param.handle,ble_param.uuid_service:toHex(),ble_param.uuid_characteristic:toHex(),ble_param.data:toHex(),ble_param.data)
    elseif ble_event == ble.EVENT_SCAN_REPORT then
        print("ble scan report",ble_param.addr_type,ble_param.rssi,ble_param.adv_addr:toHex(),ble_param.data:toHex(),ble_param.data)
        scan_count = scan_count + 1
        if scan_count > 20 then
            ble_device:scan_stop()
        end
        if ble_param.addr_type == 0 and ble_param.data:find("LuatOS") then
            ble_device:scan_stop()
            ble_device:connect(ble_param.adv_addr,ble_param.addr_type)
        end
    elseif ble_event == 14 then

        local characteristic = {uuid_service = string.fromHex("FA00"), uuid_characteristic = string.fromHex("EA02")}
        ble_device:write_value(characteristic,string.fromHex("1234"))

        local characteristic = {uuid_service = string.fromHex("FA00"), uuid_characteristic = string.fromHex("EA03")}
        ble_device:read_value(characteristic)
    end
end


sys.taskInit(function()
    log.info("开始初始化蓝牙核心")
    bluetooth_device = bluetooth.init()
    log.info("初始化BLE功能")
    ble_device = bluetooth_device:ble(ble_callback)

    -- slaver
    log.info('开始创建GATT')
    ble_device:gatt_create(att_db)

    log.info("开始设置广播内容")
    ble_device:adv_create({
        addr_mode = ble.PUBLIC,
        channel_map = ble.CHNLS_ALL,
        intv_min = 120,
        intv_max = 120,
        adv_data = {
            {ble.FLAGS,string.char(0x06)},
            {ble.COMPLETE_LOCAL_NAME, "LuatOS"},
            {ble.SERVICE_DATA, string.fromHex("FE01")},
            {ble.MANUFACTURER_SPECIFIC_DATA, string.fromHex("05F0")},
        },
    })
    log.info("开始广播")
    ble_device:adv_start()
    -- ble_device:adv_stop()

    -- master
    -- ble_device:scan_create({})
    -- ble_device:scan_start()
    -- -- ble_device:scan_stop()

    while 1 do
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
