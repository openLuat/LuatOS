-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "helloworld"
VERSION = "1.0.0"

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "xxx" -- 到 iot.openluat.com 创建项目,获取正确的项目id

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")
libnet = require "libnet"

log.info("main", "hello world")

print(_VERSION)

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(20000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

local airlbs = require "airlbs"

-- 此为收费服务，需自行联系销售申请
local airlbs_project_id = "xxx"
local airlbs_project_key = "xxx"

sys.taskInit(function()
    sys.waitUntil("IP_READY")

    socket.sntp()
    sys.waitUntil("NTP_UPDATE", 1000)

    while 1 do
        local result , data = airlbs.request({project_id = airlbs_project_id,project_key = airlbs_project_key})
        if result then
            print("airlbs", json.encode(data))
        end
        sys.wait(20000)
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!


















































