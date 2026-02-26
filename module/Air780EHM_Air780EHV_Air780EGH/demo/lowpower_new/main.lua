--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2026.02.12
@author  马梦阳
@usage
本demo演示的核心功能为：
通过若干个prj目录下的应用项目，演示常规模式，低功耗模式，PSM+模式的使用方法

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
PROJECT = "LOWPOWER"
VERSION = "001.000.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


------------------------------------ 加载应用项目主调度功能模块（每次从以下项目中选择一个来演示运行）-----------------------------------

-- 常规模式下的tcp长连接项目（每5分钟发送一次数据到tcp server）
require "prj_0_tcp_long"

-- PSM+模式3简单项目
-- require "prj_3"

-- 低功耗模式1简单项目
-- require "prj_1"

-- 常规模式0和低功耗模式1切换项目
-- require "prj_0_1"

-- 低功耗模式下的tcp长连接项目（每5分钟发送一次数据到tcp server）
-- require "prj_1_tcp_long"

-- PSM+模式下的tcp短连接项目（每次开机，发送一次数据到tcp server，无论成功还是失败，然后进入PSM+模式，1小时后唤醒）
-- require "prj_3_tcp_short"

-- 低功耗模式下的mqtt长连接项目（每5分钟发送一次数据到mqtt server）
-- require "prj_1_mqtt_long"

-- PSM+模式下的mqtt短连接项目（每次开机，读取一次温湿度数据，然后发送到mqtt server，无论成功还是失败，然后进入PSM+模式，1小时后唤醒）
-- require "prj_3_mqtt_short"

-- 低功耗模式+飞行模式下的上位机通过串口控制拍照以及照片回传项目（uart1 9600波特率接收上位机拍照指令，拍照后，通过115200波特率将照片回传给上位机）
-- require "prj_1_uart_camera"

------------------------------------ 加载应用项目主调度功能模块（每次从以上项目中选择一个来演示运行）-----------------------------------


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


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
