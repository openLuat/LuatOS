-- 本示例对比了普通GPIO和AGPIO的进入休眠模式前后的区别。
-- Luatools需要PROJECT和VERSION这两个信息
PROJECT = "leddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")


local gpio_number = 27 -- AGPIO GPIO号为27,也是核心板上的网络指示灯(蓝灯)


gpio.setup(gpio_number, 1)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
