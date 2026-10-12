--[[
@module  app_main
@summary 业务模块统一加载入口（只 require，不执行初始化）
@version 2.0
@date    2026.08.04
@author  江访
@usage
本模块只负责按顺序 require 各业务模块，各模块自身执行初始化：
- 含 sys.wait 的初始化 → 模块内部用 sys.taskInit 放协程执行
- 无 sys.wait 的初始化 → 模块内部用本地函数直接执行
- 有对外接口的模块保留对外接口，模块之间通过全局消息解耦

require 顺序说明：
- board_init 先执行：上电时序为后续模块提供供电
- network_app 次之：发布 NETWORK_INIT_DONE，flash_app 依赖此消息才能挂载 Flash
- 其余模块相互独立，无强依赖
]]

require "board_init"
require "network_app"
require "wifi_app"
require "rs485_app"
require "rs232_app"
require "di_app"
require "do_app"
require "buzzer_app"
require "led_app"
require "watchdog_app"
require "reload_app"
require "flash_app"
