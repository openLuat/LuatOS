PROJECT = "PARCEL_LOCKER"
VERSION = "001.999.000"

log.info("main", PROJECT, VERSION)

require "ecabinet"
require "ecboxstatus"
require "ecsend_pay"
require "ecsettings_detail"

sys.publish("OPEN_EXPRESS_CABINET_WIN")

sys.run()
