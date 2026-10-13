-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "FOTATEST"
-- iot限制，只能上传xxx.yyy.zzz格式的三位数的版本号，但实际上现在只用了XXX和ZZZ,中间yyy暂未使用
-- 需要注意的是,因为yyy不生效，所以111.222.333版本和111.444.333版本，对iot平台来说都一样，所以建议中间那一位永远写000
VERSION = "001.000.1"

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
excloud = require("excloud")
libnet = require "libnet"
config = require"config"
require"excloud_test"
RecordingManager = require"sd_test"
gpio_utils=require"gpio_util"
lbs_util = require"fota"
gps = require"normal"
http_app = require"http_app"
require"es7243e"
require"app"
led_util = require"led_util"
require"da221"

-- mcu.hardfault(0) 
local tol, use, max_use = rtos.meminfo("sys")
local last_max_use = max_use
local function mem_test()
    while true do
        sys.wait(100)
        tol, use, max_use = rtos.meminfo("sys")
        if max_use > last_max_use then
            log.info("memory usage is increasing", max_use ,"last_max_use", last_max_use)
            last_max_use = max_use
        end
    end
end

sys.taskInit(mem_test)

-- TODO 记录最后一次定位成功的坐标，定位失败时上传最后一个定位成功的位置
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
