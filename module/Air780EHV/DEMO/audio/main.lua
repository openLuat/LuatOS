-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "audio"
VERSION = "1.0.0"

--[[]
运行环境：Air780EHV核心板+AirAUDIO_1000配件板
最后修改时间：2025-6-17
使用了如下IO口：
[5, "spk+", " PIN5脚, 用于喇叭正极"],
[6, "spk-", " PIN6脚, 用于喇叭负极"],
[20, "AudioPA_EN", " PIN20脚, 用于PA使能脚"],
3.3V
GND
SD卡的使用IO口：
[83, "SPI0CS", " PIN83脚, 用于SD卡片选脚"],
[84, "SPI0MISO," PIN84脚, 用于SD卡数据脚"],
[85, "SPI0MOSI", " PIN85脚, 用于SD卡数据脚"],
[86, "SPI0CLK", " PIN86脚, 用于SD卡时钟脚"],
[24, "VDD_EXT", " PIN24脚, 用于给SD卡供电脚"],
GND
执行逻辑为：
设置i2s和音频参数，写了四种操作方式
1、播放脚本区的文件
2、挂载SD卡，通过HTTP下载到SD卡，播放SD卡中的文件
3、通过HTTP下载到文件区，播放文件区中的文件
4、通过HTTP下载到内存里面，播放内存中的文件
]]
-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

--目前代码里面提供了4种播放方式，对应mode的值，默认是1
--1:播放脚本区的文件
--2:挂载SD卡，通过HTTP下载到SD卡，播放SD卡中的文件
--3:通过HTTP下载到文件区，播放文件区中的文件
--4:通过HTTP下载到内存里面，播放内存中的文件
local mode = 1
local i2c_id = 0 -- i2c_id 0

local pa_pin = gpio.AUDIOPA_EN -- 喇叭pa功放脚
local power_pin = 20 -- es8311电源脚

local i2s_id = 0 -- i2s_id 0
local i2s_mode = 0 -- i2s模式 0 主机 1 从机
local i2s_sample_rate = 16000 -- 采样率
local i2s_bits_per_sample = 16 -- 数据位数
local i2s_channel_format = i2s.MONO_R -- 声道, 0 左声道, 1 右声道, 2 立体声
local i2s_communication_format = i2s.MODE_LSB -- 格式, 可选MODE_I2S, MODE_LSB, MODE_MSB
local i2s_channel_bits = 16 -- 声道的BCLK数量

local multimedia_id = 0 -- 音频通道 0
local pa_on_level = 1 -- PA打开电平 1 高电平 0 低电平
local power_delay = 3 -- 在DAC启动前插入的冗余时间，单位100ms
local pa_delay = 100 -- 在DAC启动后，延迟多长时间打开PA，单位1ms
local power_on_level = 1 -- 电源控制IO的电平，默认拉高
local power_time_delay = 100 -- 音频播放完毕时，PA与DAC关闭的时间间隔，单位1ms

local voice_vol = 50 -- 喇叭音量
local mic_vol = 80 -- 麦克风音量

gpio.setup(power_pin, 1, gpio.PULLUP) -- 设置ES83111电源脚
gpio.setup(pa_pin, 1, gpio.PULLUP) -- 设置功放PA脚

function audio_setup()
    log.info("audio_setup")
    sys.wait(200)

    i2c.setup(i2c_id, i2c.FAST)
    i2s.setup(
        i2s_id,
        i2s_mode,
        i2s_sample_rate,
        i2s_bits_per_sample,
        i2s_channel_format,
        i2s_communication_format,
        i2s_channel_bits
    )

    audio.config(multimedia_id, pa_pin, pa_on_level, power_delay, pa_delay, power_pin, power_on_level, power_time_delay)
    audio.setBus(
        multimedia_id,
        audio.BUS_I2S,
        {
            chip = "es8311",
            i2cid = i2c_id,
            i2sid = i2s_id
        }
    ) -- 通道0的硬件输出通道设置为I2S
    audio.vol(multimedia_id, voice_vol)
    audio.micVol(multimedia_id, mic_vol)
    sys.publish("AUDIO_READY")
