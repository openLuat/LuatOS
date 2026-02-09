-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "uart_irq"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")


mobile.flymode(0,true)

log.info("main", "cc0258_gnss")

mcu.hardfault(0)    --死机后停机，一般用于调试状态

require"LIBGNSS_8000"



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
