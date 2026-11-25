-- UART6 选为语音档时显示 SIP 入口，C237 接通 Air1103 到功放后才启动话机。
local M = {}

function M.selected()
    local cfg = _G.project_config
    return cfg ~= nil and cfg.features ~= nil and cfg.features.sip == true
end

function M.reason()
    if not M.selected() then return "当前型号的 UART6 用于 J22 TTL 串口。" end
    local hw = _G.project_config.hw or {}
    local audio = hw.audio
    if not audio or audio.model ~= "air1103" or audio.uart_id ~= 6 then
        return "SIP 通话需要 UART6 接到 Air1103（R25/R26）。"
    end
    if audio.play_model ~= "air1103" then
        return "双向通话需要 Air1103 通过 C237 接入功放，请核对烧录型号和音频装配。"
    end
    return ""
end

function M.ok()
    return M.reason() == ""
end

return M
