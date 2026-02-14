--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.07.13
@author  孟伟
@usage
本demo演示的功能为：
1、主要是演示四种errdump异常日志上报功能，使用的时候根据自己需求在下面选择要使用的功能，注意不能同时使用自动上报和手动读取功能
    （1）自动上报异常日志到iot平台
    （2）自动上报异常日志到自建udp服务器
    （3）手动读取异常日志并通过串口传输
    （4）手动读取异常日志并通过tcp传输
2、netdrv_device：配置连接外网使用的网卡，目前支持以下三种选择（三选一）
    （1） netdrv_4g：4G网卡
    （2） netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡
    （3） netdrv_multiple：支持以上三种网卡，可以配置三种网卡的优先级

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
PROJECT = "errdump_demo"
VERSION = "001.000.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)




-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)


-- 加载网络驱动设备功能模块
require "netdrv_device"

--下面三种情况只能打开一种，根据自己需求进行选择，不能同时打开，手动读取的errdump_read.lua中可以选择是通过串口传输还是通过tcp协议传输
-- 加载errdump测试模块
--自动上报异常日志到IOT平台
require "auto_dump_air_srv"

--自动上报异常日志到自建UDP平台
-- require "auto_dump_udp_srv"

--手动读取异常日志并通过串口和TCP传输
--加载手动读取异常日志模块
-- require "errdump_read"


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
