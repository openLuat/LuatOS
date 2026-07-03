PROJECT = 'air201_gnss'
VERSION = '1.0.0'
LOG_LEVEL = log.LOG_INFO
-- log.setLevel(LOG_LEVEL )
-- require 'air153C_wtd'
local sys = require "sys"
_G.sysplus = require("sysplus")

local gnss = require("gnss")
local lbsLocTest = require("lbsLocTest")

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
