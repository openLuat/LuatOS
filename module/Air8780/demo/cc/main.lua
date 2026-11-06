--[[
@module  main
@summary LuatOS语音通话应用主入口，负责加载功能模块
@version 1.2
@date    2026.11.06
@author  晁丹
@usage
本demo演示四种语音通话应用场景（四选一）：
场景一：基础通话功能（默认启用）
场景二：TTS循环播放与通话处理
场景三：通话录音文件保存
场景四：通话中播放外部音频

启用方式：保留对应 require，注释掉其余三行
  require "cc_app"                 -- 场景一
  require "cc_tts_app"             -- 场景二
  require "cc_record_save"         -- 场景三
  require "play_audio_during_cc"   -- 场景四

硬件：Air8780V（板载 Air780EHV，模组内置 ES8311，板上 AW8733 功放）
      ES8311 挂 I2C0，PA_EN=GPIO22，Codec 电源=GPIO20，板上无 TF 卡座

音频框架：按固件是否编入 audio_v2 自动选 new/old，见下方"音频框架"一段。

更多说明参考本目录下的readme.md文件
]] 

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
VERSION：项目版本号，ascii string类型
        使用合宙iot.openluat.com远程升级时必须按"XXX.YYY.ZZZ"三段格式定义

]] 
        
PROJECT = "VOICE_CALL_DEMO"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- if errDump then
--     errDump.config(true, 600)
-- end

-- 启动一个循环定时器，每隔3秒钟打印一次内存情况，方便分析内存异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)

-- ====================== 音频框架 ======================
-- 固件编入 audio_v2（新音频框架）时用 new，没编入时用 old。
local FW_NAME = (rtos.firmware and rtos.firmware()) or rtos.version()
local HAS_AUDIO_V2 = audio_v2 ~= nil and audio_v2.input ~= nil and audio_v2.config ~= nil
_G.AUDIO_MODE = _G.AUDIO_MODE or (HAS_AUDIO_V2 and "new" or "old")
log.info("main", "固件", FW_NAME, "audio_v2", HAS_AUDIO_V2 and "支持" or "不支持", "音频框架", _G.AUDIO_MODE)

-- 仅加载必要的功能模块
require "audio_drv" -- 音频设备管理模块

-- 加载通话业务逻辑模块（四选一）
-- 场景一：基础通话功能（默认启用）
require "cc_app"
-- 场景二：TTS循环播放与通话处理模块
-- require "cc_tts_app"
-- 场景三：通话录音文件保存（8780V 无 TF 卡座，写内部 flash）
-- require "cc_record_save"
-- 场景四：通话中播放外部音频（文件/TTS/流式），需 new 音频框架
-- require "play_audio_during_cc"

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run()之后不要加任何语句!!!!!
