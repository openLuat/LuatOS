--[[
@module  main
@summary BEAT FORGE - Air8607 10 寸屏可演奏鼓机 / 步进音序器
@version 1.1
@date    2026.10.23
@author  江访
@board   Air8607 + 10 寸 RGB 屏 1024x600（免序列）+ GT911 电容触摸
         引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
           背光 PWM3 (GPIO13)      触摸 I2C1 (400kHz) pin_rst = 14 pin_int = 51
           喇叭 DAC + HT6873 功放（AUDIOPA_EN = GPIO73，exaudio 里配置）
@usage
本文件只做加载：
1、require "app_main" —— 应用主入口（硬件初始化 + 启动编排）
2、require "ui_main"  —— UI 主入口（界面模块加载与构建）
更多说明参考本目录下的readme.md文件
@boot
1、power_on()    —— 供电 / 背光 PWM3 占空比 0 / I2C 引脚配置（app/app_main.lua）
2、exd.setup()   —— 显示初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()  —— 分辨率 + hzfont 矢量字库 + 旋转
4、engine.boot() —— 合成 8 种鼓声 + 启动混音任务（拿不到 exaudio 自动静音降级）
5、ui_main.build() —— 搭界面：网格 / 反应堆 / 示波器 / 控制条
6、touch_init()  —— GT911 初始化 + airui 绑定（必须早于动画任务）
7、ui_main.run() —— 30fps 主循环（图案默认开播，theme.audio.auto_play 可关）
8、backlight_on() —— 界面就绪后点亮背光，防花屏
@note
界面零图片素材、声音零音频素材：鼓声是 synth.lua 现场合成的 PCM，
刻度 / 波形 / 电平柱全部由 airui.shape 图元实时绘制。
hzfont 里没有中间点（·）等符号，界面文本只用 ASCII 与汉字。
]]
PROJECT = "beat_forge"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)

-- 应用主入口（require 即执行：硬件初始化 + 启动编排）
require "app_main"
-- UI 主入口（require 即执行：界面模块加载）
require "ui_main"

sys.run()
