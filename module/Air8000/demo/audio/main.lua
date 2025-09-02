
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "audio"
VERSION = "1.0.0"

--[[
本demo可直接在Air8000整机开发板上运行
]]



require "play_file"     --  播放文件
-- require "play_tts"      -- 播放tts
-- require "play_steam"        -- 流式播放
-- require "record_file"        -- 录音到文件
-- require "record_steam"        -- 流式录音   


sys.timerLoopStart(function()
    log.info("mem.lua", rtos.meminfo())
    log.info("mem.sys", rtos.meminfo("sys"))
 end, 3000)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
