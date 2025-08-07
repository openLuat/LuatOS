--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑 
@version 1.0
@date    2025.07.28
@author  朱天华
@usage
本demo演示的核心功能为：
1、分别使用http核心库和httpplus扩展库，演示以下几种应用场景的使用方式
   (1) 普通的http get请求功能演示；
   (2) http get下载压缩数据的功能演示；
   (3) http get下载数据保存到文件中的功能演示；(仅http核心库支持，httpplus扩展库不支持)
   (4) http post提交表单数据功能演示；
   (5) http post提交json数据功能演示；
   (6) http post提交纯文本数据功能演示；
   (7) http post提交xml数据功能演示；
   (8) http post提交原始二进制数据功能演示；
   (9) http post文件上传功能演示；
2、netdrv_device：配置连接外网使用的网卡，目前支持以下四种选择（四选一）
   (1) netdrv_4g：4G网卡
   (2) netdrv_wifi：WIFI STA网卡
   (3) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡
   (4) netdrv_multiple：支持以上三种网卡，可以配置三种网卡的优先级

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
PROJECT = "HTTP"
VERSION = "001.000.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


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
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)

-- 加载网络驱动设备功能模块
require "netdrv_device"

-- 加载http应用功能模块
require "http_app"
-- 加载httpplus应用功能模块
require "httpplus_app"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
