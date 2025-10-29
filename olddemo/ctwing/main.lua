PROJECT = 'CtwingDemo'
VERSION = '2.0.0'

LOG_LEVEL = log.LOG_INFO
log.setLevel(LOG_LEVEL )
local sys = require "sys"
_G.sysplus = require("sysplus")


require 'ctwingdemo'


sys.run()
