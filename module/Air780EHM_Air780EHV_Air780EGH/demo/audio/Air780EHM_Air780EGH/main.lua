
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

6、sample-6s: 用于测试本地mp3文件播放

7、test.pcm: 用于测试pcm 流式播放(实际可以云端下载)


更多说明参考本目录下的readme.md文件
]]

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]

--[[
本demo可使用Air780EHM核心板/Air780EGH核心板+AirAUDIO_1010 音频扩展板+喇叭两种硬件环境演示
]]

PROJECT = "audio"
VERSION = "001.000.000"
-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)




-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end

-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)




-- require "play_file"     --   播放音频文件，可支持wav,amr,mp3 格式音频
--  require "play_tts"      -- 支持文字转普通话输出需要固件支持
 -- require "play_stream"        -- 流式播放音频，仅支持PCM 格式，可以将音频推流到云端，用来对接大模型或者流式录音的应用。
require "record_file"        -- 录音到文件
-- require "record_stream"        -- 流式录音   

-- 音频对内存影响较大，不断的打印内存，用于判断是否异常
sys.timerLoopStart(function()
    log.info("mem.lua", rtos.meminfo())
    log.info("mem.sys", rtos.meminfo("sys"))
 end, 3000)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
