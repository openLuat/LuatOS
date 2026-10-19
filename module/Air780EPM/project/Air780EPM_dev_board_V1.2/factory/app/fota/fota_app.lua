--[[
@module  fota_app
@summary FOTA 固件升级（基于 libfota3）
@version 1.0.0
@date    2026.10.19
@usage
本模块是 AirCloud/FOTA 服务与共享库 libfota3 之间的适配层。

升级全流程由 libfota3 内部完成（等待联网/时间同步 → 定时检测 → 下载 →
SHA256 校验 → 刷写 → 重启 → 开机版本比对上报），本模块只负责：
  1. 启动 request()（开机自动检测，默认 24 小时一次）
  2. 状态回调转发为 FOTA_STATUS 消息（UI 显示）
  3. 确认回调：本机无触摸屏，检测到新版本后自动下载、下载完成后自动重启

注意：PROJECT_KEY 未配置时跳过 FOTA，避免请求必然失败。
]]

local libfota3_ok, libfota3 = pcall(require, "libfota3")
if not libfota3_ok then
    log.warn("fota", "libfota3 加载失败", libfota3)
    libfota3 = nil
end

-- 自动检测间隔（秒），默认 24 小时
local AUTO_CHECK_INTERVAL = 86400

-- 状态回调：转成大写状态码发布给 UI，同时打日志
local function on_status(status, msg, percent)
    log.info("fota", status, msg, percent)
    sys.publish("FOTA_STATUS", status, msg, percent)
end

-- 确认回调：无触摸屏，一律自动确认
local function on_confirm(action, info, callback)
    if action == "download" then
        local ver = (type(info) == "table" and info.version) or ""
        log.info("fota", "发现新版本，自动下载", ver)
    elseif action == "reboot" then
        log.info("fota", "升级包已就绪，自动重启升级")
    end
    callback(true)
end

if libfota3 then
    if not PROJECT_KEY or PROJECT_KEY:find("TODO") then
        log.warn("fota", "PROJECT_KEY 未配置，FOTA 功能跳过")
    else
        libfota3.request({
            project_key    = PROJECT_KEY,
            script_name    = PROJECT,
            script_version = VERSION,
            auto           = true,
            interval       = AUTO_CHECK_INTERVAL,
            on_status      = on_status,
            on_confirm     = on_confirm,
        })
        log.info("fota", "FOTA 启动", libfota3.version(), "interval", AUTO_CHECK_INTERVAL)
    end
else
    log.warn("fota", "libfota3 不可用，FOTA 功能停用")
end

-- 手动触发检测（云端命令或调试使用）
sys.subscribe("FOTA_CHECK_NOW", function()
    if libfota3 then libfota3.check_update() end
end)

return true
