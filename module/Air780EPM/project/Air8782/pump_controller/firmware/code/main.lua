--[[
@module  main
@summary 泵控制器（变频器远程监控终端）工程入口
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
本文件为工程唯一入口，职责如下：
1. 声明工程名称与版本号（PROJECT / VERSION）；
2. 通过 require 统一加载各功能模块（各模块内部自行通过 sys.taskInit 启动各自协程任务）；
3. 调用 sys.run() 启动 LuatOS 事件循环。

⚠️ 严格约束：main.lua 中【不得出现任何功能代码】，只允许
   PROJECT/VERSION 定义、log.info、errDump（注释）、内存监控（注释）、require 语句与 sys.run()。

被加载的模块与职责（18 个）：
    config_app        —— 全局业务配置（引脚/串口/周期/看门狗/AirCloud 参数）
    msg_bus           —— 消息总线主题常量
    netdrv_device     —— 网络驱动设备（内部按运行环境加载 netdrv_4g / netdrv_pc）
    sim_identity      —— 模拟器真机身份适配（PC 模拟器下以 4G 真机身份接入）
    modbus_map        —— 变频器寄存器采集字段表（15 条采集 + 控制帧）
    modbus_master     —— Modbus RTU 主站（485 供电使能 + 手动方向控制）
    state_norm        —— 字段规整（倍率换算 + 停机/故障置零）
    collect_task      —— 600ms 采集主任务
    excloud_app       —— AirCloud 服务核心（连接/鉴权/事件分发/运维日志）
    aircloud_report   —— 上行数据上报（TLV 封装 + 上报策略）
    device_info       —— 设备信息上报（ICCID/版本号/开机原因，每次开机首次鉴权后一次）
    aircloud_ctrl     —— 下行控制处理（Type=19/20）
    network_watchdog  —— 网络业务看门狗
    wdt_app           —— 硬件看门狗 Air153C（GPIO24）
    fota_app          —— FOTA 远程升级（方式C，开机一次 + 每 12 小时）
    oam_logger        —— 运维日志集中出口
    ntp_time          —— NTP 时间同步（供上报时间戳使用）

运行前提：
- 目标模组：Air8782P2 工业模组（基于 Air780EPM，4G Cat.1）
- 需随工程一并打包扩展库文件（excloud / exmtn / httpplus /
  exair153x_wdt / libfota3），详见 firmware/doc/开发说明.md
- 烧录前必须替换 config_app.fota_project_key 为真实项目 key
]]

-- =========================================================================
-- 工程信息
-- =========================================================================
PROJECT = "pump_controller"
VERSION = "001.999.000"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- =========================================================================
-- ⚠️ Air8782 系列（含 Air8782P2）：main.lua 中【不得出现内核 wdt 初始化代码块】
--    （公共流程6 强制：该系列不支持内核 wdt，硬件看门狗由 wdt_app 使用
--      exair153x_wdt 扩展库驱动）
-- =========================================================================

-- =========================================================================
-- errDump：记录并上传脚本运行期错误（强烈建议启用，默认注释）
-- =========================================================================
-- if errDump then
--     errDump.config(true, 600)
-- end

-- =========================================================================
-- 统一 require 加载所有功能模块
-- 各模块在自身文件内通过 sys.taskInit / sys.subscribe 启动逻辑，
-- 因此此处只需 require 加载即可，无需额外调用。
-- 加载顺序：配置 → 总线 → 网络驱动 → 设备间通信 → 业务 → AirCloud → 系统服务
-- =========================================================================
require("config_app")         -- 全局配置（无依赖，最先加载）
require("msg_bus")            -- 消息主题常量（无依赖）
require("netdrv_device")      -- 网络驱动设备（内部按运行环境加载 netdrv_4g / netdrv_pc）
require("sim_identity")       -- 模拟器真机身份适配（必须在 netdrv_device 之后加载）
require("modbus_map")         -- 采集字段表（纯数据）
require("modbus_master")      -- Modbus RTU 主站（依赖 config_app；手动 485 方向）
require("state_norm")         -- 字段规整（依赖 modbus_map）
require("collect_task")       -- 采集主任务（依赖 modbus_master / state_norm）
require("excloud_app")        -- AirCloud 服务核心（依赖 config_app / msg_bus）
require("aircloud_report")    -- 上报模块（依赖 excloud_app）
require("device_info")        -- 设备信息上报（依赖 excloud_app；每次开机首次鉴权后一次）
require("aircloud_ctrl")      -- 控制模块（依赖 modbus_master / excloud_app）
require("network_watchdog")   -- 网络业务看门狗
require("wdt_app")            -- 硬件看门狗 Air153C
require("fota_app")           -- FOTA 远程升级
require("oam_logger")         -- 运维日志集中出口
require("ntp_time")           -- NTP 时间同步

-- =========================================================================
-- 内存监控（调试期排查内存使用，默认注释）
-- =========================================================================
-- sys.timerLoopStart(function()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 30000)

-- =========================================================================
-- 启动 LuatOS 系统事件循环
-- sys.run() 会不断轮询底层消息并分发给各协程任务，程序不会返回。
-- =========================================================================
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
