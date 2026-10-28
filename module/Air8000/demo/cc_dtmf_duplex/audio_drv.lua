--[[
@module audio_drv
@summary Air8000 开发板板载 ES8311 的普通通话音频配置
@usage
main.lua 调用 initAudioDevice() 初始化音频，再将 getMultimediaId() 返回值传给 cc.init。
ES8311 负责麦克风采集和扬声器侧音频转换；本文件配置硬件，DTMF 收发在 main.lua。
更换开发板/音频电路时，应按原理图修改下方 I2C、功放和 codec 控制引脚。
]]
local exaudio = require("exaudio")
local M = {}

function M.initAudioDevice()
    -- 保留旧音频框架的延时单位兼容配置：V2026 起 dac_delay 单位为 100ms，
    -- 更早版本为 1ms，因此 6 / 600 均对应 600ms。
    -- 当前 audio_mode="new" 的 ES8311 路径不直接使用 dac_delay/dac_time_delay，
    -- codec 电源由 exaudio 管理并保持供电；功放启动延时使用 pa_delay。
    local version = (rtos.version() or ""):match("V(%d+)")
    local ok = exaudio.setup({
        model = "es8311",      -- 选择板载 codec 驱动。
        i2c_id = 0,             -- ES8311 寄存器控制总线；音频数据经 I2S 传输。
        pa_ctrl = 162,          -- Air8000 开发板功放控制 GPIO。
        dac_ctrl = 164,         -- Air8000 开发板 codec 电源控制 GPIO。
        dac_delay = tonumber(version) and tonumber(version) >= 2026 and 6 or 600,
        pa_delay = 100,         -- 功放启动延时，单位 ms，用于配合音频通路启动。
        dac_time_delay = 100,   -- 旧框架关闭 PA/DAC 的兼容延时，当前新框架路径不使用。
        bits_per_sample = 16,  -- 本地音频采样位深。
        pa_on_level = 1,        -- 功放使能有效电平：1 为高电平。
        audio_mode = "new",    -- 使用配套固件的 Audio V2 音频框架。
    })
    if not ok then return false end
    -- 可根据实际喇叭和麦克风调整；这两项不改变网络 DTMF 的按键值或请求时长。
    exaudio.vol(70)             -- 扬声器音量。
    exaudio.mic_vol(65)         -- 麦克风音量/增益配置。
    log.info("cc_dtmf_audio", "ES8311 ready I2C0 PA 162 DAC 164")
    return true
end

function M.getMultimediaId()
    -- 0 是本例使用的音频通道 ID，交给 cc.init(0) 初始化普通通话音频。
    return 0
end

return M
