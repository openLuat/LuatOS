PROJECT = "GNSS"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

-- 引入必要的模块
require "gps_win"
require "satellite_win"


-- 打开GNSS定位窗口
sys.publish("OPEN_GPS_WIN")

sys.run()
