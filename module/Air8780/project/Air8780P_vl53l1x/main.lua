--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2026.07.23
@author  江访
@usage
本demo演示Air8780P工业模组+VL53L1X激光测距传感器的低功耗数据采集与上报流程：
1、VL53L1X激光测距传感器数据采集
2、通过合宙iot平台(excloud)和MQTT上报传感器数据
3、支持libfota2远程升级
4、PSM+低功耗模式

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
-- main.lua - 程序入口文件
PROJECT = "Air8780P_VL53L1X"
VERSION = "001.999.000"
PRODUCT_KEY = "PhbD7kCQg9Jt7vwCGgtdjQ6jIscQ2gJJ"  -- 用于合宙IOT平台FOTA升级，此处仅为示例，实际使用请修改为自己的PRODUCT_KEY

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息，可以初步分析一些设备运行异常的问题
-- 以下代码是最基本的用法，更复杂的用法可以详细阅读API说明文档
-- 启动errDump日志存储并且上传功能，600秒上传一次
if errDump then
    errDump.config(true, 600)
end


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


-- 加载网络驱动设备功能模块（4G网卡）
require "netdrv_device"

-- 加载VL53L1X项目编排模块
-- 该模块会级联加载：
--   drv/drv_led — 驱动层：LED控制（事件驱动）
--   drv/drv_psm — 驱动层：PSM+模式（事件驱动）
--   sensor/sensor_vl53l1x — 应用层：传感器驱动
--   cloud/aircloud — 应用层：云平台上报
--   fota/fota_mgr — 应用层：FOTA升级管理
require "prj_vl53l1x"


-- 用户代码已结束
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
