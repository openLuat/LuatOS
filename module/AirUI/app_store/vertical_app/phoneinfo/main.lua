PROJECT = "LuatOS_PhoneInfo"
VERSION = "001.001.001"

log.info("main", PROJECT, VERSION)

require "phoneinfo_win"

sys.publish("OPEN_PHONEINFO_WIN")
sys.run()