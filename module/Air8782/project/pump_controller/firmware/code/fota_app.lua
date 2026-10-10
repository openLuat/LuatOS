--[[
@module  fota_app
@summary FOTA 远程升级（方式 C：libfota3 + 合宙升级服务器）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
依据 requirement.md 5.6（方式 C，触发逻辑 1+2）：
使用 libfota3 扩展库，在网络就绪后启动：
- 首次（开机）自动检测：libfota3 内部按“上次检测时间戳 + interval”计算，
  首次无记录时立即触发一次检测；
- 之后每隔 config_app.fota_interval(12 小时) 自动检测一次。
参考 demo module/Air780EPM/demo/fota/fota3(使用libfota3扩展库)/no_support_ui。
本模块无对外接口，直接 require "fota_app" 即加载运行。
]]

local libfota3   = require("libfota3")
local msg_bus    = require("msg_bus")
local config_app = require("config_app")

-- FOTA 状态回调
local function on_fota_status(status, msg, percent)
    log.info("fota_app", status, msg or "", percent or "")
end

-- FOTA 确认回调（无屏设备：默认确认下载与重启）
local function on_fota_confirm(action, info, callback)
    if action == "download" then
        log.info("fota_app", "确认下载升级包", info and info.version or "")
    elseif action == "reboot" then
        log.info("fota_app", "确认重启升级")
    end
    callback(true)
end

-- FOTA 任务：网络就绪后启动（interval 周期自动检测，首次立即检测）
local function fota_task()
    sys.waitUntil(msg_bus.NET_READY)
    log.info("fota_app", "网络就绪，启动 FOTA（间隔", config_app.fota_interval, "秒）")

    libfota3.request({
        project_key    = config_app.fota_project_key,
        script_name    = config_app.fota_script_name,
        script_version = _G.VERSION,
        auto           = true,
        interval       = config_app.fota_interval,
        on_status      = on_fota_status,
        on_confirm     = on_fota_confirm,
    })
end

sys.taskInit(fota_task)
