PROJECT = "VENDING_MACHINE"
VERSION = "001.001.000"

log.info("main", PROJECT, VERSION)

require "vending_machine_win"

sys.publish("OPEN_VENDING_MACHINE_WIN")

sys.run()
