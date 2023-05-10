
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pwrkey_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")


gpio.setup(35, function() -- 35是虚拟GPIO，见https://wiki.luatos.com/chips/air780e/iomux.html#id1
    log.info("pwrkey", gpio.get(35))
end, gpio.PULLUP)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
