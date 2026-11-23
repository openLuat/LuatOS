-- PC 使用 VoIP 的直接音频路径，设备采集/播放由模拟器固件管理。
-- 不初始化 Air1103，也不等待 UART MIC 数据。VoIP 生命周期由 exsip 管理。
local M = {}
local ready = false
function M.check_firmware()
    for _, name in ipairs({"start", "stop", "isRunning", "on"}) do
        if not voip or type(voip[name]) ~= "function" then
            return false, "固件缺少 voip." .. name
        end
    end
    return true
end
function M.init()
    local ok, err = M.check_firmware()
    if not ok then log.error("single_audio_pc", err); return false end
    ready = true
    log.info("single_audio_pc", "使用 PC 直接音频路径，不使用 Air1103")
    return true
end
function M.is_ready() return ready end
function M.is_running() return ready and voip.isRunning() end
function M.stop() end -- exsip 负责停止媒体。
M.stop_bridge = M.stop
function M.play_ringback(callback)
    if callback then callback() end
    return true
end
M.play_hangup = M.play_ringback
function M.play_ringback_loop() return true end
function M.stop_ringback() return true end
function M.audio_status()
    return {supported=false, reason="PC 音量由系统音频设备控制"}
end
return M
