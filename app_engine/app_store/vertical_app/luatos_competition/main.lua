
PROJECT = "LuatOS_KnowledgeCompetition"
VERSION = "001.001.001"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- require "iot_account_win"
require "competition_win"

-- sys.publish("OPEN_IOT_ACCOUNT_WIN")
sys.publish("OPEN_COMPETITION_WIN")

sys.run()
