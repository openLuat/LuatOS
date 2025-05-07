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

-- 默认进LIGHT模式
-- pm.request(pm.LIGHT)

require "bootup"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
