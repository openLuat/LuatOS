PROJECT = "VENDING_MACHINE"
VERSION = "001.999.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "vending_machine_win"

sys.publish("OPEN_VENDING_MACHINE_WIN")

sys.run()