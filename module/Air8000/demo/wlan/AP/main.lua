
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_wifi"
VERSION = "1.0.5"

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local fota_wifi = require("fota_wifi")

local function wifi_fota_task_func()
    local result = fota_wifi.request()
    if result then
        log.info("fota_wifi", "升级任务执行成功")
    else
        log.info("fota_wifi", "升级任务执行失败")
    end
end

-- 判断网络是否正常
local function wait_ip_ready()
    local result, ip, adapter = sys.waitUntil("IP_READY", 30000)
    if result then
        log.info("fota_wifi", "开始执行升级任务")
        sys.taskInit(wifi_fota_task_func)
    else
        log.error("当前正在升级WIFI&蓝牙固件，请插入可以上网的SIM卡")
    end
end

function test_ap()
    log.info("执行AP创建操作")
    wlan.createAP("uiot5678", "12345678")
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    while netdrv.ready(socket.LWIP_AP) ~= true do
        sys.wait(100)
    end
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    dhcpsrv.create({adapter=socket.LWIP_AP})
    while 1 do
        if netdrv.ready(socket.LWIP_GP) then
            netdrv.napt(socket.LWIP_GP)
            log.info("AP 创建成功，如果无法连接，需要将按照https://docs.openluat.com/air8000/luatos/app/updatwifi/update/ 升级固件")
            log.info("AP 创建成功，如果无法连接，请升级本仓库的最新core")
            break
        end
        sys.wait(1000)
    end
end

-- wifi的AP相关事件
sys.subscribe("WLAN_AP_INC", function(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的新STA的MAC地址
    -- 当evt=DISCONNECTED, data是断开与AP连接的STA的MAC地址
    log.info("收到AP事件", evt, data and data:toHex())
end)



-- 在设备启动时检查网络状态
sys.taskInit(wait_ip_ready)

sys.taskInit(function()
    log.info("开始AP 测试...")
    wlan.init()
    test_ap()
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
