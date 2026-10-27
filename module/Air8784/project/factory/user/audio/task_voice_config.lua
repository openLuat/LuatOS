--[[
@module  task_voice_config
@summary 任务提示音（TTS）配置：文案、音量、超时
@version 1.0
@date    2026.10.27
@author  王世豪
@usage
纯配置表：
- enabled       是否启用任务语音与双提示音
- volume        Air1103 本地喇叭档位（0..31）
- timeout_ms    单次提示播放超时（毫秒）
- task_text     保存主动任务后的播报文案
- receiver_text 仅接听模式就绪后的播报文案
]]
-- Runtime TTS text and local Air1103 speaker volume (0..31).
return {enabled=true,volume=20,timeout_ms=10000,
    task_text="任务已生效",receiver_text="仅接听模式已生效"}
