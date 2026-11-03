--[[
@module  main
@summary 益智乐园 - Air8607 七款益智小游戏 + 成绩排行榜（1024x600 横屏触摸）
@version 1.1
@date    2026.11.03
@board   Air8607 + 10 寸 RGB 屏 1024x600（免序列）+ GT911 电容触摸
         硬件引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
           背光 PWM3 (GPIO13)      触摸 I2C1 (400kHz) pin_rst = 14 pin_int = 51
@usage
本文件只做加载：
1、require "app_main" —— 应用主入口（硬件初始化 + 启动编排）
2、require "ui_main"  —— UI 主入口（界面模块加载与构建/主循环接口）
@boot
1、power_on()      供电 / 背光 PWM3 占空比 0 / I2C 引脚配置
2、exd.setup()     显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()    分辨率 + hzfont 矢量字库 + 旋转
4、ui_main.build() 搭大厅：顶栏 HUD + 舞台 + 底部操作栏 + 通用弹窗
5、touch_init()    GT911 初始化 + airui 绑定（必须早于动画任务）
6、ui_main.run()   30fps 主循环（页面绘制 + 触摸手势分发 + HUD 节流刷新）
7、backlight_on()  界面就绪后点亮背光，防上电花屏
@note
界面零图片素材：所有画面由 airui.shape 的 line / circle / rect / arc 图元实时计算。
脚本按裸文件名 require，下载到设备时需全部平铺到同一个目录。
]]

PROJECT = "puzzle_arcade"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)

-- 应用主入口（require 即执行：硬件初始化 + 启动编排）
require "app_main"
-- UI 主入口（require 即执行：界面模块加载）
require "ui_main"

sys.run()
