PROJECT = "CHARGING_PILE"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

require "charger_main_win"
require "charger_win"

sys.publish("OPEN_CHARGER_MAIN_WIN")

sys.run()