--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2026.07.02
@author  拓毅恒
@usage
本demo演示的核心功能为：
1、play_file.lua： 播放音频文件，可支持mp3,amr,wav格式音频

2、play_tts: 文字转语音输出，循环演示5种音色

3、play_stream: 流式播放音频，支持PCM/MP3/AMR/WAV格式

4、sample-6s.mp3、10.amr: 用于测试本地音频文件播放

5、test.pcm: 用于测试pcm流式播放

6、本demo需要固件版本>=V1024才可播放音频

更多说明参考本目录下的readme.md文件
]]

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为999
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]

--[[
本demo可直接在Air1601核心板上直接运行
]]

PROJECT = "audio"
VERSION = "001.999.000"
-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end

-- Air1601/1602系列需要启用看门狗
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 音频对内存影响较大，不断的打印内存，用于判断是否异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)


-- 加载音频播放模块
-- require "play_file"          -- 文件播放音频，支持mp3,amr,wav格式
-- require "play_tts"          -- 文字转语音，循环演示5种音色
require "play_stream"       -- 流式播放音频，支持PCM/MP3/AMR/WAV格式

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
