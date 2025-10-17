-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "wifidemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
require("sysplus")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- OTA任务
function ota_task()
    sys.taskInit(function()
        local dst_path = "/update.bin"
        os.remove(dst_path)
        local url = "http://site0.cn/api/esp32/ota?mac=" .. wlan.getMac()
        local code = http.request("GET", url, nil, nil, {dst=dst_path}).wait()
        if code and code == 200 then
            log.info("ota", "OTA 下载完成, 3秒后重启")
            sys.wait(3000)
            rtos.reboot()
        end
        log.info("ota", "服务器返回非200,就是不需要升级", code)
        os.remove(dst_path)
    end)
end

sys.taskInit(function()
    sys.wait(100)
    wlan.init()
    sys.wait(100)
    wlan.connect("luatos1234", "123456890")
    log.info("wlan", "wait for IP_READY", wlan.getMac())
    sys.waitUntil("IP_READY", 30000)

    -- 联网后,先执行一次OTA
    ota_task()
    -- 然后每隔6小时执行一次OTA
    sys.timerLoopStart(ota_task, 6*3600*1000)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
