
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ccdemo"
VERSION = "1.0.0"
log.style(1)
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
local up1 = zbuff.create(6400,0)
local up2 = zbuff.create(6400,0)
local down1 = zbuff.create(6400,0)
local down2 = zbuff.create(6400,0)


local function record(is_dl, point)
    if is_dl then
        log.info("下行数据，位于缓存", point+1, "缓存1数据量", down1:used(), "缓存2数据量", down2:used())
    else
        log.info("上行数据，位于缓存", point+1, "缓存1数据量", up1:used(), "缓存2数据量", up2:used())
    end
	log.info("通话质量", cc.quality())
    -- 可以在初始化串口后，通过uart.tx来发送走对应的zbuff即可
end

sys.subscribe("CC_IND", function(state)
    if state == "READY" then
        sys.publish("CC_READY")
    elseif state == "INCOMINGCALL" then
        cc.accept(0)
    end
end)

sys.taskInit(function()
    pm.power(pm.LDO_CTL, false)  --开发板上ES8311由LDO_CTL控制上下电
    sys.wait(100)
    pm.power(pm.LDO_CTL, true)  --开发板上ES8311由LDO_CTL控制上下电
    cc.on("record", record)
    cc.record(true, up1, up2, down1, down2)
    local multimedia_id = 0
    local i2c_id = 1
    local i2s_id = 0
    local i2s_mode = 0
    local i2s_sample_rate = 16000
    local i2s_bits_per_sample = 16
    local i2s_channel_format = 0
    local i2s_communication_format = 0
    local i2s_channel_bits = 32

    i2c.setup(i2c_id,i2c.FAST)
    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)

    audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311",i2cid = i2c_id , i2sid = i2s_id})	--通道0的硬件输出通道设置为I2S
    audio.config(multimedia_id, 25, 0, 3, 100, 255, 0, 100)
    cc.init(multimedia_id)
    sys.waitUntil("CC_READY")
    sys.wait(100)   
    --cc.dial(0,"114") --拨打电话



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
