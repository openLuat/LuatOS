--[[
@module  task_voice_config
@summary 固定任务提示语音的开关与本地音量
@version 1.1
@date    2026.09.29
@author  王世豪
@usage
只需tv_ok.pcm一个文件，16kHz/16bit/单声道PCM。
volume为Air1103本地喇叭0..31，不改变SIP与手机之间的桥接音量。
]]
return {enabled=true, volume=20, path="/luadb/", timeout_ms=10000}
