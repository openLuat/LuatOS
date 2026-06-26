--[[
@module  fota_app
@summary FOTA 远程升级封装（libfota3 两步协议）
@version 1.0 / 2026.06.12
]]

local libfota3 = require("libfota3")
local M = {}

local g_status = "idle"       -- idle / checking / new_version / downloading / download_done / error
local g_msg = ""
local g_new_version = ""
local g_progress = 0
local g_fota_sn = nil
local g_download_url = nil
local g_sha256 = nil

function M.check()
    g_status = "checking"
    g_msg = "正在检查更新..."
    log.info("fota", "开始检查更新")
    local result, err = libfota3.check({
        project_key = "47J0PYMJzOCXwjXQ0bpqhXkoq9KMgDgi",
    })
    if not result then
        g_status = "error"
        g_msg = "检查失败: " .. tostring(err or "网络错误")
        return false
    end
    if result.code == 0 then
        g_status = "new_version"
        g_new_version = result.script_version or "?"
        g_fota_sn = result.fota_sn
        g_download_url = result.url
        g_sha256 = result.sha256
        g_msg = "发现新版本: " .. g_new_version .. ", " .. (result.size or 0) .. "字节"
        log.info("fota", g_msg)
        return true
    else
        g_status = "idle"
        g_msg = result.msg or "已是最新版本"
        return false
    end
end

function M.download()
    if not g_download_url then return false, "请先检查更新" end
    g_status = "downloading"
    g_progress = 0
    log.info("fota", "开始下载", g_download_url)
    local ok, err = libfota3.download(g_download_url, g_sha256, function(rx, total)
        g_progress = total > 0 and math.floor(rx * 100 / total) or 0
    end)
    if ok then
        g_status = "download_done"
        g_msg = "下载完成，请重启模组"
        log.info("fota", "下载完成")
        return true
    else
        g_status = "error"
        g_msg = "下载失败: " .. tostring(err or "未知")
        return false, err
    end
end

function M.reboot()
    log.info("fota", "用户触发重启")
    sys.wait(500)
    rtos.reboot()
end

function M.get_status()
    return {
        status = g_status,
        msg = g_msg,
        new_version = g_new_version,
        progress = g_progress,
        fota_sn = g_fota_sn,
    }
end

return M
