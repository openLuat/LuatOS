--[[
@module  main
@summary 农业大棚智能控制大屏主机（Air8607 10寸 1024x600）
@version 1.1
@date    2026.10.23
@author  江访
@board   Air8607 + 10寸 RGB屏 1024x600（免序列）+ GT911 电容触摸
         硬件引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
           背光 PWM3 (GPIO13)      触摸 I2C1 (400kHz) pin_rst = 14 pin_int = 51
@usage
本文件只做加载：
1、require "app_main" —— 应用主入口（硬件初始化 + 业务模块加载 + 启动编排）
2、require "ui_main"  —— UI 主入口（界面模块加载与构建）
更多说明参考本目录下的readme.md文件
@boot
1、power_on()   —— 供电/背光 PWM3 占空比 0/I2C 引脚配置（app_main.lua）
2、exd.setup()  —— 显示初始化（扩展库：复位 + RGB 时序 + 帧缓冲）
3、airui 初始化 —— init + 字体加载 + 旋转
4、ui_main.build()  —— 进入大屏 UI 界面（三列布局，见 ui/ui_dashboard.lua）
5、touch_init() —— GT911 触摸初始化 + airui 绑定（触摸可操作设备按钮）
6、backlight_on() 与定时刷新任务
]]
PROJECT = "agri_greenhouse"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)

-- 应用主入口（require 即执行：硬件初始化 + 业务模块加载 + 启动编排）
require "app_main"
-- UI 主入口（require 即执行：界面模块加载）
require "ui_main"

sys.run()
