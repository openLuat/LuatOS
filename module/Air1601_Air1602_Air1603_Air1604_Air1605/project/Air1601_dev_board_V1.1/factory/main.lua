--[[
@module  main
@summary Air1601 开发板 V1.1 默认出厂固件 主程序入口（配置驱动架构 · TabOS 界面 · display 底层初始化）
@version 1.0
@date    2026.10.21
@author  江访
]]

--[[
=== 系统启动流程 ===

main.lua 是整个工厂固件的唯一入口，负责串联所有初始化阶段：

  阶段0: 设置 PROJECT / VERSION / PROJECT_KEY（编译时确定）
  阶段1: require "platform_loader" → 平台检测 → 配置加载 → 引脚初始化 → _G.project_config 就绪
  阶段2: require "lcd_common" → 根据 project_config 构建 _G.lcd_drv / _G.tp_drv 全局驱动对象
  阶段3: require "boot_ui" → 快速点亮（display → airui.init → logo+背光），显示完成后
         加载 exwin/exapp、分批加载 app_main/ui_main 核心批与可选批，核心批完成直接进桌面
  阶段4: sys.run() → 启动事件循环，所有模块通过 publish/subscribe 解耦运行

=== 关键设计决策 ===

1. PROJECT 是唯一编译时变量：更换硬件只需改 PROJECT 字符串，其余全部由 platform_loader + 配置文件驱动
2. 快速点亮链路最先加载，重模块由 boot_ui 任务分批延迟加载：模块间依赖仍保持单向，
   「点亮屏幕」不再等几十个模块加载完，其余初始化与 logo 展示并行
3. 模块编译清单在 platform_loader 头部：编译系统文本扫描 require (...) 确定打包范围，
   清单包进永不调用的函数，运行时不执行（否则会提前加载到点亮屏幕前的关键路径）
4. exwin/exapp 是固件内置扩展库，由 boot_ui 在显示完成后加载（exapp require 时扫各存储应用）
]]

-- ==================== 编译时配置（更换硬件只需改这三行） ====================

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量，远程升级功能也会用到这两个变量
PROJECT：项目名，ascii string类型
=== PROJECT 对应关系 ===
已实现的配置（修改 PROJECT 为以下任一值即可切换硬件）：

  Air1601 开发板 V1.1:
  "EVB_Air1601_7inch_1024x600_000_V011"        → config/evb_1601_7i_v11.lua     7寸RGB JD9165BA(AirLCD_1070)+WiFi(airlink/6205)+以太网(CH390)+SD
  "PC"                                         → config/pc_default.lua          PC 模拟器（不读配置文件，内联配置）
  说明：本工程只保留 7 寸真机配置与 PC 模拟器回退，其余尺寸按需新增配置文件。

  说明：Air1601 的 Airlink WiFi 与 Airlink 4G 共用 UART3，V1.1 底板上两路模组不能同时工作；
  本工程已把以太网、WiFi、4G 三路都写入配置，实际以插入 UART3 的模组为准。

VERSION：项目版本号，ascii string类型
        如果使用合宙iot.openluat.com进行远程升级，必须按照"XXX.YYY.ZZZ"三段格式定义：
            X、Y、Z各表示1位数字，三个X表示的数字可以相同，也可以不同，同理三个Y和三个Z表示的数字也是可以相同，可以不同
            因为历史原因，YYY这三位数字必须存在，但是没有任何用处，可以一直写为000
        如果不使用合宙iot.openluat.com进行远程升级，根据自己项目的需求，自定义格式即可
]]
-- main.lua - 程序入口文件
PROJECT = "EVB_Air1601_7inch_1024x600_000_V011"       -- 默认机型：7寸 AirLCD_1070（JD9165BA）
VERSION = "001.999.000"                               -- 固件版本号，用于 FOTA 升级比对
PROJECT_KEY = "4AMuUDgSjjzZ3yNaQXmoYWHeUXjOYbV0"      -- 项目密钥：iot.openluat.com 项目的 FOTA/aircloud 鉴权密钥

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

-- ==================== 阶段2: LCD/TP 驱动对象构建 ====================
-- 根据 _G.project_config.hw.lcd / hw.tp 动态 require 对应驱动模块
-- 构建 _G.lcd_drv（含 hw_init/airui_init/airui_core_init/backlight_on）和 _G.tp_drv 全局接口
require "lcd_common"

-- ==================== 阶段3: 快速点亮 + 延迟初始化编排 ====================
-- 注：exwin/exapp（窗口管理 + 应用沙箱，固件内置扩展库）在 boot_ui 里、显示完成后才加载
-- require 即启动 boot 任务：display → airui.init → logo+背光 → 核心批 → 进桌面（可选批并行）
require "boot_ui"

-- ==================== 阶段4: 启动事件循环 ====================
-- sys.run() 是 LuatOS 的主循环，永不返回。所有业务逻辑通过事件驱动在协程中运行
sys.run()
