--[[
@module  update
@summary libfota3 远程升级业务入口
@usage
init(options) 配置上游 libfota3，每 8 小时自动检测；check_update() 请求手动检查。
需要 main.lua 配置 PRODUCT_KEY，并在合宙 IoT 平台配置升级包。
下载及重启确认通过 idle 钩子检查忙状态；activity 钩子供低功耗管理使用。
检查请求成功不代表升级完成，最终结果以 fota 日志和重启版本为准。
]]

-- Business integration only; libfota3 is loaded unchanged from upstream.
local libfota3 = require "libfota3"
local M = {}
local initialized, requested = false, false
local hooks = {}
local terminal = {check_fail=true,no_new_version=true,download_fail=true,
    upgrade_success=true,upgrade_fail=true,network_fail=true}
function M.init(options)
    if initialized then return true end
    if type(PRODUCT_KEY) ~= "string" or PRODUCT_KEY == "" then
        log.warn("fota", "not_configured")
        return false, "fota_not_configured"
    end
    hooks = options or {}
    initialized = true
    libfota3.request({project_key=PRODUCT_KEY,script_name=PROJECT,script_version=VERSION,
        auto=true,interval=28800,
        on_status=function(status,msg,percent)
            log.info("fota",status,msg,percent)
            if hooks.activity then hooks.activity(not terminal[status] and status~="boot_report") end
        end,
        on_confirm=function(action,info,callback)
            local ok = not hooks.idle or hooks.idle()
            if not ok then
                log.warn("fota","deferred_busy",action)
                if hooks.activity then hooks.activity(false) end
            end
            callback(ok == true)
        end})
    return true
end
function M.check_update()
    if not initialized then return false,"fota_not_configured" end
    if hooks.idle and not hooks.idle() then return false,"device_busy" end
    if requested then return true end
    requested=true
    -- Allow the cloud command handler to enqueue its receipt first.
    sys.timerStart(function()
        requested=false
        if hooks.idle and not hooks.idle() then
            log.warn("fota","deferred_busy","check")
            return
        end
        libfota3.check_update()
    end,1000)
    return true
end
return M
