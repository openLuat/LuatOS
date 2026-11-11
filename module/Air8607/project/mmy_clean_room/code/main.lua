--[[
@module  main
@summary 华康生物 无菌制剂车间 GMP 环境监控 - 工程入口
@version 1.0
@date    2026.11.11
@board   Air8607 + 10 寸 1024x600 RGB 屏 + GT911 电容触摸

工程结构（单层 code/，与其他 Air8607 project 一致）：
  code/main.lua             入口
  code/app_main.lua         硬件初始化 + 启动编排（背光/显示/字体/触摸/语音）
  code/room_data.lua        数据引擎（五间洁净区 / 压差梯度 / 粒子 / AHU / 事件流）
  code/theme.lua            设计令牌（配色 / 四条横带 / 字号 / 节拍 / 语音参数）
  code/fx.lua               绘图图元池（线 / 圆 / 环 / 弧 / 矩形 / 气流）
  code/kit.lua              通用件（玻璃卡 / 标题 / 文本节流 / 折线 / 量条）
  code/dashboard.lua        页面外壳（顶栏 / 页签 / 内容区 / 提示行 / 触摸分发）
  code/page_overview.lua    第 1 页 总览（KPI / 压差平面 / 待确认事件 / 今日概览）
  code/page_climate.lua     第 2 页 气候（监测点 / 24h 双道趋势 / 三张读数卡）
  code/page_air.lua         第 3 页 送风（AHU 参数 / 三级滤器 / 风路 / 能耗）
  code/page_alarms.lua      第 4 页 事件（完整事件表 / 筛选 / 统计 / 确认）
  code/voice.lua            语音播报（exaudio 后端 + 静音降级）
  code/ui_main.lua          主循环 + 报警联动播报
  code/exd_air8607_rgb.lua  10 寸 RGB 屏显示 IC 初始化

界面是四页：总览回答"哪一间正在失守"，气候回答"是刚掉还是一直在掉"，
送风回答"送风侧撑不撑得住"，事件回答"发生了什么、谁还没确认"。
四页开机各建一次，切页只 set_hidden，不销毁重建（见 dashboard.lua）。

场景：无菌制剂车间的 GMP 环境监控看板
  配液间 C 级 38m2 / 灌装间 A 级 42m2（背景 B 级）/ 压塞间 A 级 26m2
  更衣气闸 D 级 16m2 / 待检包装 D 级 54m2 / 洁净走廊 78m2
监控量：对走廊压差、温度、相对湿度、0.5um 与 5.0um 悬浮粒子、换气次数
控制量：运行模式（生产 / 值班 / 消毒）、AHU 送风频率、三级过滤器阻力

接真实数据时只需要改 code/room_data.lua 的取值来源
（Modbus 采集的压差变送器 / 温湿度传感器 / 粒子计数器 / AHU 变频器），
dashboard.lua 与四个 page_*.lua 一行都不用动。
]]

PROJECT = "clean_room"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

require "app_main"

sys.run()
