PROJECT = "LuatOS_SCCG"
VERSION = "001.001.001"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "sccg_win"

sys.publish("OPEN_SCCG_WIN")
sys.run()