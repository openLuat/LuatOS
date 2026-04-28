PROJECT = "PICTURE_CHARACTER_LEARNING"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "picture_character_learning_win"

sys.publish("OPEN_PICTURE_CHARACTER_LEARNING_WIN")

sys.run()