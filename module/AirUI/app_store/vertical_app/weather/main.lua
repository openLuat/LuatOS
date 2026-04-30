PROJECT = "weather_report"
VERSION = "001.999.001"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "weather_report_win"

sys.publish("OPEN_WEATHER_WIN")

sys.run()