--[[
@module audio_diag
@summary 音频自检控制器：数据检测与人工听音确认严格分开。
start("tone" / "record" / "all") 非阻塞；record 录制 3 秒后自动回放。
status() 与 AUDIO_DIAG 事件提供同样的快照，confirm(true) 持久化人工确认。
]]
local audio = require "sph_audio_app"
local store = require "sph_store"
local M = {}

-- 人工确认状态缓存：UI 每秒都会调 status()（自检页要显示帧数/峰值），
-- 每次都去 fskv 读一次是慢速 flash 访问，和"回放期间重绘长文本"叠在一起就是
-- 回放卡顿的来源之一。这个键只有本模块会写，写成功时同步缓存即可。
local audio_ok = nil
local function verified()
    if audio_ok == nil then
        local ok, v = pcall(store.is_audio_verified)
        audio_ok = (ok and v == true) or false
    end
    return audio_ok
end
local state = {
    busy=false, stage="idle", detail="先播放测试音，再录音回放；声音需要人工确认",
    tone_complete=false, record_complete=false, confirmed=false,
}

function M.status()
    local result = {}
    for k,v in pairs(state) do result[k]=v end
    local data=audio.diagnostics()
    for _,k in ipairs({"frames","fps","mic_rate","peak","rx_bytes","bad_frames","volume"}) do result[k]=data[k] end
    result.data_ready=data.ready
    result.confirmed=verified()
    result.initializing=data.initializing
    return result
end
local function publish()
    sys.publish("AUDIO_DIAG",M.status())
end

function M.start(kind)
    kind=kind or "all"
    if kind~="tone" and kind~="record" and kind~="all" then return false,"invalid_test" end
    if state.busy or audio.is_busy() then return false,"audio_busy" end
    -- A SIP call may be ringing/dialing before its media bridge owns the speaker.
    local loaded,sip=pcall(require,"sph_sip_app")
    if not loaded then return false,"sip_state_unavailable" end
    if sip and sip.status then
        local s=sip.status()
        if s and (s.state=="incoming" or s.state=="dialing" or s.state=="talking" or s.state=="answering" or s.state=="ending") then return false,"call_busy" end
    end
    local saved,err=store.set_audio_verified(false)
    if not saved then return false,err or "storage_failed" end
    audio_ok=false
    state.busy=true;state.error=nil;state.stage="starting"
    if kind=="tone" or kind=="all" then state.tone_complete=false end
    if kind=="record" or kind=="all" then state.record_complete=false end
    state.detail="正在开始音频自检"
    publish()
    sys.taskInit(function()
        local list=kind=="all" and {"tone","record"} or {kind}
        local safe,ok,reason=pcall(function()
            for _,test in ipairs(list) do
                local passed,why=audio.diagnostic_run(test,function(stage,detail)
                    state.stage=stage;state.detail=detail;publish()
                end)
                if not passed then return false,why end
                if test=="tone" then state.tone_complete=true else state.record_complete=true end
            end
            return true
        end)
        if not safe then reason=ok;ok=false end
        state.busy=false
        if ok then
            state.stage="awaiting_confirmation"
            state.detail="数据检查完成；请人工确认测试音和录音回放均清晰正常"
        else
            state.stage="failed";state.error=tostring(reason)
            state.detail="自检失败，请检查 UART6、GPIO73、C237、R253 与功放 SD 电平"
        end
        publish()
    end)
    return true
end

function M.confirm(accepted)
    if state.busy or audio.is_busy() then return false,"audio_busy" end
    if accepted and (not state.tone_complete or not state.record_complete or not audio.is_ready()) then
        return false,"complete_both_tests_first"
    end
    local ok,err=store.set_audio_verified(accepted==true)
    if not ok then return false,err or "storage_failed" end
    audio_ok = accepted==true
    state.stage=accepted and "confirmed" or "awaiting_confirmation"
    state.detail=accepted and "人工确认已保存，可以验证 SIP 通话" or "尚未确认声音正常，SIP 通话保持禁用"
    publish()
    return true
end
return M
