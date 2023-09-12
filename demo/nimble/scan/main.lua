
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "bledemo"
VERSION = "1.0.0"

--[[
BLE 扫描
状态: 
1. 扫描, 可用
2. 接收扫描结果, 可用

支持的模块:
1. Air601
2. ESP32系列, 包括ESP32C3/ESP32S3
3. Air101/Air103 开发板天线未引出, 天线未校准, 能用但功耗高
]]

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- 接收扫描结果
sys.subscribe("BLE_SCAN_RESULT", function(addr, name, uuids, mfg_data)
    -- addr 蓝牙设备的地址, 7字节
    --      首字节是地址类型, 0 代表 随机地址, 1 代表真实地址
    --      后6字节是蓝牙地址
    -- name 设备名称, 不一定有
    -- uuids 服务id
    -- mfg_data 工厂默认信息, 主要是iBeacon或者自由广播的数据, 2023-03-19添加
    log.info("blescan", (addr:toHex()), name, json.encode(uuids), mfg_data and mfg_data:toHex() or "")
end)

sys.taskInit(function()
    sys.wait(2000)

    -- BLE模式, 默认是SERVER/Peripheral,即外设模式, 等待被连接的设
    nimble.mode(nimble.CLIENT) -- 默认就是它, 不用调用

    -- 可以自定义名称
    -- nimble.init("LuatOS-Wendal") -- 蓝牙名称可修改,也有默认值LOS-$mac地址
    nimble.init() -- 蓝牙名称可修改,也有默认值LOS-$mac地址

    sys.wait(500)
    -- 打印MAC地址
    local mac = nimble.mac()
    log.info("ble", "mac", mac and mac:toHex() or "Unknwn")
    sys.wait(1000)

    -- 发送数据
    while 1 do
        log.info("ble", "start SCAN ...")
        nimble.scan()
        -- TODO 扫描到指定设备后, 应跳出循环
        sys.wait(30000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
