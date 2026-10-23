--[[
@module  main
@summary INDUS BOARD - Air8607 10 寸屏工业产线 / 设备看板
@version 1.0
@date    2026.10.23
@author  江访
@board   Air8607 + 10 寸 RGB 屏 1024x600（免序列）+ GT911 电容触摸
         引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
           背光 PWM3 (GPIO13)      触摸 I2C1 (400kHz) pin_rst = 14 pin_int = 51
@usage
本文件只做加载：
1、require "app_main" —— 应用主入口（硬件初始化 + 启动编排）
2、require "ui_main"  —— UI 主入口（界面模块加载与构建）
更多说明参考本目录下的readme.md文件
@boot
1、power_on()    —— 供电 / 背光 PWM3 占空比 0 / I2C 引脚配置（app/app_main.lua）
2、exd.setup()   —— 显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()  —— 分辨率 + hzfont 矢量字库 + 旋转
4、ui_main.build() —— 搭看板：顶栏 HUD + 不等分栏舞台 + 视图切换栏
5、touch_init()  —— GT911 初始化 + airui 绑定（必须早于动画任务）
6、ui_main.run() —— 30fps 主循环（默认进「产线总览」，自动轮播 8 秒一换）
7、backlight_on() —— 界面就绪后点亮背光，防花屏
@note
界面零图片素材：进度环、产能面积图、热力矩阵、储罐波浪全部由 airui.shape 图元实时计算，
数据来自 app/board_data.lua 产线模拟源，换真实采集无需改 UI。
hzfont 里没有中间点（·）等符号，界面文本只用 ASCII 与汉字。
]]
PROJECT = "indus_board"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)

-- 应用主入口（require 即执行：硬件初始化 + 启动编排）
require "app_main"
-- UI 主入口（require 即执行：界面模块加载）
require "ui_main"

sys.run()
