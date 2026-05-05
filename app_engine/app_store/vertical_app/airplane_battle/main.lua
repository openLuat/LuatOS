PROJECT = "AIRPLANE_BATTLE"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

require "airplane_win"

sys.publish("OPEN_AIRPLANE_BATTLE_WIN")

sys.run()

