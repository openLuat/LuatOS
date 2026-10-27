--[[
@module  main
@summary 今天吃什么 - Air8607 10 寸屏三页转盘（减脂餐 / 家常菜 / 外卖）
@version 1.0.0
@date    2026.10.26
@board   Air8607(Air1603) + 10 寸 RGB 屏 1024x600（免序列）+ GT911 电容触摸
         引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17（低有效）
           背光 PWM3 (GPIO13)      触摸 I2C1 pin_rst = 14 pin_int = 51
@usage
本文件只做加载：
1、require "app_main" —— 应用主入口（硬件初始化 + 数据自检 + 启动编排）
2、sys.run()         —— 启动事件循环
详细说明见工程根目录的 readme.md

@note
整屏零图片素材：转盘、扇区、灯泡、卡片、页签全部由 airui.shape / container /
label 现场绘制。真机图片缓存只有 1MB，一张 500x500 的 RGBA 盘面就接近这个数，
所以没有用 image 控件（详见 ui/ui_theme.lua 顶部的设计说明）。
]]
_G.sys = require("sys")

PROJECT = "what_to_eat"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)

require "app_main"

sys.run()
