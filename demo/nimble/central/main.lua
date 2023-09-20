
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "bledemo"
VERSION = "1.0.0"

--[[
BLE 中心/从机模式 -- 还没完成,还在测试
状态: 
1. 扫描, 可用
2. 接收扫描结果, 可用
3. 连接到指定设备, 可用
4. 获取已连接设备的描述符
5. 订阅特征值
6. 发送数据

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

-- 监听GATT服务器的WRITE_CHR, 也就是收取数据的回调
sys.subscribe("BLE_GATT_WRITE_CHR", function(info, data)
    -- info 是个table, 但当前没有数据
    log.info("ble", "data got!!", data:toHex())
end)

-- 接收扫描结果
sys.subscribe("BLE_SCAN_RESULT", function(addr, name, uuids, mfg_data)
    -- addr 蓝牙设备的地址, 7字节
    --      首字节是地址类型, 0 代表 随机地址, 1 代表真实地址
    --      后6字节是蓝牙地址
    -- name 设备名称, 不一定有
    -- uuids 服务id
    -- mfg_data 工厂默认信息, 主要是iBeacon或者自由广播的数据, 2023-03-19添加
    -- log.info("ble scan", (addr:toHex()), name, json.encode(uuids), mfg_data and mfg_data:toHex() or "")
    if name == "KT6368A-BLE-1.9" then
        log.info("ble", "发现目标设备,发起连接")
        nimble.connect(addr)
    end
end)

sys.subscribe("BLE_CONN_RESULT", function(succ, ret, serv_count)
    log.info("ble", "连接结果", succ, "底层结果", ret, "服务特征数量", serv_count)
    if succ then
        log.info("ble", "设备的服务UUID列表", json.encode(nimble.listSvr()))
        nimble.discChr(string.fromHex("FF00"))
    end
end)

sys.subscribe("BLE_CHR_DISC_RESULT", function(succ, ret, chr_count)
    log.info("ble", "特征值扫描结果", succ, "底层结果", ret, "特征数量", chr_count)
    if succ then
        log.info("ble", "特征值列表", json.encode(nimble.listChr(string.fromHex("FF00"))))
        nimble.subChr(string.fromHex("FF00"), string.fromHex("FF01"))
    end
end)

sys.subscribe("BLE_GATT_READ_CHR", function(data)
    log.info("ble", "read result", data)
end)

sys.subscribe("BLE_GATT_TX_DATA", function(data)
    log.info("ble", "tx data", data)
end)

sys.taskInit(function()
    sys.wait(2000)

    nimble.config(nimble.CFG_ADDR_ORDER, 1)
    -- BLE模式, 默认是SERVER/Peripheral,即外设模式, 等待被连接的设
    nimble.mode(nimble.CLIENT) -- 默认就是它, 不用调用

    -- 可以自定义名称
    -- nimble.init("LuatOS-Wendal") -- 蓝牙名称可修改,也有默认值LOS-$mac地址
    nimble.init() -- 蓝牙名称可修改,也有默认值LOS-$mac地址

    sys.wait(500)
    -- 打印MAC地址
    local mac = nimble.mac()
    log.info("ble", "mac", mac:toHex())
    sys.wait(1000)

    -- 发送数据
    while 1 do 
        sys.wait(500)
        while not nimble.connok() do
            nimble.scan()
            sys.waitUntil("BLE_CONN_RESULT", 60000)
        end
        log.info("ble", "结束扫描, 进入数据传输测试")
        sys.wait(500)
        while nimble.connok() do
            -- log.info("已连接", "尝试写入数据")
            nimble.writeChr(string.fromHex("FF00"), string.fromHex("FF01"), "from LuatOS")
            sys.wait(1000)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
