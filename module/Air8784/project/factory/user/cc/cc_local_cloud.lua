-- 独立 CC 云通道与配置播报，不加载 SIP 任务引擎。
local app = require "cc_local_app"
local cloud = require "aircloud_tcp_adapter"
local protocol = require "aircloud_protocol"
local air = require "air1103"
local settings = require "aircloud_settings"
local speech = require("business_voice").new({
    startup_mode="cc", -- 开机播报不依赖 SIP 注册，也不触发 SIP 就绪播报。
    voice_call_idle=app.safe_idle,
    voice_ready=app.voice_ready,
    restore_volume=app.restore_volume,
})
settings.on_persisted = speech.changed
local backend = {}
function backend.idle()
    return speech.idle() and app.safe_idle() and not air.is_running()
end
function backend.status()
    local state = app.get_state()
    return {state=state, cc_state=state, sip_state="disabled", registered=false,
        connected=state=="CONNECTED", error=state=="ERROR" and "cc_init_failed" or nil}
end
-- settings.update 负责保存、pending 和号码变更。当前呼叫不读取新的号码。
-- 即使 CC 音频初始化失败，云端仍运行，允许远程切回 SIP。
local client = protocol.new(backend, cloud)
client.start()
sys.timerLoopStart(function() speech.step(250) end, 250)
return client
