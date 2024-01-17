
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "voltedemo"
VERSION = "1.0.0"

--[[
    本demo暂时只在air780ep测试过
    本demo需要外挂ES8311 codec芯片
]]

-- sys库是标配
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.subscribe("CC_IND", function(state)
    if state == "INCOMINGCALL" then
        cc.accept(0)
    end
end)

sys.taskInit(function()
    sys.wait(500)

    gpio.setup(16,0)
    gpio.set(16,1)

    local multimedia_id = 0
    local i2c_id = 1
    local i2s_id = 0
    local i2s_mode = 0
    local i2s_sample_rate = 16000
    local i2s_bits_per_sample = 16
    local i2s_channel_format = 0
    local i2s_communication_format = 0
    local i2s_channel_bits = 32

    i2c.setup(i2c_id,i2c.SLOW)
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)

    audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311",i2cid = i2c_id , i2sid = i2s_id})	--通道0的硬件输出通道设置为I2S
    audio.config(multimedia_id, 25, 0, 3, 100, 255, 0, 100)

    cc.init(multimedia_id)

end)

-- sys.taskInit(function()
--     while 1 do
--         -- 打印内存状态, 调试用
--         sys.wait(1000)
--         log.info("lua", rtos.meminfo())
--         log.info("sys", rtos.meminfo("sys"))
--     end
-- end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
