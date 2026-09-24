--[[
@module  prod_app_main
@summary 产测模式业务模块统一加载入口（只 require，不执行初始化）
@version 1.0
@date    2026.09.24
@usage
本模块只负责按顺序 require 产测模式各模块，各模块自身执行初始化：
- 含 sys.wait 的初始化 → 模块内部用 sys.taskInit 放协程执行
- 无 sys.wait 的初始化 → 模块内部用本地函数直接执行
- 有对外接口的模块保留对外接口，模块之间通过全局消息解耦

require 顺序说明：
- board_init 先执行：上电时序为后续模块提供供电
- prod_network_app 次之：发布 NETWORK_INIT_DONE，flash_app 依赖此消息才能挂载 Flash
- 其余模块相互独立，无强依赖

模式隔离说明（与业务模式的关键差异）：
- 网络：产测走 prod_network_app（双网口 DHCP），业务走 net_drv（静态 IP + 网页 + TCP从站）
- 485：产测走 prod_rs485_app（两口 115200 互发），业务走 rtu_slave_regmap + relay_ctrl
- 232：产测走 prod_rs232_app（自回环），业务未使用
- RELOAD：产测走 prod_reload_app（仅上报按键），业务走 reload_app（长按 5 秒恢复出厂）
- 共享：board_init / di_app / do_app / buzzer_app / led_app / watchdog_app / flash_app
]]

require "board_init"
require "prod_network_app"
require "prod_wifi_app"
require "prod_rs485_app"
require "prod_rs232_app"
require "di_app"
require "do_app"
require "buzzer_app"
require "led_app"
require "watchdog_app"
require "prod_reload_app"
require "flash_app"
