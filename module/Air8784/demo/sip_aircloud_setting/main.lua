--[[
@module main
@summary Air8784 单SIP与SIP_CC统一任务工程入口
@version 1.0
@date 2026.09.29
@usage
按fskv中sip_task_v1任务类型选择启动分支。phone为SIP_CC，pair/round为单SIP。
只加载一套音频和通话模块，切换分支保存后重启；保存任务不会自动拨号。
扩展库和核心库由script目录默认烧录，不在本工程重复提供。
]]
PROJECT = "AIR8784_SIP_AIRCLOUD_SETTING"
VERSION = "001.001.005"
-- 填写IoT平台用于FOTA升级的项目key（不是用户token或密码）。
PRODUCT_KEY = "gjv5xtttrhmCPjwSbfaNtjmIngXnFFN9"
FOTA_MODE = 2 -- 2: IoT/libfota2，3: 整机成品/libfota3
FOTA_INTERVAL = 24 * 3600 -- 秒
FOTA_URL = "" -- libfota2自建升级URL；空字符串使用官方IoT服务
sys = require "sys"
sysplus = require "sysplus"
log.info("main", PROJECT, VERSION)
require "netdrv_4g"
local mode = require "sip_runtime"
if mode.active == "single" then
    require "single_app"
else
    require "app_main"
end
local call_adapter = require "sip_task_adapter"
local update = require "update"
update.init(call_adapter)
require "sip_task_keys"
sys.run()
