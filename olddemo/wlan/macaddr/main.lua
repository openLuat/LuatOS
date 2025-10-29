-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "wifidemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
require("sysplus")

--[[
@demo 设置wifi设备的mac地址
@content
备注:

1. 对应ESP32系列, 自定义mac地址存储在nvs分区
2. 对Air601/Air103/Air101, 设置后需要重启才能生效

本demo于 2023.10.12 添加, 需要该日期或之后的编译的固件才能正常工作
]]

sys.taskInit(function()
    sys.wait(1000)
    if not wlan or not wlan.connect then
        log.info("wlan", "这个demo不适合当前模块或当前模块未编译wlan库")
    end
    wlan.init()
    sys.wait(100)
    local macaddr = wlan.getMac()
    log.info("macaddr", macaddr)

    local ret = wlan.setMac(0, (string.fromHex("C81234567890")))
    log.info("wlan", "设置mac结果", ret)
    log.info("wlan", "设置后的mac地址", wlan.getMac())

    if wlan.getMac() == macaddr then
        log.info("wlan", "设置不成功, 还是原本的mac")
    else
        log.info("wlan", "设置成功", "还原到原本的mac")
        wlan.setMac(0, (string.fromHex(macaddr)))
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
