-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "StudentCard"
VERSION = "1.2.0"
PRODUCT_KEY = "epeGacglnQylV5jSKybIj1Dvqk6vm6nu"
-- 产品信息:放学接我
PRODUCT_VER = "0003"

IPV6_UDP_VER = false

log.info("main", PROJECT, VERSION, PRODUCT_VER)
-- pm.ioVol(pm.IOVOL_ALL_GPIO, 1800)
-- 引入必要的库文件(lua编写), 内部库不需要require
_G.sys = require "sys"
_G.sysplus = require "sysplus"

gpio.setup(22, 1, gpio.PULLUP)


_G.pcb = require "pcb"

-- 开机防抖
pm.power(pm.PWK_MODE, true)

-- pa，默认是高的，先关掉，去除没用的耗电
-- gpio.setup(pcb.paPin(), 0)

-- 开机先主动关一下gnss电源，确保初始化的时候是低电平
pcb.gnssPower(false)

-- es8311，有用，但先关一下，确保初始化的时候是低电平
gpio.setup(24, 1, gpio.PULLUP)          -- i2c工作的电压域
gpio.setup(pcb.es8311PowerPin(), 1)


--手动关闭部分外设电源
pcb.gnssPower(0)--gpio25,26
local result = pm.power(pm.GPS,false)--关闭gps电源--GPIO24,25
log.info("main", "gps power off",result)

local result = gpio.setup(pcb.es8311PowerPin(), 0)--关闭es8311电源
log.info("main", "es8311 power off",result)

local result = gpio.setup(pcb.chargeCmdPin(), 0)   --关闭充电ic的CMD脚--gpio152
log.info("main", "chargeCmd power off",result)

sys.taskInit(function()
    
    sys.wait(2000)
    mobile.flymode(0,true)
    log.info("main", "fly mode")
    sys.wait(2000) 

    -- local result = gpio.setup(24, 0)
    -- log.info("main", "wakeup2 power off",result)
    
    airlink.pause(1)
    sys.wait(2000)
    log.info("main", "airlink pause")
    -- sys.wait(3000)
    local result = airlink.power(false)
    log.info("关闭wifi",result)
    -- gpio.setup(23, 0)

    log.info("main", "PSM+")
    log.info("pm check", pm.check())

    pm.power(pm.WORK_MODE, 3)--PSM+模式
    log.info("check pm state  ", pm.check())
    sys.wait(3000)

end)


-- 默认进LIGHT模式
-- pm.request(pm.LIGHT)

require "bootup"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
