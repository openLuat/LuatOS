--[[
@module  main
@summary DIGITAL TWIN - Air8607 10 寸屏数字孪生车间大屏
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
更多说明参考本目录下的 readme.md
@note
视觉分三层：
  底图   res/scene_bg.png（AI 生成的 3D 车间渲染，1:1 贴，不缩放）
  全息层 ui/scene3d.lua 按透视相机实时算出来的地面网格 / 光柱 / 流光 / 热点环
  面板层 ui/bdui.lua 的玻璃卡 + 大字号读数（文字 5Hz 刷新）
hzfont 里没有中间点（·）、度数（°）等符号，界面文本只用 ASCII 与汉字。
]]
PROJECT = "digital_twin"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)

-- 应用主入口（require 即执行：硬件初始化 + 启动编排）
require "app_main"
-- UI 主入口（require 即执行：界面模块加载）
require "ui_main"

sys.run()
