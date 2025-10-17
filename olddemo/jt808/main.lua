-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "my_test"
VERSION = "1.2"
PRODUCT_KEY = " " --自己iot平台下的PRODUCT_KEY
-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

--[[本demo实现了jt808协议的基本框架，可以通过tcp上报位置信息和心跳包，后续功能可按照此框架添加即可；
    使用前需修改下tcp的ip地址和端口；
    如果是780eg模块，可以直接烧录，如果是780e外挂定位模块，需要注意串口号!]]--
----------------------------------------
-- 报错信息自动上报到平台,默认是iot.openluat.com
-- 支持自定义, 详细配置请查阅API手册
-- 开启后会上报开机原因, 这需要消耗流量,请留意
if errDump then
    errDump.config(true, 600)
end
----------------------------------------


-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end


-- 如果运营商自带的DNS不好用，可以用下面的公用DNS
-- socket.setDNS(nil,1,"223.5.5.5")
-- socket.setDNS(nil,2,"114.114.114.114")

-- socket.sntp()
--socket.sntp("ntp.aliyun.com") --自定义sntp服务器地址
--socket.sntp({"ntp.aliyun.com","ntp1.aliyun.com","ntp2.aliyun.com"}) --sntp自定义服务器地址
-- sys.subscribe("NTP_UPDATE", function()
--     log.info("sntp", "time", os.date())
-- end)
-- sys.subscribe("NTP_ERROR", function()
--     log.info("socket", "sntp error")
--     socket.sntp()
-- end)

-----------------------------------------------------------------------------------------------------------------
sys.taskInit(function()
    -- 检查一下当前固件是否支持fskv
    if not fskv then
        while true do
            log.info("fskv", "this demo need fskv")
            sys.wait(1000)
        end
    end

    -- 初始化kv数据库
    fskv.init()
    fskv.set("authCode", " ")  --注册成功后的鉴权码
    fskv.set("heartFreq",60)  --心跳上报间隔，单位秒
    fskv.set("tcpSndTimeout",10)  --TCP等待应答超时时间，单位秒
    fskv.set("tcpResendMaxCnt", 3)  --TCP重传次数
    fskv.set("locRptStrategy", 0)   --位置汇报策略，0：定时汇报；1：定距汇报；2：定时和定距汇报
    fskv.set("locRptMode",0)      --位置汇报方案，0：根据 ACC 状态； 1：根据登录状态和 ACC 状态，先判断登录状态，若登录再根据 ACC 状态
    fskv.set("sleepLocRptFreq", 60)   --休眠时位置汇报时间间隔，单位为秒
    fskv.set("alarmLocRptFreq",5)  --紧急报警时位置汇报时间间隔，单位为秒
    fskv.set("wakeLocRptFreq", 20)   --缺省位置汇报时间间隔，单位为秒
    fskv.set("sleepLocRptDistance", 500)    --休眠时汇报距离间隔，单位为米
    fskv.set("alarmLocRptDistance", 5)     --紧急报警时位置汇报时间间隔，单位为米
    fskv.set("wakeLocRptDistance", 50)    --缺省位置汇报时间间隔，单位为米
    fskv.set("fenceRadis", 100)     --电子围栏半径，单位为米
    fskv.set("alarmFilter",0)    --报警屏蔽字，与位置汇报消息中的报警标志相对应，相应位为 1，则相应报警被屏蔽
    fskv.set("keyFlag", 0)   --关键标志，与位置信息汇报消息中的报警标志相对应，相应位为 1 则对相应报警为关键报警
    fskv.set("speedLimit", 100)  --最高速度，单位为公里每小时（km/h）
    fskv.set("speedExceedTime", 60)   --超速持续时间，单位为秒（s）
end)

-------------------------------------------------------------------------------------------------------------

local gpsMng = require "gpsMng"
require "JT808Prot"
require "socket_demo"
-- dtuDemo("112.125.89.8",35960)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
