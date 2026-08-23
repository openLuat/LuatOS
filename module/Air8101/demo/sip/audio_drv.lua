--[[
@module  audio_drv
@summary 音频驱动模块
@version 1.0
@date    2026.04.15
@usage
本模块负责音频设备的初始化和配置
]]

local exaudio = require "exaudio"

local audio_drv = {}

local audio_configs ={
    model = "dac",            -- 音频编解码类型: "dac" 表示使用内置DAC
    
    pa_ctrl = 27,             -- 音频放大器电源控制管脚
    pa_on_level = 1,          -- PA打开电平
    pa_delay = 10,            -- PA延时
    audio_mode = "new"      -- 音频模式: "new" 表示使用新的audio_v2音频模式
}

--================================================================
-- 音量/增益配置（根据实际音效调整下面的值）
--================================================================

-- mic音量：通过 audio_v2.config 设置 Air8101(BK7258) audio_v2 驱动的私有参数
-- （参数定义见固件 projects/luatos/ap/components/luatos/srcs/luat_audio_bk72xx_v2.h）
local CFG_PARAM_ADC_DIG_GAIN = 0x424b0101  -- ADC(mic)数字增益，取值 0~0x3f(63)，默认 0x2d(45)
local CFG_PARAM_ADC_ANA_GAIN = 0x424b0102  -- ADC(mic)模拟增益，取值 0~0x0f(15)，默认 0

-- 调优原则：模拟增益(前置放大)为主，数字增益为辅；任何一级过大都可能让ADC饱和削波，
-- 表现为"音量大但破音/发闷/杂音重"，削波后AEC降噪还会引入"水下音"
-- 数字增益默认0x2d(45)=0dB，超过默认值的部分为纯数字放大，建议只在0x2d~0x35之间微调
-- 模拟增益每档约3dB，建议从0x02开始，每次+0x01边听边调，一般0x02~0x06足够
local MIC_ADC_DIG_GAIN = 0x3f   -- mic数字增益，默认0x2d=0dB，最大0x3f，不建议超过0x35
local MIC_ADC_ANA_GAIN = 0x03   -- mic模拟增益，越大mic越灵敏，太大必失真，范围0~0x0f

-- 喇叭音量：SIP通话走的是 audio_v2 的 speech 直通通道，audio_v2.soft_volume/exaudio.vol 对通话不生效；
-- 且 Air8101(BK7258) 的 audio_v2 驱动没有通过 audio_v2.config 暴露 DAC 增益参数，
-- 所以这里用旧接口 audio.vol 直接设置 DAC 硬件增益（0~100 映射到增益寄存器 0~0x3f，不设置时默认约等于70）
local DAC_PLAY_VOL = 40       -- 喇叭音量，0~100，喇叭声音大就往小了调

-- 设置mic增益
-- audio_v2.config配置的值会保存在驱动中，通话建立ADC启动时自动生效；通话中调用则立即生效
local function config_mic_gain()
    local ret1 = audio_v2.config(CFG_PARAM_ADC_DIG_GAIN, MIC_ADC_DIG_GAIN)
    local ret2 = audio_v2.config(CFG_PARAM_ADC_ANA_GAIN, MIC_ADC_ANA_GAIN)
    log.info("audio_drv", "设置mic增益, 数字增益:", string.format("0x%02x", MIC_ADC_DIG_GAIN), ret1,
             "模拟增益:", string.format("0x%02x", MIC_ADC_ANA_GAIN), ret2)

    -- 可选：如果增益调大后底噪(嘶嘶声)明显，且确认板子mic是单端接法，可以尝试改为单端模式
    -- 驱动默认是差分模式(AUD_ADC_MODE_DIFFEN=0)，单端模式值为1
    -- audio_v2.config(0x424b0103, 1)

    -- 可选：如果mic几乎没声音，可能是mic接在另一个通道上，可以尝试交换mic通道
    -- audio_v2.config(0x424b0100, 1)
end

-- 设置喇叭音量（DAC硬件增益）
-- 注意：每次通话建立时DAC硬件会重新初始化为默认增益，所以必须在通话音频启动之后再设置，
-- 这里通过订阅 SIP_APP_MAIN_VOIP_STARTED 消息，在每次通话音频启动后重新设置
local function config_dac_vol()
    local vol = audio.vol(0, DAC_PLAY_VOL)
    log.info("audio_drv", "设置喇叭音量(DAC硬件增益):", DAC_PLAY_VOL, "实际生效:", vol)
end

function audio_drv.init()
    if rtos and rtos.bsp and rtos.bsp() and rtos.bsp():find("PC") then
        log.info("audio_drv", "PC 模拟器，跳过音频初始化")
        return true
    end

    --初始化音频设备
    if exaudio.setup(audio_configs) then
        log.info("audio_drv", "exaudio.setup初始化成功")

        -- TTS播报等普通播放通道的软件音量（对SIP通话通道无效）
        if exaudio.vol then
            exaudio.vol(DAC_PLAY_VOL)
            log.info("audio_drv", "已设置普通播放(TTS)软件音量为: 20")
        end

        -- 设置mic增益（对SIP通话生效）
        config_mic_gain()

        -- 订阅通话音频启动消息，每次通话开始后重新设置喇叭音量
        sys.subscribe("SIP_APP_MAIN_VOIP_STARTED", config_dac_vol)

        return true
    else
        log.error("audio_drv", "exaudio.setup初始化失败")
        return false
    end
end

return audio_drv
