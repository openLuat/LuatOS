--[[
@module  main
@summary app_engine_factory 主程序入口（配置驱动架构）
@version 1.2
@date    2026.05.22
@author  江访
]]

--[[
=== 系统启动流程 ===

main.lua 是整个工厂固件的唯一入口，负责串联所有初始化阶段：

  阶段0: 设置 PROJECT / VERSION / PROJECT_KEY（编译时确定）
  阶段1: require "platform_loader" → 平台检测 → 配置加载 → 引脚初始化 → _G.project_config 就绪
  阶段2: require "exwin" / "exapp" → 窗口管理器 + 应用沙箱（LuatOS 固件内置扩展库）
  阶段3: require "lcd_common" → 根据 project_config 构建 _G.lcd_drv / _G.tp_drv 全局驱动对象
  阶段4: require "app_main" → 加载所有业务模块（网络/WiFi/NTP/FOTA/设置等），事件驱动自初始化
  阶段5: require "ui_main" → 加载所有 UI 页面模块，创建 init_ui_task 协程（LCD→TP→欢迎页→背光）
  阶段6: sys.run() → 启动事件循环，所有模块通过 publish/subscribe 解耦运行

=== 关键设计决策 ===

1. PROJECT 是唯一编译时变量：更换硬件只需改 PROJECT 字符串，其余全部由 platform_loader + 配置文件驱动
2. require 顺序即初始化顺序：Lua 单线程，require 同步执行，不会出现竞态
3. 模块编译清单在 platform_loader 头部：编译系统静态分析 pcall(require, ...) 确定打包范围
4. exwin/exapp 是固件内置扩展库，不在 factory 仓库中，由 LuatOS SDK 提供
]]

-- ==================== 编译时配置（更换硬件只需改这三行） ====================

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
=== PROJECT 对应关系 ===
已实现的配置（修改 PROJECT 为以下任一值即可切换硬件）：

  Engine 引擎主机系列:
  "Engine_Air8000W_4inch_320x480_000_V000"     → config/eng_8000w_4i_v0.lua     4寸SPI  ST7796  +4G+WiFi
  "Engine_Air1602_5inch_720x1280_002_V000"     → config/eng_1602_5i_v2.lua     5寸RGB  NV3052C +WiFi
  "Engine_Air1602_5inch_720x1280_003_V000"     → config/eng_1602_5i_v3.lua     5寸RGB  NV3052C +WiFi+NAND
  "Engine_Air1602_7inch_1024x600_000_V000"     → config/eng_1602_7i_v0.lua     7寸RGB  Custom  +WiFi
  "Engine_Air1602_10inch1_1024x600_001_V000"   → config/eng_1602_10i_v0.lua    10寸RGB Custom  +WiFi+蜂鸣器

  EVB turnkey 开发板系列:
  "EVB_Air8101_10inch1_1024x600_000_V010"      → config/evb_8101_10i_v1.lua    10寸RGB HX8282  +WiFi+SD
  "EVB_Air8101B_5inch_480x854_000_V010"         → config/evb_8101b_5i_v1.lua     5寸RGB  ST7701S +WiFi+SD

  待实现（映射已预留，配置文件待创建）:
  "EVB_Air1601_10inch1_1024x600_000_V011"      "EVB_Air1601_7inch_1024x600_000_V011"
  "EVB_Air1601_5inch_800x480_000_V011"         "EVB_Air8000A_3inch5_480x320_000_V020"
  "EVB_Air780EGG_3inch5_480x320_000_V014"      "EVB_Air780EHV_3inch5_480x320_000_V014"
  "EVB_Air780EHU_3inch5_480x320_000_V014"      "EVB_Air780EHM_3inch5_480x320_000_V014"
  "EVB_Air8101B_5inch_480x854_000_V010"        "EVB_Air8101_10inch1_1024x600_000_V010_b"
  Core 核心板系列:
  "Core_Air780EGG_3inch5_480x320_000_V020"     "Core_Air780EHU_3inch5_480x320_000_V020"
  "Core_Air780EHN_3inch5_480x320_000_V020"     "Core_Air8000A_3inch5_480x320_000_V040"
  "Core_Air8000W_3inch5_480x320_000_V040"      "Core_Air8000D_3inch5_480x320_000_V040"
  "Core_Air8000DB_3inch5_480x320_000_V040"     "Core_Air8000U_3inch5_480x320_000_V040"
  "Core_Air8000N_3inch5_480x320_000_V040"


VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
-- main.lua - 程序入口文件
PROJECT = "Engine_Air8000W_4inch_320x480_000_V000"  -- 项目命名，映射到 config/ 下的配置文件和硬件参数
VERSION = "001.999.006"                               -- 固件版本号，用于 FOTA 升级比对
PROJECT_KEY = "vMzSTFa5YG3GBMdqR5hxrKXClkwWPnZp"    -- 项目密钥，FOTA 云端鉴权

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- 设置日志输出风格为样式2（建议调试时开启）
-- log.style(2)


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

-- ==================== 阶段1: 平台检测 + 配置加载 + 引脚初始化 ====================
-- require 即执行：平台检测 → PROJECT 短名映射 → require 配置文件 → 设 _G.project_config → 配引脚
require "platform_loader"

-- ==================== 阶段2: 窗口管理 + 应用沙箱（固件内置扩展库） ====================
-- exwin: 窗口栈管理（open/close/焦点切换），所有 UI 页面的容器
-- exapp: 外部应用管理（扫描/安装/卸载/生命周期），运行从应用商店下载的 .exapp 应用
exwin = require "exwin"
exapp = require "exapp"

-- ==================== 阶段3: LCD/TP 驱动对象构建 ====================
-- 根据 _G.project_config.hw.lcd / hw.tp 动态 require 对应驱动模块
-- 构建 _G.lcd_drv（含 init/backlight_on）和 _G.tp_drv（含 init）全局接口
require "lcd_common"

-- ==================== 阶段4: 业务模块加载 ====================
-- 按顺序 require 各业务模块：net_init → wifi_app → status_provider → ntp → speedtest → iot → settings → fota
-- 每个模块 require 时自动订阅事件、启动定时器，互不阻塞
require "app_main"

-- ==================== 阶段5: UI 模块加载 + 启动 ====================
-- require 所有 UI 页面模块（注册窗口），然后 sys.taskInit 创建协程执行硬件初始化序列
require "ui_main"

-- ==================== 阶段6: 启动事件循环 ====================
-- sys.run() 是 LuatOS 的主循环，永不返回。所有业务逻辑通过事件驱动在协程中运行
sys.run()
