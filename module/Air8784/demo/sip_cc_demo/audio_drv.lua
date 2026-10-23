--[[
@module  audio_drv
@summary 音频设备管理模块（8784 + Air1103 版）
@version 1.0
@date    2026.09.23
@author  蒋骞
@usage
本文件为音频设备管理模块，核心业务逻辑为：
1、用 exaudio.setup({model="air1103", audio_mode="new"}) 拉起本地 audio_v2 音频框架，
   跳过 I2C/PA/CODEC 全部硬件初始化(8784 无本地 ES8311/PA，语音走外置 Air1103，UART 固定 2M 波特率)；
2、静默 Air1103 的 MIC 上行(air1103.stop_audio() + set_rx_enable(false))：
   芯片上电/复位后默认持续发 32KB/s 上行音频，会占满 msgbus 挤掉 cc 系统消息(实测会死机)；
3、按 config.local_audio_default 设置初始喇叭音量(0 表示本地静音)，
   通话建立后由 bridge.apply_audio() 再次应用；
4、不提供 audio_drv.enable_cc_codec 接口：本硬件无 ES8311/PA，
   cc_main 里恢复外置 Codec 输出通路的分支会自动跳过；

SIP<->CC 的音频桥接由固件完成(cc_sip_bridge)，Air1103 不参与该数据通路；
本文件对外提供 audio_drv.init()/audio_drv.getMultimediaId() 接口，
直接在其他功能模块中require "audio_drv"就可以加载运行；
]]

local exaudio = require "exaudio"
local air1103 = require "air1103"
local cfg = require "config"

local audio_drv = {}

-- Air1103 模式: 仅初始化 audio_v2 新框架, 跳过 I2C/PA/CODEC 全部硬件初始化
local audio_configs = {
    model = "air1103",
    audio_mode = "new",
    uart_id = cfg.air1103_uart_id,
}

-- 供 cc 使用: Air1103 走 UART, 不占用多媒体设备 id
-- @return number 多媒体设备 id
function audio_drv.getMultimediaId()
    return 0
end

-- 初始化音频设备: 拉起 audio_v2 框架并静默 Air1103 MIC 上行
-- 必须在 sys 任务中调用(exaudio.setup 内部有等待)
-- @return boolean 成功返回 true
function audio_drv.init()
    log.info("audio_drv", "exaudio.setup 初始化音频设备(Air1103 模式, 跳过本地音频硬件)")
    local ok, result = pcall(exaudio.setup, audio_configs)
    if not ok or not result then
        log.error("audio_drv", "exaudio.setup 失败(Air1103 模式):", result)
        return false
    end
    log.info("audio_drv", "exaudio.setup 初始化成功(Air1103 模式)")

    -- 静默 Air1103 MIC 上行: 桥接不经过 1103, 不需要它的 MIC 数据,
    -- 不静默会被 32KB/s 上行占满 msgbus(up_test.lua 实测死机)
    air1103.stop_audio()
    air1103.set_rx_enable(false)
    log.info("audio_drv", "已静默 Air1103 MIC 上行(桥接数据由固件完成)")

    -- 初始音量与 local_audio_default 保持一致; 通话建立后 bridge.apply_audio() 会再应用一次。
    -- Air1103 的 0..31 档位映射到 exaudio.vol 的 0..100 百分比。
    if cfg.local_audio_default then
        exaudio.vol(math.ceil(cfg.air1103_volume * 100 / 31))
    else
        exaudio.vol(0)
    end
    return true
end

return audio_drv
