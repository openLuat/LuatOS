--[[
@module  main
@summary UAV GCS - Air8607 10 寸屏无人机姿态与飞控地面站
@version 1.0
@date    2026.11.02
@board   Air8607 + 10 寸 RGB 屏 1024x600（免序列）+ GT911 电容触摸
         引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
           背光 PWM3 (GPIO13)      触摸 I2C1 (400kHz) pin_rst = 14 pin_int = 51
@usage
本文件只做加载：
1、require "app_main" —— 应用主入口（硬件初始化 + 启动编排）
2、require "ui_main"  —— UI 主入口（外壳构建与主循环）
更多说明参考本目录下的 README.md
@boot
1、power_on()      供电 / 背光 PWM3 占空比 0 / I2C 引脚（app_main.lua）
2、exd.setup()     显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()    分辨率 + 按字号逐个载入 hzfont
4、sim.init()      飞行仿真与遥测状态机就绪
5、ui_main.build() 搭界面：顶栏 / 五页 / 标签栏（ui/shell.lua）
6、touch_init()    GT911 初始化 + airui 绑定（必须早于动画任务）
7、ui_main.run()   启动 30fps 主循环
8、backlight_on()  界面就绪后点亮背光，防花屏
@note
全工程零图片素材：
  四旋翼机体、线框训练场、人工地平仪、罗盘、刻度带、曲线、图标
  全部由 airui.shape 的 line / rect / circle / arc / ellipse 图元实时绘制，
  机体姿态是真正的 3D 旋转 + 透视投影（ui/model3d.lua），不是贴图假转。
hzfont 里没有度数（°）、中间点（·）、正负号（±），所以界面文本只用 ASCII 与汉字。
]]
PROJECT = "uav_gcs"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)

-- 应用主入口（require 即执行：硬件初始化 + 启动编排）
require "app_main"
-- UI 主入口（require 即执行：加载外壳，等待 build/run 被调用）
require "ui_main"

sys.run()
