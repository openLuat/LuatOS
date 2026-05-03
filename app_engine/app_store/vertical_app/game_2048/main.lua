PROJECT = "2048_GAME"
VERSION = "001.999.001"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "game_2048_win"

sys.publish("OPEN_GAME_2048_WIN")

sys.run()