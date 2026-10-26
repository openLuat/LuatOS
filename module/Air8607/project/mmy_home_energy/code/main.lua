--[[
@module  main
@summary 家庭能源监测面板 - 工程入口
@version 1.0
@date    2026.10.26
@board   Air8607 + 10 寸 1024x600 RGB 屏 + GT911 触摸

工程结构（单层 code/，与其他 Air8607 project 一致）：
  code/main.lua             入口
  code/app_main.lua         硬件初始化 + 启动编排
  code/energy_data.lua      能源数据引擎（光伏/负载/储能/电网 仿真与统计）
  code/theme.lua            设计令牌（配色/版式/字号/节拍）
  code/fx.lua               绘图图元池（线/环/弧/折线/缓动/配色）
  code/kit.lua              通用件（卡片/标题/文本节流/条形/面积）
  code/dashboard.lua        主面板（流向图/曲线/排行/KPI/汇总）
  code/voice.lua            语音播报（TTS 三后端降级 + 右下角静音键）
  code/ui_main.lua          主循环
  code/exd_air8607_rgb.lua  10 寸 RGB 屏显示 IC 初始化

接真实数据时只需要改 code/energy_data.lua 的取值来源（MQTT / Modbus 电表 / 逆变器 API），
ui 层不要动。
]]

PROJECT = "home_energy"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

require "app_main"

sys.run()
