-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ccdemo"
VERSION = "1.0.0"
log.style(1)


-- sys库是标配
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    --wdt.init(9000)--初始化watchdog设置为9s
    --sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
local up1 = zbuff.create(6400,0)        --上行数据保存区1
local up2 = zbuff.create(6400,0)        --上行数据保存区2
local down1 = zbuff.create(6400,0)      --下行数据保存区1
local down2 = zbuff.create(6400,0)      --下行数据保存区2
local cnt = 0

gpio.setup(24, 1, gpio.PULLUP)          -- i2c工作的电压域
gpio.setup(164, 1, gpio.PULLUP) -- es8311电源使能脚
gpio.setup(162, 1, gpio.PULLUP) -- 喇叭pa功放脚
pins.setup(80, "I2C0_SCL")      --复用pin80为i2c0_scl
pins.setup(81, "I2C0_SDA")      --复用pin81为i2c0_sda

local multimedia_id = 0         -- 音频通道 0
local i2c_id = 0            -- i2c_id 0
local i2s_id = 0            -- i2s_id 0
local i2s_mode = 0          -- i2s模式 0 主机 1 从机
local i2s_sample_rate = 16000   -- 采样率
local i2s_bits_per_sample = 16      -- 数据位数
local i2s_channel_format = i2s.MONO_R        -- 声道, 0 左声道, 1 右声道, 2 立体声
local i2s_communication_format = i2s.MODE_LSB    -- 格式, 可选MODE_I2S, MODE_LSB, MODE_MSB
local i2s_channel_bits = 16     -- 声道的BCLK数量

local pa_pin = 162       -- 喇叭pa功放脚
local pa_on_level = 1       -- PA打开电平 1 高电平 0 低电平
local pa_delay = 100        -- 在DAC启动后，延迟多长时间打开PA，单位1ms
local power_pin = 164         -- es8311电源使能脚
local power_on_level = 1        -- 电源控制IO的电平，默认拉高
local power_delay = 3       -- 在DAC启动前插入的冗余时间，单位100ms
local power_time_delay = 100        -- 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms

local voice_vol = 70        -- 喇叭音量
local mic_vol = 65          -- 麦克风音量

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
        cnt = cnt + 1
        if cnt > 3 then
            cc.accept(0)   --自动接听
        end
    elseif state == "HANGUP_CALL_DONE" or state == "MAKE_CALL_FAILED" or state == "DISCONNECTED" then
        audio.pm(0,audio.STANDBY)
        -- audio.pm(0,audio.SHUTDOWN)   --低功耗可以选择SHUTDOWN或者POWEROFF，如果codec无法断电用SHUTDOWN
    end
end)

function cc_setup()

    cc.record(true, up1, up2, down1, down2)

    pm.power(pm.LDO_CTL, false)  --开发板上ES8311由LDO_CTL控制上下电
    sys.wait(100)
    pm.power(pm.LDO_CTL, true)  --开发板上ES8311由LDO_CTL控制上下电

    i2c.setup(i2c_id,i2c.FAST)      --设置i2c

    i2s.setup(i2s_id, i2s_mode, i2s_sample_rate, i2s_bits_per_sample, i2s_channel_format, i2s_communication_format,i2s_channel_bits)

    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
    audio.setBus(multimedia_id, audio.BUS_I2S,{chip = "es8311", i2cid = i2c_id, i2sid = i2s_id})    --通道0的硬件输出通道设置为I2S

    audio.vol(multimedia_id, voice_vol)
    audio.micVol(multimedia_id, mic_vol)

    cc.init(multimedia_id) --初始化电话功能

    sys.waitUntil("CC_READY")
    sys.wait(10000)
    cc.dial(0,"15893470522") --拨打电话
end
cc.on("record", record)--注册cc事件回调
sys.taskInit(cc_setup) --初始化cc

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