PROJECT = "LuatOS_Weight"
VERSION = "001.001.001"


log.info("main", PROJECT, VERSION)

require "weight_win"

sys.publish("OPEN_WEIGHT_WIN")

sys.run()
