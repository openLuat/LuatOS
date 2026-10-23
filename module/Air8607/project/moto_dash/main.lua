--[[
@module  main
@summary MOTO DASH - Air8607 10 寸屏两轮车仪表盘
@version 1.1
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
1、power_on()      供电 / 背光 PWM3 占空比 0 / I2C 引脚（app_main.lua）
2、exd.setup()     显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()    分辨率 + hzfont 矢量字库 + 旋转
4、ui_main.build() 搭仪表盘：速度表 / 四张卡 / 顶栏 / 模式键（ui/cluster.lua）
5、touch_init()    GT911 初始化 + airui 绑定（必须早于动画任务）
6、ui_main.run()   启动 30fps 主循环（先跑自检扫针，再进入骑行态）
7、backlight_on()  界面就绪后点亮背光，防花屏

@note
界面主体是 airui.shape 图元：指针、进度弧、刻度、电池条、折线全部由
line / circle / rect 实时绘制（精确、可算、可随车速插值）。
另有 3 张程序生成的素材负责"质感与发光"，见 ui/eff.lua：
  bg_weave.png 碳纤维底纹 / fx_glow.png 手指光晕 / fx_scan.png 扫描光带
hzfont 里没有中间点（·）和度数（°），所以界面文本只用 ASCII 与汉字，
温度写成 "42 C"、单位写成 "km/h"。
]]
PROJECT = "moto_dash"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)

-- 应用主入口（require 即执行：硬件初始化 + 启动编排）
require "app_main"
-- UI 主入口（require 即执行：界面模块加载）
require "ui_main"

sys.run()
