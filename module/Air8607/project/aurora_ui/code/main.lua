--[[
@module  main
@summary AURORA UI - Air8607 10 寸 RGB 1024x600 炫酷界面演示
@version 1.1
@date    2026.10.23
@author  江访
@board   Air8607 + 10 寸 RGB 屏 1024x600（免序列）+ GT911 电容触摸
         硬件引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
           背光 PWM3 (GPIO13)      触摸 I2C1 (400kHz) pin_rst = 14 pin_int = 51
@usage
本文件只做加载：
1、require "app_main" —— 应用主入口（硬件初始化 + 启动编排 + 动画任务）
2、require "ui_main"  —— UI 主入口（界面模块加载与构建）
更多说明参考本目录下的readme.md文件
@boot
1、power_on()      —— 供电 / 背光 PWM3 占空比 0 / I2C 引脚配置（app_main.lua）
2、exd.setup()     —— 显示初始化（复位 + RGB 时序 + 帧缓冲）（app_main.lua）
3、airui.init()    —— 分辨率 + 字体 + 旋转 + 性能统计（app_main.lua）
4、ui_main.build() —— 搭整屏：极光背景 + HUD + 舞台 + 4 个页面 + Dock（ui/ui_main.lua）
5、touch_init()    —— GT911 初始化 + airui 绑定，必须早于动画任务（app_main.lua）
6、ui_main.run()   —— 启动逐帧动画任务（33ms / 约 30fps）（ui/ui_main.lua）
7、backlight_on()  —— 界面就绪后点亮背光，防花屏（app_main.lua）

@note
本工程不使用任何图片素材：极光、3D 陀螺仪、频谱、星云、粒子全部由
airui.shape 的 line / circle / rect 图元每帧实时计算生成。
]]
PROJECT = "aurora_ui"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)

-- 应用主入口（require 即执行：硬件初始化 + 启动编排 + 动画任务）
require "app_main"
-- UI 主入口（require 即执行：界面模块加载）
require "ui_main"

sys.run()
