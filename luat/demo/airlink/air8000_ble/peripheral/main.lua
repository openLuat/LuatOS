-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ble"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

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
        string.fromHex("EA04"), ble.READ | ble.WRITE
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
    elseif evt == ble.EVENT_WRITE_REQ then
        -- 收到写请求
        log.info("ble", "接收到写请求", param.uuid_service:toHex() param.data:toHex())
    end
end

local bt_scan = false -- 是否扫描蓝牙

sys.taskInit(function()
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

    -- while 1 do
    --     sys.wait(3000)
    --     if ble_stat then
    --         local wt = {
    --             service_id = 0,
    --             handle = characteristic4
    --         }
    --         local result = ble_device:write_notify(wt, "123456")
    --         log.info("ble", "发送数据", result)
    --     else
    --         -- log.info("等待连接成功之后发送数据")
    --     end
    -- end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
