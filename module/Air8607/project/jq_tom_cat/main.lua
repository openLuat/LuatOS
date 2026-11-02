--[[
@module  main
@summary 汤姆猫 TOM CAT - Air8607 10 寸屏触摸互动 UI（零图片 / 零音频素材）
@version 1.1
@date    2026.10.25
@author  蒋骞
@board   Air8607 + 10 寸 RGB 屏 1024x600（免序列）+ GT911 电容触摸 + 板载 DAC/HT6873 功放
@usage
本文件只做加载：
1、require "app_main" —— 硬件初始化 + 启动编排（app/app_main.lua）
2、require "ui_main"  —— 界面装配 + 交互 + 主循环（ui/ui_main.lua）
玩法：点猫身上不同位置，两只前爪扑过去捂住那里，并说一句中文
（头顶"谢谢主人" / 耳朵"耳朵好痒" / 眼睛"别戳眼睛" / 口鼻"主人你好" /
  肚子"肚子好舒服" / 前爪"手也摸摸" / 后脚"脚脚怕痒" / 尾巴"别拽尾巴"）。
@note
猫的每一根线条都由 airui.shape 图元程序化绘制，工程内没有任何 png/jpg/mp3；
台词走固件本地 TTS（app/voice.lua -> exaudio.play_start type=1），不联网。
详细说明见本目录 README.md。
]]
PROJECT = "tom_cat"
VERSION = "1.1.0"
log.info("main", PROJECT, VERSION)

require "app_main"
require "ui_main"

sys.run()
