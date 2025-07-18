
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "LOG"
VERSION = "2.0.0"

--[[
本demo演示 string字符串的基本操作
1. lua的字符串是带长度, 这意味着, 它不依赖0x00作为结束字符串, 可以包含任意数据
2. lua的字符串是不可变的, 就不能直接修改字符串的一个字符, 修改字符会返回一个新的字符串
]]

-- sys库是标配
_G.sys = require("sys")

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

local netLed = require("netLed")
--GPIO18配置为输出，默认输出低电平，可通过setGpio18Fnc(0或者1)设置输出电平
local LEDA= gpio.setup(27, 0, gpio.PULLUP)

sys.taskInit(function ()
    sys.wait(1000) -- 免得看不到日志
    local tmp

	--实验1：输出四个等级的日志，日志等级排序从低到高为 debug < info < warn < error
	log.debug(PROJECT, "debug message")
	log.info(PROJECT, "info message")
	log.warn(PROJECT, "warn message")
	log.error(PROJECT, "error message")
	
	
	--实验2：输出INFO及更高级别日志，即debug日志不输出
	log.setLevel("INFO")
	print(log.getLevel())

	-- 这条debug级别的日志不会输出
	log.debug(PROJECT, "debug message")
	log.info(PROJECT, "info message")
	log.warn(PROJECT, "warn message")
	log.error(PROJECT, "error message")
	
	--实验3：通过日志输出变量内容
	local myInteger = 42
    log.info("Integer", myInteger)
end)
-- 这里演示4G模块上网后，会自动点亮网络灯，方便用户判断模块是否正常开机
sys.taskInit(function()
    while true do
        sys.wait(6000)
                if mobile.status() == 1 then
                        gpio.set(27, 1)  
                else
                        gpio.set(27, 0) 
                        mobile.reset()
        end
    end
end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
