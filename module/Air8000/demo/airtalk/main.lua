--[[
@module  main
@summary LuatOS语音对讲应用主入口，负责加载功能模块
@version 1.0
@date    2025.12.08
@author  陈媛媛
@usage
本demo演示的核心功能为：
1、netdrv_device：网络驱动设备配置（选择4G/WiFi/以太网/多网卡/PC模拟器）
2、audio_drv：音频设备初始化与控制
3、talk：airtalk 对讲业务逻辑处理

模块加载顺序严格按照：
1. 网络驱动 → 2. 音频驱动 → 3. 对讲业务
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

PROJECT = "extalk"
VERSION = "001.000.000"

-- 到 iot.openluat.com 创建项目，获取正确的项目key
PRODUCT_KEY =  "5544VIDOIHH9Nv8huYVyEIGT4tCvldxI"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


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

-- ========================== 模块加载顺序 ==========================

-- 1. 首先加载网络驱动设备模块（配置网络连接）
-- 注意：在netdrv_device.lua中会根据需要加载具体的网络驱动
require "netdrv_device"

-- 2. 加载音频驱动模块
require "audio_drv"

-- 3. 加载对讲主业务模块
require "talk"

-- ========================== 系统监控 ==========================

-- 内存监控，每30秒打印一次内存使用情况（语音对讲对内存要求较高，需要监控）
sys.timerLoopStart(function()
    log.info("内存使用情况:")
    log.info("  Lua内存:", rtos.meminfo())
    log.info("  系统内存:", rtos.meminfo("sys"))
end, 30000)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!