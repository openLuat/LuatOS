PROJECT = "IDIOMS_CLASSIFY"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

require "idioms_classify_win"

sys.publish("OPEN_IDIOMS_CLASSIFY_WIN")

sys.run()
