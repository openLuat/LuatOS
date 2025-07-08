PROJECT = "record_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)
log.style(1)
-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")
-- es8311 录音demo
require "es8311"
-- es8311 循环录音demo
-- require "es8311_loop"
-- es8218e 录音demo
-- require "es8218e"

-- es7243e 录音demo
-- require "es7243e"

sys.run()