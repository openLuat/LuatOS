
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "nimbledemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- 监听BLE主适配的状态变化
sys.subscribe("BLE_STATE_INC", function(state)
    log.info("ble", "ble state changed", state)
    if state == 1 then
        nimble.server_init()
    else
        nimble.server_deinit()
    end
end)

-- 监听GATT服务器的WRITE_CHR
sys.subscribe("BLE_GATT_WRITE_CHR", function(info, data)
    -- info 是个table, 但当前没有数据
    log.info("ble", "data got!!", data:toHex())
end)

-- TODO 支持传数据(read)和推送数据(notify)

-- 配合微信小程序 "LuatOS蓝牙调试"
-- 1. 若开发板无天线, 将手机尽量靠近芯片也能搜到
-- 2. 该小程序是开源的, 每次write会自动分包
-- https://gitee.com/openLuat/luatos-miniapps

sys.taskInit(function()
    sys.wait(2000)

    -- BLE模式, 默认是SERVER/Peripheral,即外设模式, 等待被连接的设
    -- nimble.mode(nimble.MODE_BLE_SERVER)

    -- 设置SERVER/Peripheral模式下的UUID, 支持设置3个
    -- 地址支持 2/4/16字节, 需要二进制数据, 例如 string.fromHex("AABB") 返回的是2个字节数据,0xAABB
    if nimble.setUUID then -- 2023-02-25之后编译的固件支持本API
        nimble.setUUID("srv", string.fromHex("380D"))      -- 服务主UUID         ,  默认值 180D
        nimble.setUUID("write", string.fromHex("FF31"))    -- 往本设备写数据的UUID,  默认值 FFF1
        nimble.setUUID("indicate", string.fromHex("FF32")) -- 订阅本设备的数据的UUID,默认值 FFF2
    end

    -- nimble.debug(6)
    -- nimble.init("LuatOS-Wendal") -- 蓝牙名称可修改,也有默认值LOS-$mac地址
    nimble.init() -- 蓝牙名称可修改,也有默认值LOS-$mac地址

    if nimble.send_msg then
        while 1 do
            sys.wait(3000)
            nimble.send_msg(1, 0, string.char(0x5A, 0xA5, 0x12, 0x34, 0x56))
        end
    else
        log.info("nimble", "no send_msg")
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
