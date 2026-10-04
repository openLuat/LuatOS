--[[
@module  cc_audio
@summary 音频设备管理模块（8784 + Air1103 版）
@version 2.1
@date    2026.09.23
@author  蒋骞
@usage
协同配置版本：运行模式独立于主动任务保存，删除任务不改变模式。
本文件为音频设备管理模块，核心业务逻辑为：
1、用 exaudio.setup({model="air1103", audio_mode="new"}) 拉起本地 audio_v2 音频框架，
   跳过 I2C/PA/CODEC 全部硬件初始化(8784 无本地 ES8311/PA，语音走外置 Air1103，UART 固定 2M 波特率)；
2、静默 Air1103 的 MIC 上行(air1103.stop_audio() + set_rx_enable(false))：
   芯片上电/复位后默认持续发 32KB/s 上行音频，会占满 msgbus 挤掉 cc 系统消息(实测会死机)；
3、按 config.local_audio_default 设置初始喇叭音量(0 表示本地静音)，
   通话建立后由 bridge.apply_audio() 再次应用；
4、不提供 cc_audio.enable_cc_codec 接口：本硬件无 ES8311/PA，
   cc_main 里恢复外置 Codec 输出通路的分支会自动跳过；

SIP<->CC 的音频桥接由固件完成(cc_sip_bridge)，Air1103 不参与该数据通路；
本文件对外提供 cc_audio.init()/cc_audio.getMultimediaId() 接口，
直接在其他功能模块中require "cc_audio"就可以加载运行；
]]

local exaudio = require "exaudio"
local air1103 = require "air1103"
local cfg = require "sip_config"
local single_config = require "single_config"
local hardware = single_config.audio

local cc_audio = {}
local initialized = false
function cc_audio.is_ready() return initialized end

-- Air1103 模式: 仅初始化 audio_v2 新框架, 跳过 I2C/PA/CODEC 全部硬件初始化
local audio_configs = {
    model = "air1103",
    audio_mode = "new",
    uart_id = cfg.air1103_uart_id,
}

-- 供 cc 使用: Air1103 走 UART, 不占用多媒体设备 id
-- @return number 多媒体设备 id
function cc_audio.getMultimediaId()
    return 0
end

-- 初始化音频设备: 拉起 audio_v2 框架并静默 Air1103 MIC 上行
-- 必须在 sys 任务中调用(exaudio.setup 内部有等待)
-- @return boolean 成功返回 true
function cc_audio.init()
    initialized = false
    -- SIP_CC桥接不使用Air1103，但本地任务播报需要真实上电。
    -- 与单SIP复用同一份硬件引脚配置，不加载单SIP业务或音频模块。
    if type(hardware.power_gpio)=="number" then
        gpio.setup(hardware.power_gpio, hardware.power_on_level or 1)
        log.info("cc_audio", "Air1103 power on", hardware.power_gpio, hardware.power_on_level or 1)
        sys.wait(hardware.boot_ms or 1500)
    end
    log.info("cc_audio", "exaudio.setup 初始化音频设备(Air1103 模式, 跳过本地音频硬件)")
    local ok, result = pcall(exaudio.setup, audio_configs)
    if not ok or not result then
        log.error("cc_audio", "exaudio.setup 失败(Air1103 模式):", result)
        air1103.stop_audio()
        air1103.set_rx_enable(false)
        return false
    end
    log.info("cc_audio", "exaudio.setup 初始化成功(Air1103 模式)")

    -- 静默 Air1103 MIC 上行: 桥接不经过 1103, 不需要它的 MIC 数据,
    -- 不静默会被 32KB/s 上行占满 msgbus(up_test.lua 实测死机)
    air1103.stop_audio()
    air1103.set_rx_enable(false)
    log.info("cc_audio", "已静默 Air1103 MIC 上行(桥接数据由固件完成)")

    -- 初始音量与 local_audio_default 保持一致; 通话建立后 bridge.apply_audio() 会再应用一次。
    -- Air1103 的 0..31 档位映射到 exaudio.vol 的 0..100 百分比。
    if cfg.local_audio_default then
        exaudio.vol(math.ceil(cfg.air1103_volume * 100 / 31))
    else
        exaudio.vol(0)
    end
    initialized = true
    return true
end

return cc_audio
