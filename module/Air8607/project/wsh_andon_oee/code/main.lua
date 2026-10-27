--[[
@module  main
@summary 产线 Andon 安灯 + OEE 生产看板 —— 工程入口（只做加载）
@author  王世豪
@version 1.0
@date    2026.10.26
@board   Air8607（Air1603）+ 10寸 RGB 1024x600 + GT911 电容触摸 + SPI1 TF 卡
@usage
本文件只做加载：require "app_main" —— 应用主入口（硬件初始化 + 启动编排）。
代码分类：
  app/  应用逻辑（app_main 启动编排、line_sim 虚拟产线、oee 统计计算）
  drv/  硬件驱动（lcd 屏初始化、sd_card、rtc_util）
  ui/   界面（ui_main 聚合、theme 主题、ui_board 看板）
  conf.lua  板级与业务参数（根目录，全局唯一配置）
@boot
1、power_on()        —— 背光 PWM3 占空比 0 / LCD 供电 / SD_EN / 功放关断 / I2C1 轮询（app/app_main.lua）
2、exd.setup()       —— 显示初始化（drv/lcd/exd_air8607_rgb.lua）
3、airui 初始化      —— init + 旋转 + hzfont 中文字库（app/app_main.lua）
4、line_sim.init()   —— 虚拟产线：8 工位状态机 + 产量/停机统计（app/line_sim.lua）
5、ui_main.build()   —— 看板：工位网格 + 异常面板 + 底部 OEE（ui/ui_board.lua）
6、touch_init()      —— GT911 触摸 + airui 绑定（app/app_main.lua）
7、背光点亮          —— PWM3 占空比 conf.backlight.duty（app/app_main.lua）
8、每秒刷新          —— line_sim.tick + ui_board.refresh（ui/ui_main.lua）
@note PC 分支
rtos.bsp() == "PC" 时跳过全部硬件初始化，虚拟产线照常运行，可在电脑上验证交互与统计。
]]
PROJECT = "andon_oee"
VERSION = "001.000.001"
log.info("main", PROJECT, VERSION)

-- 应用主入口（require 即执行：硬件初始化 + 启动编排）
require "app_main"

sys.run()
