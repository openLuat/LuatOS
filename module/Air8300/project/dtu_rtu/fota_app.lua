--[[
@module  fota_app
@summary FOTA 升级封装（libfota3 v2.0）
@version 2.0 / 2026.06.22
]]

local libfota3 = require("libfota3")
local M = {}

local g_stage = "idle"       -- idle/checking/new_version/downloading/download_done/error/rebooting
local g_msg = ""
local g_version = ""
local g_size = 0
local g_progress = 0
local g_history = {}
local g_auto = false
local g_interval = 86400

-- 加载升级历史
local function load_history()
    local raw = fskv.get("FOTA_HISTORY")
    if raw and #raw > 0 then
        local ok, t = pcall(json.decode, raw)
        if ok and type(t) == "table" then g_history = t end
    end
end
load_history()

local function save_history(ver, status)
    table.insert(g_history, 1, {time=os.date("%m-%d %H:%M"), ver=ver, status=status})
    if #g_history > 10 then g_history[#g_history] = nil end
    fskv.set("FOTA_HISTORY", json.encode(g_history))
end

-- 状态回调
local function on_status(status, msg, percent)
    log.info("fota", status, msg or "", percent or 0)
    if status == "checking" then
        g_stage = "checking"; g_msg = "检测中..."
    elseif status == "new_version" then
        g_stage = "new_version"; g_msg = msg or ""; g_version = msg or ""
    elseif status == "no_new_version" then
        g_stage = "idle"; g_msg = "已是最新版本"
    elseif status == "download_start" then
        g_stage = "downloading"; g_msg = "下载中"; g_progress = 0
    elseif status == "downloading" then
        g_progress = percent or 0
    elseif status == "download_done" then
        g_stage = "download_done"; g_msg = "下载完成, 请重启"; save_history(g_version, "成功")
    elseif status == "download_fail" then
        g_stage = "error"; g_msg = msg or "下载失败"; save_history(g_version, "失败:"..(msg or ""))
    elseif status == "check_fail" then
        g_stage = "error"; g_msg = msg or "检测失败"
    elseif status == "rebooting" then
        g_stage = "rebooting"; g_msg = "重启中..."
    end
end

-- 确认回调（自动确认，下载后自动重启）
local function on_confirm(action, info, callback)
    callback(true)
end

function M.start(auto, interval)
    g_auto = auto or false
    g_interval = interval or 86400
    libfota3.request({
        project_key = "iYxeZKfyaP6YGHczPWW4EYoH0HbTxtLz",
        script_name = "Air8300_DataCollector",
        script_version = VERSION or "001.999.000",
        auto = auto or false,
        interval = interval or 86400,
        on_status = on_status,
        on_confirm = on_confirm,
    })
end

function M.check() libfota3.check_update() end
function M.config(cfg)
    if cfg.auto ~= nil then g_auto = cfg.auto end
    if cfg.interval ~= nil then g_interval = cfg.interval end
    libfota3.config(cfg)
end

function M.get_config()
    return {auto = g_auto, interval = g_interval}
end

function M.get_status()
    return {
        stage = g_stage,
        msg = g_msg,
        version = g_version,
        progress = g_progress,
        history = g_history,
    }
end

-- 启动时加载（auto=false，手动模式）
M.start(false)

return M
