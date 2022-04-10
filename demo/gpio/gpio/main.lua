
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gpiodemo"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
end

--下面的GPIO引脚编号，请根据实际需要进行更改！
-- Air101开发板的3个LED分别为 PB08/PB09/PB10
-- Air103开发板的3个LED分别为 PB24/PB25/PB26
-- Air105开发板的3个LED分别为 PD14/PD15/PC3

-- 若下载到设备后提示pin库不存在,请升级固件到V0006或以上


--【HaoSir2022】于2022年4月10日修改
function pinx()--根据开发板给LED的gpio引脚不同编号

if rtos.bsp()=="air101" then--Air103开发板LED
local A= pin.PB08
local B= pin.PB09
local C= pin.PB10
return A,B,C

elseif rtos.bsp() == "air103" then--Air103开发板LED
local A= pin.PB26
local B= pin.PB25
local C= pin.PB24
return A,B,C

elseif rtos.bsp() == "air105" then--Air105开发板LED
local A= pin.PD14
local B= pin.PD15
local C= pin.PC3
return A,B,C
end
end
local P1,P2,P3=pinx()--赋值开发板LED脚
local LEDA= gpio.setup(P1, 0, gpio.PULLUP)
local LEDB= gpio.setup(P2, 0, gpio.PULLUP)
local LEDC= gpio.setup(P3, 0, gpio.PULLUP)


sys.taskInit(function()
--开始流水灯
    local count = 0
    while 1 do
    --流水灯程序
        sys.wait(1000) --点亮时间
        -- 轮流点灯
        LEDA(count % 3 == 0 and 1 or 0)
        LEDB(count % 3 == 1 and 1 or 0)
        LEDC(count % 3 == 2 and 1 or 0)
        log.info("GPIO", "Go Go Go", count, rtos.bsp())
        log.info("LuatOS:", "https://wiki.luatos.com")
        count = count + 1
    end
end)

-- API文档 https://wiki.luatos.com/api/gpio.html

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
