--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑
@version 1.0
@date    2025.07.17
@author  拓毅恒
@usage
演示功能概述
1.1 蓝牙配网是什么
蓝牙配网是一种利用蓝牙低功耗（BLE）链路，在未联网设备与手机之间建立本地安全通道，把 Wi-Fi 的 SSID、密码及其他网络参数传递给设备，使其独立完成 STA 或 SOFTAP 联网的技术方案。
1.3 蓝牙配网原理
设备在上电后进入配网模式，作为 BLE Peripheral 持续广播自定义的配网服务 UUID；手机 APP 作为 Central 扫描并建立 GATT 连接，随后通过加密特征值把网络参数下发给设备。设备收到参数后，启用 Wi-Fi 并执行联网流程。
1.4 蓝牙配网流程：
1) 广播
设备以固定间隔广播配网服务，等待手机连接。
2) 连接
手机 APP 扫描 → 选择目标设备 → 建立 BLE 连接。
3) 选择配网方式
在 APP 界面选择：
station 模式：设备直接作为 Station 连接路由器。
softap 模式：设备通过 4G 开 AP 热点，用于其他设备连接（由于Air8101本身内部没有4G，所以暂时不支持配置AP功能）。

蓝牙配网就是让Air8101工作在蓝牙配网模式下，手机app通过蓝牙连接Air8101,通过app内界面实现配网功能。

本示例基于合宙 Air8101 模组，演示 “STA + SoftAP 双模式 BLE 配网” 的完整流程。手机通过 BLE 下发 Wi-Fi 账号/密码或热点参数，模组自动完成 STA 连接或 SoftAP 创建，并验证网络可用性。

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
PROJECT = "BLE_CONIFG_WIFI"
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

-- 加载espblufi应用功能模块
local espblufi = require("espblufi")

-- 加载dnsproxy应用功能模块
dnsproxy = require("dnsproxy")

-- 加载dhcp应用功能模块
dhcpsrv = require("dhcpsrv")

-- 加载 ble_config_wifi 主应用功能模块
require "ble_config_wifi"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
