
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "osdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()
    sys.wait(1000)

    -- 获取本地时间字符串
    log.info("本地时间字符串", os.date())
    -- 获取UTC时间字符串
    log.info("UTC时间字符串", os.date("!%c"))

    -- 格式化本地时间字符串
    log.info("本地时间字符串", os.date("%Y-%m-%d %H:%M:%S"))
    -- 格式化UTC时间字符串
    log.info("UTC时间字符串", os.date("!%Y-%m-%d %H:%M:%S"))

    -- 格式化时间字符串
    log.info("自定义时间的字符串", os.date("!%Y-%m-%d %H:%M:%S", os.time({year=2000, mon=1, day=1, hour=0, min=0, sec=0})))
    
    -- 获取本地时间的table
    log.info("本地时间字符串", json.encode(os.date("*t")))
    -- 获取UTC时间的table
    log.info("UTC时间字符串",  json.encode(os.date("!*t")))


    -- 时间戳, 但lua下的精度只能到秒
    log.info("UTC时间戳", os.time())
    log.info("自定义时间戳", os.time({year=2000, mon=1, day=1, hour=0, min=0, sec=0}))
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
