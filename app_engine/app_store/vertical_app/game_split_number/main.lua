PROJECT = "SPLIT_NUMBER_GAME"
VERSION = "001.999.001"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "game_split_number_win"

sys.publish("OPEN_GAME_SPLIT_NUMBER_WIN")

sys.run()