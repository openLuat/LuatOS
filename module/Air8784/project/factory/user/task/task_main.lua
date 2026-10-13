--[[
@module  task_main
@summary Air8784 网页任务业务模式入口（来自 sip_aircloud_setting）
@version 1.0
@date    2026.09.30
@author  王世豪
@usage
本模块为业务模式（产测完成后）加载的统一入口，由 factory/main.lua 在
fskv 已有 test_done 时 require。
PROJECT/VERSION/PRODUCT_KEY/FOTA 由 factory/main.lua 统一管理（libfota3），
本模块不再定义；sys.run() 也由 factory/main.lua 统一调用，此处不调用。
按 fskv 中 sip_task_v1 任务类型选择启动分支：phone 为 SIP_CC，pair/round 为单 SIP。
只加载一套音频和通话模块，切换分支保存后重启；保存任务不会自动拨号。
]]
sys = require "sys"
sysplus = require "sysplus"
require "netdrv_4g"
local mode = require "task_runtime"
if mode.active == "single" then
    require "single_app"
else
    require "cc_app"
end
require "task_adapter"
require "task_keys"
