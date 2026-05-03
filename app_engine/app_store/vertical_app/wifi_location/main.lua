PROJECT = "WIFI_LOCATION"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

require "celllocate_win"
-- require "cell_config_win"

sys.publish("OPEN_CELLLOCATE_WIN")

sys.run()