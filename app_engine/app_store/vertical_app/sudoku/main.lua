PROJECT = "SUDOKU_GAME"
VERSION = "001.999.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "sudoku_win"

sys.publish("OPEN_SUDOKU_WIN")

sys.run()