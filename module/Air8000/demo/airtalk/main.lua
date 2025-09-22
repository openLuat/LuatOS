--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.09.19
@author  梁健
@usage
本demo演示的核心功能为：

airtalk.lua： 进行airtalk 对讲业务,相关使用说明，请见https://docs.openluat.com/value/airtalk/

更多说明参考本目录下的readme.md文件
]]

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]

--[[
本demo可直接在Air8000整机开发板上运行
]]

PROJECT = "audio"
VERSION = "1.0.0"
PRODUCT_KEY =  "NrkXcjWwjcc5EFdCrrYnvypBCyJlEaIO"
-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)
exnetif = require("exnetif")

-- 如果内核固件支持wdt看门狗功能，此处对看门狗进行初始化和定时喂狗处理
-- 如果脚本程序死循环卡死，就会无法及时喂狗，最终会自动重启
if wdt then
    --配置喂狗超时时间为9秒钟
    wdt.init(9000)
    --启动一个循环定时器，每隔3秒钟喂一次狗
    sys.timerLoopStart(wdt.feed, 3000)
end

-- exnetif.set_priority_order({ { -- 次优先级：WiFi
--     WIFI = {

--         ssid = "机房-降功耗,找合宙!",

--         password = "Air123456", 

--     }
-- }})

-- -- 设置网络状态回调

-- exnetif.notify_status(function(net_type, adapter)

--     log.info("网络切换至:", net_type)

-- end)

-- -- wifi的STA相关事件
-- sys.subscribe("WLAN_STA_INC", function(evt, data)
--     -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
--     -- 当evt=CONNECTED, data是连接的AP的ssid, 字符串类型
--     -- 当evt=DISCONNECTED, data断开的原因, 整数类型
--     log.info("收到STA事件", evt, data)
-- end)

require "talk"            --  启动airtalk

-- 音频对内存影响较大，不断的打印内存，用于判断是否异常
sys.timerLoopStart(function()
    log.info("mem.lua", rtos.meminfo())
    log.info("mem.sys", rtos.meminfo("sys"))
 end, 3000)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

