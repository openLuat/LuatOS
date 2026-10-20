--[[
@module  air8784_tts_demo
@summary Air8784（Air780EHM + Air1103）离线 TTS 语音播报示例入口
@version 1.0.0
@date    2026.10.15
@author  王世豪
@usage
演示 Air8784 主控 Air780EHM 外挂 Air1103 语音芯片的「离线 TTS」播报：
1. 本文件为入口：上电使能 Air1103（GPIO22 高电平），随后加载 tts_app 模块；
2. 具体的 TTS 播报逻辑在 tts_app.lua：exaudio.setup(audio_mode="new") 初始化，
   再 exaudio.play_start({type=1, content=文本}) 触发本地合成播放，无需联网；
   初始化完成后开机播报一次，之后每按一次 SOS 按键(GPIO20)再播报一次；
3. 依赖：固件需编入 tts_pcm 离线语音合成引擎（需 Air780EHM 13号固件）；
         同时需要v3.10及之后版本的exaudio.lua扩展库。
更多说明参考本目录下的 readme.md 文件
]]

PROJECT = "air8784_tts_demo"
VERSION = "001.999.001"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 可选：看门狗（9s 超时 / 3s 喂狗；硬狗默认启用也可不加）
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 1000)
end

-- Air1103 供电使能
gpio.setup(22, 1)

-- 加载 TTS 播报功能模块（require 时自动启动播放任务）
require "tts_app"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
