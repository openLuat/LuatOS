
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "bledemo"
VERSION = "1.0.0"

--[[
BLE iBeacon示例
支持的模块:
1. Air101/Air103, 开发板的BLE天线未引出, 需要靠近使用, 且功耗高
2. ESP32系列, 包括ESP32C3/ESP32S3

-- 使用蓝牙小程序, BeaconController, 可搜索到,且能看到数据变化
]]

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()
    sys.wait(2000)

    -- 设置ibeacon的数据, 16字节
    -- local data = string.char(0x11, 0x22, 0x11, 0x22, 0x11, 0x22, 0x11, 0x22, 0x11, 0x22, 0x11, 0x22, 0x11, 0x22, 0x11, 0x22)
    local data = string.fromHex("11223344112233441122334411223344")
    -- nimble.ibeacon(data, 2, 10, 0)
    nimble.ibeacon(data)
    
    -- BLE模式, 默认是SERVER/Peripheral,即外设模式, 等待被连接的设
    nimble.mode(nimble.MODE_BLE_BEACON)
    -- 启动之
    nimble.init()

    -- 运行时改变数据也是可以的
    while 1 do
        sys.wait(60000) -- 每隔1分钟变一次
        data = crypto.trng(16)
        log.info("ibeacon", "data", data:toHex())
        nimble.ibeacon(data)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
