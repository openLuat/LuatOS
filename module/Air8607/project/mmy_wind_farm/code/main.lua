--[[
@module  main
@summary 北岭风电场集控中枢 - 工程入口
@version 1.0
@date    2026.11.09
@board   Air8607 + 10 寸 1024x600 RGB 屏 + GT911 触摸

工程结构（单层 code/，与其他 Air8607 project 一致）：
  code/main.lua             入口
  code/app_main.lua         硬件初始化 + 启动编排
  code/wind_data.lua        风电场数据引擎（12 台机组 / 尾流 / 功率曲线 / 限电 / 事件流）
  code/theme.lua            设计令牌（配色/版式/字号/节拍/语音参数）
  code/fx.lua               绘图图元池（线/环/弧/方块/折线/风机转子/风向瓣）
  code/kit.lua              通用件（卡片/标题/文本节流/折线/面积/量条）
  code/dashboard.lua        主面板（功率曲线 / 机组阵列 / 风向玫瑰 / 事件流 / KPI）
  code/voice.lua            语音播报（TTS 三后端降级 + 右下角静音键）
  code/ui_main.lua          主循环 + 报警联动播报
  code/exd_air8607_rgb.lua  10 寸 RGB 屏显示 IC 初始化

接真实数据时只需要改 code/wind_data.lua 的取值来源
（风机 SCADA / Modbus / IEC104 / MQTT 网关），ui 层不要动。
]]

PROJECT = "wind_farm"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

require "app_main"

sys.run()
