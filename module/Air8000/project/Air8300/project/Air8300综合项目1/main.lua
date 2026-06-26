--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑 
@version 1.0
@date    2026.05.12
@author  朱天华
@usage
本demo演示的核心功能为：
1、配置连接外网使用的网卡（netdrv_device），支持以下模式（多选一）：
    (1) netdrv_4g：4G网卡
    (2) netdrv_wifi：WIFI STA网卡
    (3) netdrv_eth_spi：通过SPI外挂CH390H芯片的以太网卡
    (4) netdrv_multiple：支持以上三种网卡，可配置优先级
    (5) netdrv_pc：PC模拟器网卡
    (6) netif_app_1：4G提供网络供wifi和以太网设备上网
    (7) netif_app_2：以太网提供网络供wifi和以太网设备上网
    (8) netif_app_3：wifi提供网络供wifi和以太网设备上网
2、AirCloud数据上报：aircloud_data.lua 定时上报设备数据到AirCloud平台
3、airlbs定位：airlbs_app.lua 通过多基站+多wifi定位获取设备经纬度
4、modbus功能：
    - RTU从站：rtu_slave_regmap.lua（寄存器映射表，同时提供从站功能）
    - RTU主站：temp_hum_sensor.lua（读取RS485温湿度传感器）
    - TCP从站：tcp_slave.lua
    - TCP主站：tcp_modbus_master.lua（读取网口1温湿度传感器）
5、LED状态指示：led.lua（绿=传感器更新, 红=主站请求）
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
PROJECT = "SOCKET_LONG_CONNECTION"
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


-- 网络驱动设备功能模块
require "netdrv_device"


-- 开启以太网wan（使用静态 IP 地址）
-- 注意：当使用以太网静态ip地址时，netdrv_device 文件下相关以太网的配置都不能使用，否则会有干扰
require "netdrv_eth_static"


-- airlbs 定位（多基站+多wifi定位）
require "airlbs_app"

-- AirCloud 数据上报
require "aircloud_data"


-- RTU从站：寄存器映射表 + 从站响应
require "rtu_slave_regmap"

-- TCP Modbus从站
require "tcp_slave"

-- RTU Modbus温湿度传感器主站
require "temp_hum_sensor"

-- TCP Modbus 主站
require "tcp_modbus_master"

-- LED 状态指示
require "led"


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
