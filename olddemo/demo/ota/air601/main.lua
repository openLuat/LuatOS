-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "otademo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
require("sysplus")

--[[
提示:
1. 本demo是演示ota的, 只升级脚本, 如果还需要底层一起升级, 参考demo/fota
2. demo/fota 需要大量flash空间作为fota分区, 所以能启用的库会很少,请酌情使用
3. ota文件是放在文件系统的,所以不能超过40k, 且不能少于1k
4. 服务器上的ota文件路径无所谓, 本地下载路径必须是 /update.bin
]]

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.timerLoopStart(function()
    log.info("当前版本号", _G.VERSION)
end, 1000)

-- OTA任务
function ota_task()
    sys.taskInit(function()
        local dst_path = "/update.bin"
        os.remove(dst_path) -- 一定要先移除老的文件
        -- 这里是演示用的url, 实际项目中请换成自己的
        -- 路径规则是自定义的, 不是一定要这种规格
        -- 这里把当前版本当路径, 是为了方便演示, 避免反复升级
        local url = "http://upload.air32.cn/ota/air601/" .. _G.PROJECT .. "/" .. _G.VERSION .. ".ota?mac=" .. wlan.getMac()
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
    wlan.connect("luatos1234", "12341234")
    log.info("wlan", "wait for IP_READY", wlan.getMac())
    sys.waitUntil("IP_READY", 30000)

    sys.wait(500)
    -- 联网后,先执行一次OTA
    ota_task()
    -- 然后每隔6小时执行一次OTA
    sys.timerLoopStart(ota_task, 6*3600*1000)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
