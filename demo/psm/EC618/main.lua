
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "psmdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
-- 对于双卡的设备, 可以设置为自动选sim卡
-- 但是, 这样SIM1所在管脚就强制复用为SIM功能, 不可以再复用为GPIO
-- mobile.simid(2)
sys.taskInit(function()
    mobile.rtime(2) -- 在无数据交互时，RRC2秒后自动释放
    mobile.config(mobile.CONF_T3324MAXVALUE,0)
    mobile.config(mobile.CONF_PSM_MODE,1)
    pm.force(pm.HIB)
    pm.power(pm.USB,false)
    gpio.setup(23,nil)
end)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
