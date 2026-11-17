--[[
@module  main
@summary 充放电终端 —— Air8607 10寸 RGB 屏（1024x600）
@description
  主入口：main.lua 被固件执行后，通过 require "app_main" 完成
  硬件初始化、界面构建与主循环启动。
  ui/:   VoltAgent 翠绿信号风格界面（电量 / 功率 / 端口，充电时电池图内有气泡动画）
  app/:  主流程，供电与显示初始化
  drv/:  显示驱动（Air8607 10寸 RGB 免序列面板）
@author 充放电终端项目组
@time   2026-11-17
]]

PROJECT = "power_terminal"
VERSION = "1.0.0"

-- 加载自检进度界面与主流程
require "app_main"

-- 启动事件循环：LuatOS 必须显式调用，否则 main 返回后 VM 立即退出
--（表现为日志 E/main Lua VM exit!! reboot in 15000ms）
sys.run()
