--[[
@module  ui_main
@summary UI页面模块统一加载入口（只 require，不执行初始化）
@version 2.0
@date    2026.08.04
@author  江访
@usage
本模块只负责按顺序 require 各窗口模块。窗口模块自身：
- 订阅 OPEN_XXX_WIN 消息并注册窗口
- 在窗口打开时订阅/取消订阅业务消息

LCD/TP 驱动初始化已在 main.lua 中 require 完成（lcd_st6201_43in / tp_gt911）。
]]

require "idle_win"
require "network_win"
require "wifi_win"
require "rs485_win"
require "rs232_win"
require "di_win"
require "do_win"
require "buzzer_win"
require "led_win"
require "watchdog_win"
require "reload_win"
require "flash_win"
require "sysinfo_win"
