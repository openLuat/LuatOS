PROJECT = "COLDCHAIN"
VERSION = "001.000.000"

log.info("main", PROJECT, VERSION)

require "cc_main"
require "cc_settings"
require "cc_record"

sys.publish("OPEN_CC_MAIN_WIN")

sys.run()
