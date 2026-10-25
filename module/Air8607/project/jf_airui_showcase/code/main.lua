--[[
@module  main
@summary AirUI 视觉特效演示（Air8607 + 10寸 RGB 屏 1024x600 + GT911 触摸）
@version 1.1
@date    2026.10.23
@author  江访
@board   Air8607 + 10寸 RGB 屏 1024x600（免序列）+ GT911 电容触摸
         硬件引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
           背光 PWM3 (GPIO13)      触摸 I2C1 (400kHz) pin_rst = 14 pin_int = 51
@usage
本文件只做加载：
1、require "app_main" —— 应用主入口（硬件初始化 + 启动编排）
2、require "ui_main"  —— UI 主入口（界面模块加载与构建/动画接口）
更多说明参考本目录下的readme.md文件
@boot
1、power_on()      —— 供电/背光 PWM3 占空比 0/I2C 引脚配置（app_main.lua）
2、exd.setup()     —— 显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui 初始化    —— init + 字体加载 + 旋转
4、ui_main.build() —— 搭建演示界面（顶栏 HUD + 特效舞台 + 场景切换栏，见 ui/ui_showcase.lua）
5、touch_init()    —— GT911 触摸初始化 + airui 绑定（可点击切换场景）
6、ui_main.run()   —— 启动逐帧动画任务（约 30fps，shape:set_items 重绘舞台）
7、backlight_on()  —— 界面就绪后点亮背光，防花屏
@note
本演示全部视觉都由 airui.shape 的 line/circle/rect 图元实时计算生成，
不依赖任何图片资源；切换场景只隐藏/显示对应容器，不销毁对象。
]]
PROJECT = "airui_showcase"
VERSION = "1.0.0"

-- 应用主入口（require 即执行：硬件初始化 + 启动编排）
require "app_main"
-- UI 主入口（require 即执行：界面模块加载）
require "ui_main"

sys.run()
