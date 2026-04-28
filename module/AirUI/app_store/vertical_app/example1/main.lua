
PROJECT = "EXAMPLE1"
VERSION = "001.999.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

require "iot_account_win"

sys.publish("OPEN_IOT_ACCOUNT_WIN")

sys.run()
