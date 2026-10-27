--[[
@module  main
@summary 智慧工业园区管理平台 · Air8607 10 寸屏 1024x600
@version 1.0
@date    2026.10.25
@author  江访
@board   Air8607 + 10 寸 RGB 屏 1024x600（免序列）+ GT911 电容触摸
         引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
           背光 PWM3 (GPIO13)      触摸 I2C1 (400kHz) pin_rst = 14 pin_int = 51
@usage
本文件只做加载：
1、require "app_main" —— 应用主入口（硬件初始化 + 启动编排）
2、require "ui_main"  —— UI 主入口（界面模块加载与构建）
更多说明参考本目录下的 README.md 文件
@boot
1、power_on()      供电 / 背光 PWM3 占空比 0 / I2C 引脚（app_main.lua）
2、exd.setup()     显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()    分辨率 + hzfont 矢量字库 + 旋转
4、ui_main.build() 搭大屏：顶栏 / 园区总览 / 能耗 / 园区平面图 / 三张服务卡 / 告警 / 安防
5、touch_init()    GT911 初始化（纯展示，失败不阻塞）
6、ui_main.run()   启动主循环（约 16fps，卡片与文本分节拍刷新）
7、backlight_on()  界面就绪后点亮背光，防花屏

@note
界面零图片素材：卡片、进度环、条形、园区平面图、告警点位全部由 airui.shape
的 arc / line / circle / rect 图元实时绘制。
性能上按"值班室大屏"来设计：静态层只画一次，每张卡的动态部分各自一个图层轮转刷新，
每帧真正重绘的只有地图上三个 44x44 的告警脉冲点位。
]]
PROJECT = "industrial_park"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)

require "app_main"
require "ui_main"

sys.run()
