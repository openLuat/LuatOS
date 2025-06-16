
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "aht10demo"
VERSION = "1.0.0"

-- sys库是标配
sys = require("sys")

local aht10 = require "aht10"

-- 接线
--[[
AHT10 --- 模块
SDA   -   I2C_SDA
SCL   -   I2C_SCL
VCC   -   VDDIO
GND   -   GND
]]

--电平设置为3.3v
pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
--设置gpio2输出,给camera_sda、camera_scl引脚提供上拉
gpio.setup(2, 1)

i2cid = 1
i2c_speed = i2c.FAST

sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    aht10.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local aht10_data = aht10.get_data()
        log.info("aht10_data", "aht10_data.RH:"..(aht10_data.RH*100).."%","aht10_data.T"..(aht10_data.T).."℃")
        sys.wait(1000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
