PROJECT = "SMART_MIST_SYSTEM"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

-- 直接启动主页窗口
require "water_home_win"

sys.publish("OPEN_WATER_HOME_WIN")

sys.run()