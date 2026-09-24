--[[
@module  main
@summary 触摸显示位置偏移测试入口，初始化显示/触摸/AirUI后进入测试界面
@version 2.0
@date    2026.09.22
@author  江访
@usage
本demo演示的核心功能为：
1、开机显示坐标网格，按像素刻度标注屏幕坐标，直观展示屏幕尺寸
2、触摸屏幕任意位置，用AirUI在触摸点画十字标记并打印触摸坐标，
   将十字标记位置与网格刻度对比，即可判断显示与触摸之间是否存在偏移
3、点击屏幕右下角"清屏"按钮，清除所有触摸标记，方便重新测试
本工程只保留显示、触摸、AirUI初始化功能，不包含网络、音频等其他业务；
供电时序、引脚配置、显示初始化方式（display 底层初始化）与
factory_new 工厂工程完全一致，支持 factory_new 中所有已实现型号，
更换硬件只需修改下方 PROJECT 字符串
更多说明参考本目录下的readme.md文件
]]

-- ==================== 编译时配置（更换硬件只改 PROJECT 一行） ====================

--[[
必须定义PROJECT和VERSION变量，Luatools工具会用到这两个变量
PROJECT：项目名，ascii string类型
=== 支持的 PROJECT 列表（与 factory_new 工厂工程一致，≥800×480 / 480×854） ===

  Engine 引擎主机系列:
  "Engine_Air1602_5inch_720x1280_002_V000"      5寸RGB  NV3052C 720x1280
  "Engine_Air1602_5inch_720x1280_003_V000"      5寸RGB  NV3052C 720x1280
  "Engine_Air1602_5inch_480x854_005_V000"       5寸RGB  ST7701S 480x854
  "Engine_Air1602_7inch_1024x600_000_V000"      7寸RGB  HX8282  1024x600
  "Engine_Air1602_7inch_1024x600_004_V000"      7寸RGB  HX8282  1024x600
  "Engine_Air1602_10inch1_1024x600_001_V000"    10寸RGB HX8282  1024x600
  "Engine_Air1602_AirLCD_1090_09421_V000"      9寸RGB  HX8282  1024x600
  "Engine_Air1602_AirLCD_1100_10421_V000"      10寸RGB HX8282  1024x600
  "Engine_Air8601_7inch_1024x600_010_V000"      7寸RGB  HX8282  1024x600
  "Engine_Air8602_9inch_1024x600_010_V000"      9寸RGB  HX8282  1024x600

  EVB turnkey 开发板系列:
  "EVB_Air8101_AirLCD_1020_000_V020"            5寸RGB  H050IWV 800x480
  "EVB_Air8101_AirLCD_1070_000_V020"            7寸RGB  HX8282  1024x600
  "EVB_Air8101_AirLCD_1090_000_V020"            9寸RGB  HX8282  1024x600
  "EVB_Air8101_AirLCD_1100_000_V020"            10寸RGB HX8282  1024x600
  "EVB_Air8101B_5inch_480x854_000_V010"         5寸RGB  ST7701S 480x854
  "EVB_Air8101B_5inch_480x854_000_V020"         5寸RGB  GC9503  480x854
  "EVB_Air1601_5inch_800x480_000_V011"          5寸RGB  800x480
  "EVB_Air1601_7inch_1024x600_000_V011"         7寸RGB  HX8282  1024x600
  "EVB_Air1601_7inch_1024x600_000_V012"         7寸RGB  HX8282  1024x600
  "EVB_Air1601_10inch1_1024x600_000_V011"       10寸RGB HX8282  1024x600

VERSION：项目版本号，ascii string类型
]]
PROJECT = "Engine_Air1602_5inch_480x854_005_V000"  -- 项目命名，映射到 config/ 下的配置文件和硬件参数
VERSION = "1.0.0"                                    -- 固件版本号

-- 在日志中打印项目名和项目版本号
log.info("main", PROJECT, VERSION)

-- ==================== 阶段1: 平台检测 + 配置加载 + 供电/引脚初始化 ====================
-- require 即执行：平台检测 → PROJECT 短名映射 → require 配置文件 → 设 _G.project_config → 配引脚 → 上电时序
require "platform_loader"

-- ==================== 阶段2: LCD/TP 驱动对象构建（含 AirUI 初始化封装） ====================
-- 根据 _G.project_config.hw.lcd / hw.tp 动态 require 对应驱动模块
-- RGB 屏统一走 lcd_display_rgb（内部 display.init 完成 IC 寄存器 + RGB 时序 + FrameBuffer）
-- 构建 _G.lcd_drv（含 init/backlight_on）和 _G.tp_drv（含 init）全局接口
require "lcd_common"

-- ==================== 阶段3: 测试界面模块加载 ====================
-- 注册触摸测试界面（坐标网格 + 触摸十字标记 + 清屏按钮），init 调用时才创建 UI
local touch_test_win = require "touch_test_win"

-- ==================== 硬件初始化协程（LCD → TP → 测试界面 → 背光） ====================

--[[
硬件初始化协程函数，按显示、触摸、界面、背光的顺序初始化：
1、lcd_drv.init：display 底层初始化 LCD（IC 寄存器 + RGB 时序 + FrameBuffer），
   成功后自动初始化 AirUI（分辨率、字体、旋转、密度）
2、tp_drv.init：初始化GT911触摸芯片（自动继承 LCD 分辨率做触摸尺寸兜底），并绑定到AirUI
3、touch_test_win.init：创建坐标网格测试界面，订阅触摸回调，开始接收触摸点
4、sys.wait(100)：等待界面渲染进 FrameBuffer，避免背光提前点亮看到白屏
5、lcd_drv.backlight_on：打开背光，进入测试流程

@param 无
@return 无（协程函数，内部使用 sys.wait）
]]
local function init_ui_task_func()
    -- 步骤1: LCD 初始化（display 底层初始化 + AirUI 初始化、字体加载、密度缩放计算）
    lcd_drv.init()

    -- 步骤2: TP 触摸初始化（GT911 驱动 + AirUI 触摸绑定）
    tp_drv.init()

    -- 步骤3: 创建触摸显示偏移测试界面
    touch_test_win.init()

    -- 步骤4: 等待界面渲染完成（避免背光提前亮导致白屏）
    sys.wait(100)

    -- 步骤5: 打开背光
    lcd_drv.backlight_on()
end

-- 创建协程执行硬件初始化，不阻塞 sys.run() 事件循环启动
sys.taskInit(init_ui_task_func)

-- ==================== 启动事件循环 ====================
-- sys.run() 是 LuatOS 的主循环，永不返回。触摸回调、按钮点击都在事件循环中被处理
sys.run()
