PROJECT = "air_ui_test"
VERSION = "1.0.0"
PRODUCT_VER = "0001"
log.info("main", PROJECT, VERSION)

-- sys库是标配
sys = require("sys")
sysplus = require("sysplus")

mcu.hardfault(0) -- 死机后停机，一般用于调试状态
-- pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)    -- 所有GPIO高电平输出3.3V
air_ui = require("air_ui")
api = require("api")
-- air_touch = require("air_touch")
air_jt808 = require("air_gt808")
-- air_test = require("air_test")
air_http = require("air_http")
air_gnss = require("air_gnss")
netWork = require("netWork")
air_lan = require("air_lan")
require("air_log_serer")

-- air_fota = require("air_fota")
sys.taskInit(function()
    sys.waitUntil("IP_READY")
    log.info("已联网")
    sys.publish("net_ready")
end)

local function main_test()
    fskv.init()
    air_ui.lcd_init()
    sys.waitUntil("net_ready")
    -- air_http.run_tests()
    air_lan.run_tests()
    -- air_gnss.gnss_start()
end

sys.taskInit(main_test)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
