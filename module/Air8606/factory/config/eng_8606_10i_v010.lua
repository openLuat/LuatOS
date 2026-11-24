--[[
@module  config.eng_8606_10i_v010
@summary Air8606 引擎主机 10寸1024x600 RGB屏 配置文件（接口复用装配可切换）
@version 1.0
@date    2026.11.20
@author  江访
@usage
装配选择（SPI2 4G/WiFi、UART2 CAN/RS232、UART1 485、UART3、UART6 SIP/TTL、音频回放、USB Host）
由 air8606_mux 开机锁存：fskv 有存档用存档，否则用 board_options 默认（首启 WiFi），
「设置 → 接口复用」修改后重启生效。配置本体由 air8606_config.build 按装配生成。

PROJECT: "Engine_Air8606_10inch_1024x600_V010"
]]
local defaults = require "board_options"
local modes = require("air8606_mux").load(defaults.radio or "wifi", defaults)
return require("air8606_config").build(modes.radio, modes)
