--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
        可以随便定义，只要不使用,就行
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可

本demo实现的业务逻辑为：
1、Air8101核心板+USB HUB+4个USB摄像头，注意根据USB摄像头的规格书，拨动核心板上的3.3V和5V的按键开关
2、每隔10秒循环一次，依次启动4个USB摄像头中的其中一个，拍照然后上传到http服务器，可以在http前端页面查看拍摄的照片
]]

PROJECT = "AirUSBHUB_1000"
VERSION = "001.000.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 加载必须用到的sys功能模块
-- sys功能模块是LuatOS运行框架的基础模块
_G.sys = require("sys")


-- 加载大部分情况下会用到的sysplus功能模块
-- sysplus功能模块是sys功能模块的强力补充
-- 如果项目脚本中用到了sysplus的接口，则打开此处的注释
-- _G.sysplus = require("sysplus")


-- 如果内核固件支持wdt看门狗功能，此处对看门狗进行初始化和定时喂狗处理
-- 如果脚本程序死循环卡死，就会无法及时喂狗，最终会自动重启
if wdt then
    --配置喂狗超时时间为9秒钟
    wdt.init(9000)
    --启动一个循环定时器，每隔3秒钟喂一次狗
    sys.timerLoopStart(wdt.feed, 3000)
end


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


-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
sys.timerLoopStart(function()
    log.info("mem.lua", rtos.meminfo())
    log.info("mem.sys", rtos.meminfo("sys"))
 end, 3000)

-- 加载WIFI网络连接管理功能模块
require "wifi_app"
-- 加载AirUSBHUB_1000外挂的摄像头拍照并且通过http上传照片的功能模块
require "http_app"



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
