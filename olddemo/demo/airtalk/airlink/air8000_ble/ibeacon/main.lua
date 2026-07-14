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

function ble_callback()
    -- 无事可做
end

sys.taskInit(function()
    local ret = 0
    sys.wait(500)
    log.info("开始初始化蓝牙核心")
    bluetooth_device = bluetooth.init()
    sys.wait(100)
    log.info("初始化BLE功能")
    ble_device = bluetooth_device:ble(ble_callback)
    sys.wait(100)

    sys.wait(100)
    log.info("开始设置广播内容")
    local adv_data = string.char(0x4C, 0x00,
                                0x02, 0x15, 0x01, 0x02, 0x03, 0x04, 0x05,
                                        0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
                                        0x00, 0x01,
                                        0x00, 0x02,
                                        0x00)
    ble_device:adv_create({
        addr_mode = ble.PUBLIC,
        channel_map = ble.CHNLS_ALL,
        intv_min = 120,
        intv_max = 120,
        adv_data = {
            {ble.FLAGS, string.char(0x06)},
            {ble.MANUFACTURER_SPECIFIC_DATA, adv_data}
        }
    })

    sys.wait(100)
    log.info("开始广播")
    ble_device:adv_start()
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
