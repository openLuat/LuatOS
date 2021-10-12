
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pwmdemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

log.info("main", "hello world")

print(_VERSION)

-- Air640w的固件,在2020-11-27开始支持PWM,之前的版本不带PWM
-- W600规格书 http://www.winnermicro.com/upload/1/editor/1594026750682.pdf
--[[
    // PWM4 --> PB8      channel 5
    // PWM3 --> PB15     channel 4
    // PWM1 --> PA1      channel 2
    // PWM0 --> PA0      channel 1
]]
-- 注意PWM4的channel值是5, 对应PB8
pwm.open(5, 1000, 50)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
