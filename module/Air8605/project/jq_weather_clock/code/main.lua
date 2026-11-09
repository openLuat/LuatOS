--[[
@module  main
@summary 桌面天气时钟 —— 脚本入口
@version 1.0
@date    2026.11.08
@usage
PROJECT / VERSION 供 LuatTools 识别工程与 FOTA 比对，必须是顶层全局变量。
真正的初始化全部在 app/app_main.lua 里，本文件只负责把事件循环跑起来。
]]
PROJECT = "Air8605_WeatherClock"
VERSION = "1.0.0"

require "app_main"

sys.run()
