--[[
@module update
@summary Air8784 IoT平台FOTA检查及通话空闲重启管理
@version 1.0
@date 2026.09.29
@usage
参考Air8202 factory/update.lua，采用libfota2供用户在IoT平台管理升级。
main.lua配置PRODUCT_KEY与三段式VERSION，init(adapter)在sys.run前调用。
联网后空闲检查一次，每24小时再次检查；check_update或FOTA_CHECK_REQ手动检查。
下载成功后等待通话和媒体连续空闲10秒再重启；不主动挂断通话。
依赖script/libs/libfota2.lua，不在本工程复制核心库/扩展库。
]]
local M = {}
local adapter, library
local mode, confirm_download = 2, nil
local initialized, online, pending, downloading, reboot_pending = false, false, false, false, false
local quiet_seconds, last_result = 0, nil
local function is_idle()
    local ok, value = pcall(adapter.idle)
    return ok and value == true
end
local function on_result(result)
    downloading = false; last_result = result
    log.info("update", "FOTA result", result)
    if result == 0 then
        reboot_pending = true; pending = false; quiet_seconds = 0
        log.info("update", "download complete; wait 10 idle seconds before reboot")
    else
        -- 4包含无可用升级、服务器拒绝和报文/下载失败，不能一概判断已是最新版本。
        log.warn("update", "check/download unsuccessful; inspect libfota2 log", result)
    end
    sys.publish("FOTA_CHECK_DONE", result)
end
local function on_status(status, message, percent)
    last_result = status
    log.info("update", "libfota3", status, message, percent)
    if status == "downloading" then downloading = true end
    if status == "check_fail" or status == "download_fail" or status == "no_new_version" then
        downloading = false
        sys.publish("FOTA_CHECK_DONE", status)
    end
end
local function on_confirm(action, info, callback)
    if action == "download" then
        confirm_download = callback; quiet_seconds = 0
    elseif action == "reboot" then
        -- libfota3默认500ms后重启；禁止其自动重启，统一交给本模块空闲检查。
        callback(false)
        on_result(0)
    else callback(false) end
end
function M.check_update()
    if not initialized then return false end
    if downloading or reboot_pending or confirm_download then return false end
    pending = true
    return true
end
local function on_ip_ready()
    online = true
end
local function on_ip_lose()
    online = false; quiet_seconds = 0
end
local function on_tick()
    if not is_idle() then quiet_seconds = 0; return end
    quiet_seconds = quiet_seconds + 1
    if quiet_seconds < 10 then return end
    if confirm_download then
        if not online then return end
        local callback = confirm_download; confirm_download = nil
        downloading = true; callback(true); return
    end
    if reboot_pending then
        -- No yielding between the last idle check and reboot.
        log.info("update", "idle confirmed; reboot to apply FOTA")
        rtos.reboot()
        return
    end
    if not pending or downloading or not online then return end
    pending = false; downloading = true
    log.info("update", "check", PROJECT, VERSION)
    -- libfota2会修改opts，每次请求必须使用新的表。
    local ok, err
    if mode == 3 then
        downloading = false -- 库内部控制检查互斥；状态回调标记下载阶段。
        ok, err = pcall(library.check_update)
    else
        local options = {project_key=PRODUCT_KEY, timeout=300000}
        if type(_G.FOTA_URL) == "string" and _G.FOTA_URL ~= "" then
            options.url = _G.FOTA_URL; options.url_done = true
        end
        ok, err = pcall(library.request, on_result, options)
    end
    if not ok then
        downloading = false; last_result = "request_error"
        log.error("update", "request failed", tostring(err))
        sys.publish("FOTA_CHECK_DONE", last_result)
    end
end
function M.status()
    return {mode=mode, enabled=initialized, online=online, pending=pending,
        downloading=downloading, reboot_pending=reboot_pending, last_result=last_result}
end
function M.init(call_adapter)
    if initialized then return true end
    log.info("update", "current version", _G.PROJECT, _G.VERSION)
    if type(_G.PRODUCT_KEY) ~= "string" or not _G.PRODUCT_KEY:match("%S") then
        log.warn("update", "PRODUCT_KEY missing; FOTA disabled")
        return false
    end
    if type(_G.VERSION) ~= "string" or not _G.VERSION:match("^%d%d%d%.%d%d%d%.%d%d%d$") then
        log.error("update", "VERSION must use xxx.yyy.zzz")
        return false
    end
    if type(call_adapter) ~= "table" or type(call_adapter.idle) ~= "function" or not rtos or type(rtos.reboot) ~= "function" then
        log.error("update", "missing call idle check or reboot API")
        return false
    end
    mode = _G.FOTA_MODE or 2
    if mode ~= 2 and mode ~= 3 then log.error("update", "FOTA_MODE must be 2 or 3"); return false end
    local interval = _G.FOTA_INTERVAL or 86400
    if type(interval) ~= "number" or interval < 60 or interval > 604800 then
        log.error("update", "FOTA_INTERVAL must be 60..604800 seconds"); return false
    end
    local ok, value = pcall(require, mode == 3 and "libfota3" or "libfota2")
    if not ok or type(value) ~= "table" or (mode == 2 and type(value.request) ~= "function") or (ok and mode == 3 and (type(value.config) ~= "function" or type(value.check_update) ~= "function")) then
        log.error("update", "FOTA library unavailable; include script libraries when flashing")
        return false
    end
    adapter = call_adapter; library = value
    if mode == 3 then
        library.config({project_key=PRODUCT_KEY, script_name=PROJECT, script_version=VERSION,
            auto=false, interval=interval, on_status=on_status, on_confirm=on_confirm})
    end
    initialized = true; pending = true
    sys.subscribe("IP_READY", on_ip_ready)
    sys.subscribe("IP_LOSE", on_ip_lose)
    sys.subscribe("FOTA_CHECK_REQ", M.check_update)
    sys.timerLoopStart(on_tick, 1000)
    sys.timerLoopStart(M.check_update, interval * 1000)
    return true
end
return M
