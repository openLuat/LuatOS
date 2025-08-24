
--=============================================================
PROJECT = "12V_4G_RTU"--名字之间不能有空格，否则影响远程更新的名字识别
VERSION = "1.0.6" --版本号2023.8.2,必须是3个数，否则升级会失败,系统忽略中间的0
--=============================================================
-- sys库是标配--需要用到的其他库，下载时需要添加进来
_G.sys = require("sys")--前面加-G表示全局引入？
_G.sysplus = require("sysplus")--加强版的sys库，用于操作网络
--_G.libnet = require "libnet"--网络相关的库
--_G.libfota = require"libfota"--远程升级
--=============================================================
--=============================================================
--引入自己定义的文件
--_G.require("Radar")--串口2雷达采集
_G.require("Radar_485")--串口3采集485雷达
log.info("main", PROJECT,VERSION)--2023.11.8
--=============================================================
--=============================================================
--设置看门狗
if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
--=============================================================
--=============================================================
--查看内存情况，正式版需注释掉
sys.taskInit(function ()
    while true do
        sys.wait(3000)
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end)
--=============================================================
-- 如果运营商自带的DNS不好用，可以用下面的公用DNS
-- socket.setDNS(nil,1,"223.5.5.5")
-- socket.setDNS(nil,2,"114.114.114.114")

--socket.sntp()--读取时间
--socket.sntp("ntp.aliyun.com") --自定义sntp服务器地址
--socket.sntp({"ntp.aliyun.com","ntp1.aliyun.com","ntp2.aliyun.com"}) --sntp自定义服务器地址
--sys.subscribe("NTP_UPDATE", function()--订阅NTP_UPDATE这个消息，成功则打印系统时间
--log.info("sntp", "time", os.date())
--end)
--sys.subscribe("NTP_ERROR", function()--订阅NTP_ERROR这个消息，失败则打印错误
--log.info("socket", "sntp error")
--socket.sntp()--再次获取时间
--end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()

