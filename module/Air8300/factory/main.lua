--[[
@module  main
@summary LuatOS 用户应用脚本文件入口，总体调度应用逻辑
@version 1.1
@date    2026.09.18
@usage
本demo演示的核心功能为：
1、多网融合驱动：net_config.lua + net_drv.lua
   使用 exnetif.set_priority_order 同时管理 WiFi + 双以太网 + 4G，支持运行时动态切网
2、AirCloud 数据上报：aircloud_data.lua 定时上报设备数据到 AirCloud 平台
3、airlbs 定位：airlbs_app.lua 每 15 分钟通过基站+WiFi 定位获取设备经纬度
4、modbus 功能：
   - 温湿度采集：temp_sensor.lua（非隔离口 UART3，从站1，读温湿度变送器）
   - 继电器控制：relay_ctrl.lua（隔离口 UART1，从站1，控制 4 路继电器模块/风扇/LED，通道0~3）
5、FOTA 远程升级：fota_app.lua（libfota3，开机网络就绪+每12小时）
6、网络业务看门狗：net_watchdog.lua（监控网络业务，异常自动恢复）
]]

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义
]]

-- 项目名（工程内英文标识）
PROJECT = "Air8300_EdgeGateway"
-- 项目版本号（三段式，用于远程升级）
VERSION = "001.999.001"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- 因为此功能模块可以记录并且上传脚本在运行过程中出现的语法错误或者其他自定义的错误信息
-- 启动errDump日志存储并且上传功能，600秒上传一次
-- 【V1.1 修改】放开该配置：脚本级语法错误/自定义错误可被记录并上报，是线上排障的必备手段
if errDump then
    errDump.config(true, 600)
end

-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 远程升级的详细用法，可以参考fota的demo进行使用

-- 启动一个循环定时器
-- 每隔3秒钟打印一次总内存，实时的已使用内存，历史最高的已使用内存情况
-- 方便分析内存使用是否有异常
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)

-- 网络配置管理
require "net_config"

-- NTP 时间同步
require "time_sync"

-- 多网融合驱动（以太网/WiFi/4G）
require "net_drv"

-- Modbus RTU 公共封装
require "comm_core"

-- 温湿度采集（非隔离口 UART3）
require "temp_sensor"

-- 继电器控制（隔离口 UART1）
require "relay_ctrl"

-- 网络业务看门狗
require "net_watchdog"

-- airlbs 基站定位（15分钟一次）
require "airlbs_app"

-- AirCloud 数据上报/命令处理
require "aircloud_data"

-- FOTA 远程升级
require "fota_app"

-- 业务编排
require "app_main"

-- 进入主循环
sys.run()
