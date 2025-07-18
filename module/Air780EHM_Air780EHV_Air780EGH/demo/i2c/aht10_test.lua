--[[
@module  aht10_test
@summary aht10_test测试功能模块
@version 1.0
@date    2025.07.01
@author  yc
@usage
使用Air780EHV核心板 配合 aht10 传感器 演示i2c通信功能.
]]



local aht10 = require "aht10"

function aht10_test_func()
--电平设置为3.3v
pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
--设置gpio2输出,给camera_sda、camera_scl引脚提供上拉
gpio.setup(2, 1)

i2cid = 1
i2c_speed = i2c.FAST

i2c.setup(i2cid,i2c_speed)
--初始化,传入i2c_id
aht10.init(i2cid)
while 1 do
    local aht10_data = aht10.get_data()
    log.info("aht10_data", "aht10_data.RH:"..(aht10_data.RH*100).."%","aht10_data.T"..(aht10_data.T).."℃")
    sys.wait(2000)

end

end
--创建并且启动一个task
--运行这个task的主函数aht10_test_func
sys.taskInit(aht10_test_func)
