
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "my_test"
VERSION = "1.2"
PRODUCT_KEY = "s1uUnY6KA06ifIjcutm5oNbG3MZf5aUv" --换成自己的
-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")
log.style(1)
--require "gpio_test"
-- require "i2c_test"
-- require "audio_test"
require "net_test"
-- require "evb_lcd"
-- require "timer_test"
-- require "rotary"
-- rotary_start()
--require "fs_test"
--fs_demo()
--require "video_demo"
-- require "sd"
-- require "xmodem"
-- pwm.open(2, 1000, 300,1000,1000)
-- sys.taskInit(sendFile,3, 115200, "/sd/fw/air101.fls")
-- require "camera_test"
-- require "camera_raw"
-- camDemo("10.0.0.3", 12000)
-- require "core_lcd"
-- require "lvgl_test"
-- require "pm_test"
-- require "no_block_test"
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!