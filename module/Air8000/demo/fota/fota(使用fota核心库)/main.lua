--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.10.24
@author  孟伟
@usage
Air8000模块的两种FOTA升级方式：文件系统直接升级和串口分段升级；

分两种不同的应用场景来演示固件升级的实现方法:

1、文件系统直接升级：通过模组文件系统中的文件直接升级,代码演示通过luatools的烧录文件系统功能将升级包文件直接烧录到文件系统然后升级；

2、分段升级：通过串口将升级包文件分多个片段发送，每个片段接收并写入,代码演示使用usb虚拟串口分段写入升级包升级；

适用场景：
    - 非标准数据传输 -> 串口、TCP、MQTT等自定义通道升级

    - 流程精细控制 -> 需要自定义升级前后处理逻辑

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
PROJECT = "fota_test"
VERSION = "1.0.0" --不同于使用libfota2扩展库来升级必须是xxx.xxx.xxx的格式，这里可以自定义版本号格式。


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



-- 循环打印版本号, 方便看版本号变化, 非必须
function print_version()
    while 1 do
        sys.wait(1000)
        log.info("fota", "version", VERSION)
        -- log.info("fota1111122222222222")
    end
end
sys.taskInit(print_version)

-- 方式1: 文件系统直接升级
-- require("fota_file")

-- 方式2: 分段写入升级，以串口来分段写入升级包
require("fota_uart")

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
