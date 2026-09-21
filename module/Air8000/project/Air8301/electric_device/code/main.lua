--[[
@module  main
@summary 智控电场发生器系统通讯控制板（Air8301）主程序入口
@version 1.0
@date    2026.09.18
@author  嵌入式软件设计开发代理
@usage
本工程由 Air8000A 版本（智控电场发生器系统通讯控制板）移植而来，运行于 Air8301 硬件板
（基于 Air8000W 主控，4G + WiFi + 4.3寸 480x272 ST6201 SPI 屏 + GT911 触摸）。

移植说明：
1、业务代码（uart_app / aircloud_app / protocol_app / business_app / fota_app /
   network_watchdog / ntp_app / 各 UI 窗口）原样复用，逻辑不变；
2、硬件相关部分替换为 Air8301 板级驱动：
   - board_init.lua  板级上电时序（参考 hardware_test/app/board_init.lua）
   - lcd_drv.lua     ST6201 4.3寸 480x272 SPI 屏驱动（参考 hardware_test/drv/lcd）
   - tp_drv.lua      GT911 触摸驱动（参考 hardware_test/drv/tp）
   - netdrv_*.lua    4G/WiFi 双网卡驱动（沿用 Air8000 系列通用实现）

通过 require 语句加载各功能模块运行。
]]

-- 必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
-- PROJECT：项目名，ascii string类型
-- VERSION：项目版本号，ascii string类型（XXX.YYY.ZZZ 三段格式，YYY 三位数字必须存在，可一直写 000）

-- 项目名称和版本定义
PROJECT = "LuatOS_ELECTRIC_DEVICE"  -- 项目名称，用于标识当前工程（作为 FOTA script_name 上报）
VERSION = "001.999.000"    -- 项目版本号（FOTA 升级版本对比使用）
-- FOTA 项目密钥（在 https://iot.openluat.com 创建项目后获取）
-- ⚠️ 说明：PROJECT_KEY 仅与 FOTA 升级功能相关，与 AirCloud 功能无关
-- ⚠️ 必填：请在下方填入您的 FOTA 项目 key，否则 FOTA 升级不可用
PROJECT_KEY = "IsuAC8YuntlvT430sixFK6jn15EfdmPM"

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 初始化 fskv 键值存储（用于持久化设定电压等参数，必须在读取前调用）
fskv.init()

-- 设置日志输出风格为样式2（建议调试时开启）
-- log.style(2)

-- 如果内核固件支持errDump功能，此处进行配置，【强烈建议打开此处的注释】
-- if errDump then
--     errDump.config(true, 600)
-- end

-- 使用LuatOS开发的任何一个项目，都强烈建议使用远程升级FOTA功能
-- 本项目使用 libfota3 库，fota_app.lua 中调用（libfota3 由扩展库提供）

-- 1. 板级上电时序（Air8301：引脚复用 + 各外设供电 + 安全默认态）
require "board_init"

-- 2. 网络驱动（4G + WiFi 双网卡，WiFi 优先，由 netdrv_device 统一加载）
require "netdrv_device"

-- 3. 硬件驱动（LCD 屏幕、触摸）
lcd_drv = require "lcd_drv"
tp_drv = require "tp_drv"

-- 4. UI 框架
exwin = require "exwin"

-- 5. 通信驱动（串口、云连接）
require "uart_app"
require "aircloud_app"

-- 6. 协议处理
require "protocol_app"

-- 7. 业务逻辑
require "business_app"

-- 8. 系统服务（FOTA、网络看门狗、NTP 时间同步）
require "fota_app"
require "network_watchdog"
require "ntp_app"

-- 9. 基站定位（airlbs 扩展库：获取经纬度，随状态上报一起上传）
-- ⚠️ AirLBS 为合宙收费服务，需联系合宙销售申请；未填写时自动跳过定位（不影响其他业务）
AIRLBS_PROJECT_ID = "JMuNkC"    -- TODO: 填入合宙 AirLBS 项目 ID（6 位，联系销售获取）
AIRLBS_PROJECT_KEY = "QLwrDEPUahWh01nPfgc2N6zHp751ldWf"   -- TODO: 填入合宙 AirLBS 项目密钥（联系销售获取）
require "lbs_app"

-- 10. UI 主模块
require "ui_main"

-- 用户代码已结束
-- 结尾总是这一句
sys.run()
-- sys.run()之后不要加任何语句!!!!!因为添加的任何语句都不会被执行
