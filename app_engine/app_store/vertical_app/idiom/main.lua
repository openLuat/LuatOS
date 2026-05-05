PROJECT = "idiom"
VERSION = "1.0.0"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "idiom_game_win"

log.info("main", "应用初始化完成")
sys.publish("OPEN_IDIOM_APP")

sys.run()