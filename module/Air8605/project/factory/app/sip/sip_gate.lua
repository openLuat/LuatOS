--[[
@module  sip_gate
@summary SIP 通话开启门槛：只给接了 Air1103 语音芯片的型号开 SIP 通话
@version 1.0
@date    2026.11.12
@author  江访

=== 为什么要这道门槛 ===

SIP 通话的语音通路整个压在 Air1103 上：上行 MIC 是 Air1103 的 UART6 上行帧，
下行喇叭是 Air1103 的流式 PCM。没有 Air1103 的板子跑 SIP 通话，注册能成、听不见声。
Air1103 是 UART 语音芯片，型号里只有 Air8605M / Air8605W 接了它
（对应 config 里 hw.audio.model = "air1103"），所以 SIP 通话只在这两个型号上开。

=== 两个条件缺一不可 ===

1. config.features.sip = true           显式开启：板子有 Air1103 也不一定想出 SIP 通话
2. config.hw.audio.model == "air1103"   硬前提：配置写错也开不起来，避免有声无声不一致

=== 对外接口 ===

  sip_gate.ok()      -> boolean  本机型是否开 SIP 通话
  sip_gate.reason()  -> string   没开时的原因（日志/诊断用），已开返回空串

=== 调用方 ===

ui/idle_win.lua         桌面「SIP通话」入口按它显隐
ui/sip_test_win.lua     开窗前自检，门槛没过不建窗口
]]

local M = {}

--[[
@function ok
@summary 本机型是否开 SIP 通话（features.sip + hw.audio.model=="air1103" 双条件）
@return boolean
]]
function M.ok()
    local c = _G.project_config
    if not c then return false end
    if not (c.features and c.features.sip) then return false end
    local ac = c.hw and c.hw.audio
    return ac ~= nil and ac.model == "air1103"
end

--[[
@function reason
@summary 没开 SIP 通话的原因，已开返回空串
@return string
]]
function M.reason()
    local c = _G.project_config
    if not c then return "未加载 project_config" end
    if not (c.features and c.features.sip) then return "config.features.sip 未开启" end
    local ac = c.hw and c.hw.audio
    if not ac then return "未配置 hw.audio（本机型没有 Air1103 语音芯片）" end
    if ac.model ~= "air1103" then
        return "hw.audio.model = " .. tostring(ac.model) .. "，SIP 通话只支持 Air1103"
    end
    return ""
end

return M
