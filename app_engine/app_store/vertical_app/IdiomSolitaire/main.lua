PROJECT = "IDIOM_SOLITAIRE"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "idiom_solitaire_win"

sys.publish("OPEN_IDIOM_SOLITAIRE_WIN")
sys.run()