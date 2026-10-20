--[[
@module  fota_app
@summary FOTA 升级封装（libfota3）
@version 1.0
@date    2026.10.20

说明：
1. project_key 只服务于 FOTA（libfota3 的接口认证参数），AirCloud 的自动认证与本文件无关；
2. 未配置 project_key 时不启动自动检测，避免无效请求；
3. 升级历史存 fskv，Web 页面可查；
4. 下载完成默认自动重启（无屏设备没有"确认"交互）。
]]

local app_config = require "app_config"
local libfota3 = require "libfota3"
local storage = require "storage"

local M = {}

local st = {
    stage = "idle",
    msg = "",
    version = "",
    progress = 0,
    history = {},
}

local function save_history(ver, status)
    table.insert(st.history, 1, {
        time = os.date("%m-%d %H:%M"),
        ver = ver or "?",
        status = status,
    })
    while #st.history > 10 do st.history[#st.history] = nil end
    pcall(fskv.set, "FOTA_HISTORY", st.history)
end

local function load_history()
    local t = fskv.get("FOTA_HISTORY")
    if type(t) == "table" then st.history = t end
end
load_history()

local function on_status(status, msg, percent)
    log.info("fota", status, msg or "", percent or 0)
    storage.log("fota", tostring(status) .. " " .. tostring(msg or ""))
    if status == "checking" then
        st.stage, st.msg = "checking", "检测中"
    elseif status == "new_version" then
        st.stage, st.msg, st.version = "new_version", msg or "", msg or ""
    elseif status == "no_new_version" then
        st.stage, st.msg = "idle", "已是最新版本"
    elseif status == "download_start" then
        st.stage, st.msg, st.progress = "downloading", "下载中", 0
    elseif status == "downloading" then
        st.progress = percent or 0
    elseif status == "download_done" then
        st.stage, st.msg = "download_done", "下载完成，准备重启"
        save_history(st.version, "成功")
    elseif status == "download_fail" then
        st.stage, st.msg = "error", msg or "下载失败"
        save_history(st.version, "失败:" .. (msg or ""))
    elseif status == "check_fail" then
        st.stage, st.msg = "error", msg or "检测失败"
    elseif status == "rebooting" then
        st.stage, st.msg = "rebooting", "重启中"
    elseif status == "upgrade_success" then
        st.stage, st.msg = "success", "升级成功"
    elseif status == "upgrade_fail" then
        st.stage, st.msg = "error", "升级失败"
    end
end

-- 无屏设备：下载与重启都自动确认
local function on_confirm(action, info, callback)
    callback(true)
end

local started = false

function M.start()
    local c = app_config.load()
    if not c.project_key or #tostring(c.project_key) == 0 then
        log.warn("fota", "未配置 project_key，跳过 FOTA 自动检测")
        return
    end
    if started then return end
    started = true
    libfota3.request({
        project_key = c.project_key,
        script_name = PROJECT,
        script_version = VERSION,
        auto = c.fota_auto ~= false,
        interval = c.fota_interval or 86400,
        on_status = on_status,
        on_confirm = on_confirm,
    })
    storage.log("fota", "FOTA 已启动 auto=" .. tostring(c.fota_auto))
end

-- 手动检测（Web 页面）
function M.check()
    if not started then M.start() end
    if not started then
        return false, "未配置 project_key"
    end
    libfota3.check_update()
    return true
end

function M.get_status()
    return st
end

return M
