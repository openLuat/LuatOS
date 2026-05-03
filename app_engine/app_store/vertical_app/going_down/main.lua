PROJECT = "GOING_DOWN"
VERSION = "001.000.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "going_down_win"
sys.publish("OPEN_GOING_DOWN_WIN")
if going_down_open then
    going_down_open()
end

sys.run()
