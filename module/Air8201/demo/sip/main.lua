--[[
@module  main
@summary LuatOS SIP/VoIP 电话应用入口，负责加载功能模块
@version 1.0
@date    2026.04.15
@author  蒋骞
@usage
本demo演示的核心功能为：
1. 使用 exsip.lua 封装库实现 SIP/VoIP 电话功能
2. 音频设备初始化与控制
3. SIP 事件回调处理
4. 按键接听电话

模块加载顺序：
1. 加载 sip_app_main 主业务模块
2. 加载 sip_app_key 按键控制模块
3. 加载 netdrv_device 网络驱动设备功能模块
4. 加载 tts_speaker TTS播报模块

Air8201 兼容 Air8201G（Air780EGH）和 Air8201H（Air780EHM）两款型号，通过 _G.HARDWARE_ENV 宏切换
- Air8201G: pa_ctrl=25, ES8311 3.3V
- Air8201H: pa_ctrl=23, ES8311 1.8V
netdrv_device：4G网卡 或 PC模拟器网卡 二选一

注意：
1. 本demo使用新音频框架，固件需要V2048及以上的13/113号固件才能播放
2. 使用本demo时需要确认audio_drv.lua中初始化配置的音频框架audio_mode = "new" 才能播放
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

PROJECT = "sip_demo_simple"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

--[[
硬件版本选择：修改下方 _G.HARDWARE_ENV 的值即可切换
    "G" = Air8201G (Air780EGH, pa_ctrl=25, ES8311 3.3V)
    "H" = Air8201H (Air780EHM, pa_ctrl=23, ES8311 1.8V)
]]--
_G.HARDWARE_ENV = "G"


-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- if errDump then
--     errDump.config(true, 600)
-- end


-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 可以使用合宙的iot.openluat.com平台进行远程升级
-- 也可以使用客户自己搭建的平台进行远程升级
-- 远程升级的详细用法，可以参考fota的demo进行使用


-- 加载网络驱动设备功能模块
require "netdrv_device"

-- 加载SIP电话应用模块
require "sip_app_key"
require "sip_app_main"
require "tts_speaker"


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
