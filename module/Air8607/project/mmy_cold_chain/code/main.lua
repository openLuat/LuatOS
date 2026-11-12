--[[
@module  main
@summary 冷链温控中枢 - 工程入口
@version 1.0
@date    2026.11.08
@board   Air8607 + 10 寸 1024x600 RGB 屏 + GT911 触摸

工程结构（单层 code/，与其他 Air8607 project 一致）：
  code/main.lua             入口
  code/app_main.lua         硬件初始化 + 启动编排
  code/cold_data.lua        冷链数据引擎（8 温区温度仿真 / 压缩机负载 / 事件流 / 24h 历史）
  code/theme.lua            设计令牌（配色/版式/字号/节拍/语音参数）
  code/fx.lua               绘图图元池（线/环/方块/折线/霓虹/雪花/配色混合）
  code/kit.lua              通用件（卡片/标题/文本节流/折线/面积/量条）
  code/dashboard.lua        主面板（温度曲线 / 温区矩阵 / 事件流 / KPI / 汇总 / 触摸）
  code/voice.lua            语音播报（TTS 三后端降级 + 右下角静音键）
  code/ui_main.lua          主循环 + 报警联动播报
  code/exd_air8607_rgb.lua  10 寸 RGB 屏显示 IC 初始化

接真实数据时只需要改 code/cold_data.lua 的取值来源
（Modbus 温湿度模块 / 冷库控制器 / MQTT 网关），ui 层不要动。
]]

PROJECT = "cold_chain"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

require "app_main"

sys.run()
