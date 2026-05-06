PROJECT = "TEXAS_HOLDEM"
VERSION = "001.000.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "texas_holdem_win"
sys.publish("OPEN_TEXAS_HOLDEM_WIN")
if texas_holdem_open then
    texas_holdem_open()
end

sys.run()
