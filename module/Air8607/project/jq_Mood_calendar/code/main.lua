--[[
@module  main
@summary 情绪日历 —— 工程入口（只做加载）
@author  蒋骞
@version 1.0
@date    2026.10.30
@board   Air8607（Air1603）+ 10寸 RGB 1024x600 + GT911 电容触摸 + SPI1 TF 卡
@usage
本文件只做加载：require "app_main" —— 应用主入口（硬件初始化 + 启动编排）。
代码分类：
  app/  应用逻辑（app_main 启动编排、date_util 日历算法、mood_stat 统计与祝福语）
  drv/  硬件驱动（lcd 屏初始化、sd_card、rtc_util、backlight 背光、mood_store 心情存取）
  ui/   界面（ui_main 聚合、theme 主题、ui_calendar 日历页、ui_picker 心情选择、ui_report 月度报告）
  conf.lua  板级与业务参数（根目录，全局唯一配置）
@boot
1、power_on()        —— 背光 PWM3 占空比 0 / LCD 供电 / SD_EN 上电 / 功放关断 / I2C1 轮询
2、exd.setup()       —— 显示初始化：复位 + RGB 时序 + 帧缓冲
3、airui 初始化      —— init + 旋转 + hzfont 中文字库
4、建根页面          —— 容器 + 奶油色渐变底色
5、ui_main.build()   —— 日历页 + 心情选择浮层 + 月度报告浮层
6、touch_init()      —— GT911 触摸 + airui 绑定
7、背光点亮          —— 界面就绪后再点亮，防花屏
8、time_init()       —— RTC 基准年 + 时区
9、timerLoopStart    —— 每秒检查是否跨天
@note PC 分支
rtos.bsp() == "PC" 时跳过全部硬件初始化（GPIO/PWM/I2C/显示/触摸/SD），
只跑界面与日期算法，方便先在电脑上验证再烧真机。
]]
PROJECT = "mood_calendar"
VERSION = "001.000.000"
log.info("main", PROJECT, VERSION)

-- 应用主入口（require 即执行：硬件初始化 + 启动编排）
require "app_main"

sys.run()
