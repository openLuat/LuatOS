PROJECT = "record_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)
log.style(1)
-- sys库是标配
_G.sys = require("sys")
require "es8311"
-- require "es8218e"
sys.run()