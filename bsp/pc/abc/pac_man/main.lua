
PROJECT = "PACMAN_GAME"
VERSION = "001.999.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "pacman_game_win"

sys.publish("OPEN_PACMAN_GAME_WIN")

sys.run()
