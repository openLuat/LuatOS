PROJECT = "TETRIS"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "tetris_game"

sys.publish("OPEN_TETRIS_WIN")

sys.run()
