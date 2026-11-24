-- UART6 选为语音档时显示 SIP 入口，C237 接通 Air1103 到功放后才启动话机。
local M = {}

function M.selected()
    local cfg = _G.project_config
    return cfg ~= nil and cfg.features ~= nil and cfg.features.sip == true
end

function M.reason()
    if not M.selected() then return "UART6 未选择 SIP 通话" end
    local hw = _G.project_config.hw or {}
    local audio = hw.audio
    if not audio or audio.model ~= "air1103" or audio.uart_id ~= 6 then
        return "SIP 通话需要 UART6 接到 Air1103（R25/R26）。"
    end
    if audio.play_model ~= "air1103" then
        return "双向通话需 C237 装配。请核对 C237 实贴、C104 空贴后，在「设置 → 接口复用 → 音频回放」选择 Air1103（C237），保存并重启。"
    end
    return ""
end

function M.ok()
    return M.reason() == ""
end

return M
