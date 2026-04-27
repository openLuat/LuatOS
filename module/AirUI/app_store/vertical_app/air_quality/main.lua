
PROJECT = "LuatOS_StopWatch"
VERSION = "001.001.001"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "airquality_win"

sys.publish("OPEN_AIR_QUALITY_WIN")
sys.run()
