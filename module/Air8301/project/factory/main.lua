--[[
@module  main
@summary LuatOS用户应用脚本文件入口，总体调度应用逻辑（Air8301 出厂固件，产测+业务合一）
@version 2.0
@date    2026.09.24
@author  江访
@usage
本固件为 Air8301 出厂固件，采用「一套固件 + test_done 分流」模式（对齐 8780 出厂固件范式）：

  ┌──────────────────────────────────────────────────────────────┐
  │ 开机 → fskv.get("test_done")                                  │
  │        未完成产测 → 加载产测模块集（prod_test）                 │
  │        已完成产测 → 加载业务模块集（原有出厂业务）              │
  └──────────────────────────────────────────────────────────────┘

工位流程：产线先烧本固件 → 跑产测（USB虚拟串口指令 / 屏幕手测）
        → 发 TEST_DONE# 写 test_done → 重启后自动进入业务模式。

BOOT_MODE 调试开关（方便调试，出货保持 "auto"）：
  "auto"    按 test_done 自动分流（默认，出货值）
  "normal"  强制进入业务模式（无视 test_done，便于调试业务）
  "factory" 强制进入产测模式（无视 test_done，便于复测）

产测模式职责（prod_test.lua 主控）：
  1、基础信息指令（VERSION/IMEI/IMSI/ICCID/CSQ/MUID/VBAT/FLYMODE/ECNPICFG）
  2、写号（MODEL/HVERSION 写 OTP PROD/PCB）
  3、232 自回环（U232_TEST）、485 互发（U485_TEST）、网口 DHCP（ETH_TEST）
  4、看门狗（WD_TEST）、蜂鸣器（BUZZER_TEST）、继电器 DO（DO_TEST）
  5、Flash 写读（FLASH_TEST）、RELOAD 按键（RELOAD_TEST）
  6、系统控制（RST / TEST_DONE / PCBA_TEST_DONE）
  7、屏幕 12 项手动测试首页（prod_idle_win）

业务模式职责（原有出厂业务）：
  1、多网融合驱动：netdrv_device.lua → net_config.lua + net_drv.lua
     双 CH390H 网口（网口1=CS GPIO12/供电 GPIO32，网口2=CS GPIO5/供电 GPIO33）
     + 4G + WiFi + WiFi AP 热点
  2、485 继电器控制（主站）：comm_core.lua + relay_ctrl.lua
     UART11（RE/DE=GPIO153，9600 8N1），Modbus RTU 主站控制 4 路继电器模块
  3、Modbus 从站：
     - RTU从站：rtu_slave_regmap.lua（UART1，RE/DE=GPIO2，115200 8N1，接485串口板连电脑）
     - TCP从站：tcp_slave.lua（网口2，端口502）
  4、网口 TCP 主站：tcp_modbus_master.lua（读取建大仁科 RS-WS-ETH-6 温湿度）
  5、HTTP Web管理界面：httpsrv_web.lua（网口1端口80，PC浏览器访问 192.168.1.183）
  6、屏幕 UI：ui_main.lua（ST6201 4.3寸 480×272 + GT911 触摸 + AirUI/exwin）
  7、云端：aircloud_data.lua（AirCloud 上报 + 下行继电器控制命令 + 运维日志）
  8、定位：airlbs_app.lua（多基站+WiFi 定位）
  9、FOTA 远程升级：fota_app.lua + libfota3.lua
  10、硬件外设：di_app / do_app / buzzer_app / led_app / watchdog_app（Air153D）/ flash_app / reload_app
  11、网络看门狗：net_watchdog.lua

模式隔离（关键，避免资源抢占导致"产测过了业务不通"）：
  网络  产测 prod_network_app（双网口 DHCP）  业务 net_drv（静态 IP + 网页 + TCP从站）
  485   产测 prod_rs485_app（两口 115200 互发） 业务 rtu_slave_regmap + relay_ctrl
  232   产测 prod_rs232_app（TX-RX 自回环）     业务未使用
  RELOAD 产测 prod_reload_app（仅上报按键）     业务 reload_app（长按 5 秒恢复出厂）
  共享  board_init / di_app / do_app / buzzer_app / led_app / watchdog_app / flash_app
        以及 theme / lcd_st6201_43in / tp_gt911 / exair153x_wdt
]]


--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
VERSION：项目版本号，ascii string类型，使用合宙iot.openluat.com远程升级时必须按"XXX.YYY.ZZZ"三段格式定义
]]
PROJECT = "Air8301_Factory"
VERSION = "001.999.000"


-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)


-- ==================== 产测标记存储初始化（test_done 存于 fskv） ====================
fskv.init()


-- ==================== 启动模式选择 ====================
-- "auto"：按 test_done 自动分流（出货默认）；"normal"：强制业务；"factory"：强制产测
local BOOT_MODE = "auto"

local is_factory = false
if BOOT_MODE == "factory" then
    is_factory = true
elseif BOOT_MODE == "auto" then
    is_factory = not fskv.get("test_done")
end


-- ==================== 窗口管理器（固件内置扩展库，须在业务/UI模块之前加载） ====================
-- 必须显式 require 才会创建全局 exwin 表，各 UI 窗口模块均依赖此全局变量
exwin = require "exwin"


if is_factory then

    -- ==================== 产测模式 ====================
    -- prod_test 内部会 require prod_app_main（产测 app 集）与 prod_ui_main（产测 UI 集）
    log.info("main", "未完成产测，进入产测模式")
    require "prod_test"

else

    -- ==================== 业务模式 ====================
    log.info("main", "已完成产测，进入业务模式")

    -- 板级初始化
    require "board_init"

    -- 网络驱动设备功能模块
    require "netdrv_device"

    -- NTP 时间同步
    require "time_sync"

    -- 网络环境检测看门狗
    require "net_watchdog"

    -- 485 继电器主站（UART11）
    require "comm_core"
    require "relay_ctrl"

    -- Modbus 从站（UART1 + 网口2 TCP）
    require "rtu_slave_regmap"
    require "tcp_slave"

    -- 网口 TCP 主站（建大仁科温湿度）
    require "tcp_modbus_master"

    -- 硬件外设应用
    require "di_app"
    require "do_app"
    require "buzzer_app"
    require "led_app"
    require "watchdog_app"
    require "flash_app"
    require "reload_app"

    -- 业务编排层
    require "app_main"

    -- 内置网页（网口1 + WiFi AP）
    require "httpsrv_web"

    -- 云端上报与定位
    require "airlbs_app"
    require "aircloud_data"

    -- FOTA 远程升级
    require "fota_app"

    -- 屏幕 UI
    require "ui_main"

end


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