end

-- 配置好audio外设
sys.taskInit(audio_setup)

local taskName = "task_audio"

local MSG_MD = "moreData" -- 播放缓存有空余
local MSG_PD = "playDone" -- 播放完成所有数据

audio.on(0,function(id, event)
        -- 使用play来播放文件时只有播放完成回调
        local succ, stop, file_cnt = audio.getError(0)
        if not succ then
            if stop then
                log.info("用户停止播放")
            else
                log.info("第", file_cnt, "个文件解码失败")
            end
        end
        sysplus.sendMsg(taskName, MSG_PD)
    end
)

local function audio_task()
    local result
    sys.waitUntil("AUDIO_READY")
    result = sys.waitUntil("IP_READY", 15000)
    if result then
        if mode == 1 then
        elseif mode == 2 then
            --以下内容为SD卡挂载的方式，如果有需要用到SD卡可以打开下面的挂载流程
            -- -- 此为spi方式
            local spi_id, pin_cs = 0, 8
            -- 仅SPI方式需要自行初始化spi, sdio不需要
            spi.setup(spi_id, nil, 0, 0, pin_cs, 400 * 1000)
            gpio.setup(pin_cs, 1)
            fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000)
            local code, headers, body =
                http.request("GET", "http://airtest.openluat.com:2900/download/1.mp3", nil, nil, {dst = "/sd/1.mp3"}).wait()
            --存到sd卡里面
            log.info("下载完成", code, headers, body)
        elseif mode == 3 then
            local code, headers, body =
                http.request("GET", "http://airtest.openluat.com:2900/download/1.mp3", nil, nil, {dst = "/1.mp3"}).wait()
            --存到本地文件区，适用于多次播放
            log.info("下载完成", code, headers, body)
        elseif mode == 4 then
            local code, headers, body =
                http.request("GET", "http://airtest.openluat.com:2900/download/1.mp3", nil, nil, {dst = "/ram/1.mp3"}).wait()
            --存到内存里面，适用于下载播放一次，然后不需要再次播放或者不重启的时候可以继续播放，重启后需要重新下载
            log.info("下载完成", code, headers, body)
        end
    end

    while true do
        log.info("开始播放")
        if result then
            if mode == 1 then
                result = audio.play(0, "/luadb/1.mp3") -- 播放本地脚本区文件
            elseif mode == 2 then
                result = audio.play(0, "/sd/1.mp3") -- 播放sd卡里面文件
            elseif mode == 3 then
                result = audio.play(0, "/1.mp3") --播放HTTP下载的文件
            elseif mode == 4 then
                result = audio.play(0, "/ram/1.mp3") --播放HTTP下载到内存的文件
            end
        end
        if result then
            --等待音频通道的回调消息，或者切换歌曲的消息
            while true do
                msg = sysplus.waitMsg(taskName, nil)
                if type(msg) == "table" then
                    if msg[1] == MSG_PD then
                        log.info("播放结束")
                        break
                    end
                else
                    log.error(type(msg), msg)
                end
            end
        else
            log.debug("解码失败!")
            sys.wait(1000)
        end
        if not audio.isEnd(0) then
            log.info("手动关闭")
            audio.playStop(0)
        end
        if audio.pm then
            audio.pm(0, audio.STANDBY) --PM模式 待机模式，PA断电，codec待机状态，系统不能进低功耗状态，如果PA不可控，codec进入静音模式
        end
        -- audio.pm(0,audio.SHUTDOWN)	--低功耗可以选择SHUTDOWN或者POWEROFF，如果codec无法断电用SHUTDOWN
        log.info("mem", "sys", rtos.meminfo("sys"))
        log.info("mem", "lua", rtos.meminfo("lua"))
        sys.wait(1000)
    end
end

sys.timerLoopStart(
    function()
        log.info("mem.lua", rtos.meminfo())
        log.info("mem.sys", rtos.meminfo("sys"))
    end,
    3000
)

sysplus.taskInitEx(audio_task, taskName)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
