
--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.09.08
@author  梁健
@usage
本demo演示的核心功能为：
1、play_file.lua： 播放音频文件，可支持wav,amr,mp3 格式音频

2、play_tts: 支持文字转普通话输出需要固件支持

3、play_stream: 流式播放音频，仅支持PCM 格式，可以将音频推流到云端，用来对接大模型或者流式录音的应用。

4、record_file: 录音到文件，仅支持PCM 格式

5、record_stream:  流式录音，仅支持PCM，可以将音频流不断的拉取，可用来对接大模型

6、1.mp3: 用于测试本地mp3文件播放

7、test.pcm: 用于测试pcm 流式播放(实际可以云端下载)


更多说明参考本目录下的readme.md文件
]]
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "audio"
VERSION = "1.0.0"

--[[
本demo可直接在Air8000整机开发板上运行
]]



-- require "play_file"     --  播放文件
-- require "play_tts"      -- 播放tts
-- require "play_stream"        -- 流式播放
require "record_file"        -- 录音到文件
-- require "record_stream"        -- 流式录音   


sys.timerLoopStart(function()
    log.info("mem.lua", rtos.meminfo())
    log.info("mem.sys", rtos.meminfo("sys"))
 end, 3000)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
