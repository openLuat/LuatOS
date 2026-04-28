PROJECT = "GREEDY_SNAKE"
VERSION = "1.0.0"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "greedy_snake_win"

sys.publish("OPEN_GREEDY_SNAKE_WIN")

sys.run()