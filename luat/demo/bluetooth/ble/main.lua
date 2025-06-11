
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ble"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

log.info("main", "project name is ", PROJECT, "version is ", VERSION)

-- characteristic handle
local characteristic1,characteristic2,characteristic3,characteristic4

local att_db = {--Service
        string.fromHex("FA00"),             --Service UUID
        -- Characteristic
        { -- Characteristic 1
            string.fromHex("EA01"),         -- Characteristic UUID Value
            ble.NOTIFY|ble.READ|ble.WRITE,  -- Properties
        },
        { -- Characteristic 2
            string.fromHex("EA02"),
            ble.WRITE,
        },
        { -- Characteristic 3
            string.fromHex("EA03"),
            ble.READ,
        },
        { -- Characteristic 4
            string.fromHex("EA04"),
            ble.READ|ble.WRITE,
        },
    }

local function ble_callback(ble_device, ble_event, ble_param)
    if ble_event == ble.EVENT_CONN then
        log.info("ble", "connect 成功")
    elseif ble_event == ble.EVENT_DISCONN then
        log.info("ble", "disconnect")
        -- 1秒后重新开始广播
        sys.timerStart(function() ble_device:adv_start() end, 1000)
    elseif ble_event == ble.EVENT_WRITE then
        log.info("ble", "write", ble_param.conn_idx,ble_param.service_id,ble_param.handle,ble_param.data:toHex())
    elseif ble_event == ble.EVENT_READ then
        log.info("ble", "read", ble_param.conn_idx,ble_param.service_id,ble_param.handle)
        ble_device:read_response(ble_param,string.fromHex("1234"))
    end
end


sys.taskInit(function()
    log.info("开始初始化蓝牙核心")
    bluetooth_device = bluetooth.init()
    log.info("初始化BLE功能")
    ble_device = bluetooth_device:ble(ble_callback)

    log.info('开始创建GATT')
    characteristic1,characteristic2,characteristic3,characteristic4 = ble_device:gatt_create(att_db)
    log.info("创建的GATT为",characteristic1,characteristic2,characteristic3,characteristic4)

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
        }
    })

    log.info("开始广播")
    ble_device:adv_start()
    -- ble_device:adv_stop()

    while 1 do
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
