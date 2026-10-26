--[[
@module  main
@summary 桌面时钟 / 日历 —— 工程入口（只做加载）
@author  王世豪
@version 1.0
@date    2026.10.26
@board   Air8607（Air1603）+ 10寸 RGB 1024x600 + GT911 电容触摸 + SPI1 TF 卡
@usage
本文件只做加载：require "app_main" —— 应用主入口（硬件初始化 + 启动编排）。
代码分类：
  app/  应用逻辑（app_main 启动编排、date_util 日历算法）
  drv/  硬件驱动（lcd 屏初始化、sd_card、rtc_util、settings 背光）
  ui/   界面（ui_main 聚合、theme 主题、ui_clock 时钟页、ui_settings 设置页、wallpaper 壁纸）
  conf.lua  板级与业务参数（根目录，全局唯一配置）
@boot
1、power_on()        —— 背光 PWM3 占空比 0 / LCD 供电 / SD_EN 上电 / 功放关断 / I2C1 轮询（app/app_main.lua）
2、exd.setup()       —— 显示初始化：复位 + RGB 时序 + 帧缓冲（drv/lcd/exd_air8607_rgb.lua）
3、airui 初始化      —— init + 旋转 + hzfont 中文字库（app/app_main.lua）
4、建根页面          —— 容器 + 渐变底色（app/app_main.lua → ui/theme.lua）
5、wallpaper.load()  —— 可选壁纸：挂载 SD + JPEG 校验 + 背景图层（ui/wallpaper.lua → drv/sd_card.lua）
6、ui_main.build()   —— 时钟页 + 设置页 + 页面切换回调（ui/ui_main.lua → ui/ui_clock.lua / ui/ui_settings.lua）
7、touch_init()      —— GT911 触摸 + airui 绑定（app/app_main.lua）
8、背光点亮          —— 应用持久化亮度（drv/settings.lua）
9、time_init()       —— RTC 基准年 + 时区（drv/rtc_util.lua）
10、timerLoopStart   —— 每秒 ui_main.refresh 刷新时钟（app/app_main.lua → ui/ui_clock.lua）
@note PC 分支
rtos.bsp() == "PC" 时跳过全部硬件初始化（GPIO/PWM/I2C/显示/触摸/SD），
只跑界面与日期算法，方便先在电脑上验证再烧真机。
]]
PROJECT = "wsh_desktop_clock"
VERSION = "001.000.001"
log.info("main", PROJECT, VERSION)

-- 应用主入口（require 即执行：硬件初始化 + 启动编排）
require "app_main"

sys.run()
