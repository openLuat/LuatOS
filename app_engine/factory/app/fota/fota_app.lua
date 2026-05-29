--[[
@module  fota_app
@summary FOTA 固件升级管理模块（两步协议：检查→下载→上报）
@version 3.0
@date    2026.05.27
@author  江访
@usage
升级流程：
1. 手动检测：点击立即检测 → 显示新版本信息 → 确认下载 → 显示进度 → 完成弹窗"是否重启"
2. 定时检测：后台静默检查 → 有新版本弹窗提示 → 确认下载 → 下载完成弹窗"是否重启"
3. 重启前上报升级结果，开机补报上次未上报的结果

事件接口（与 settings_fota_win.lua 兼容）：
  订阅: FOTA_CHECK_NOW / FOTA_CHECK_AUTO / FOTA_CONFIRM_REBOOT / FOTA_GET_SETTINGS / FOTA_SAVE_SETTINGS
  发布: FOTA_STATUS / FOTA_PROMPT_REBOOT / FOTA_SETTINGS / FOTA_AUTO_PROMPT_UPGRADE
]]

-- ==================== 防御性加载 ====================

local libfota3_ok, libfota3 = pcall(require, "libfota3")
if not libfota3_ok then
    log.warn("fota_app", "libfota3 加载失败:", libfota3)
    libfota3 = nil
end

-- ==================== 局部变量 ====================

local network_ready = false
local auto_timer_id = nil
local fota_running = false
local fota_update_ready = false
local last_check_result = nil     -- 最近一次check结果（供下载使用）

-- fskv 键名
local KV_AUTO_CHECK  = "fota_auto_check"
local KV_INTERVAL    = "fota_interval"
local KV_FOTA_SN     = "fota_sn"           -- 待上报的升级序列号
local KV_FOTA_RESULT = "fota_result_code"  -- 待上报的结果码

-- ==================== 下载进度回调 ====================

local last_percent = -1

local function download_progress_cb(received, total)
    if total and total > 0 then
        local percent = math.floor(received * 100 / total)
        if percent ~= last_percent then
            last_percent = percent
            local msg = string.format("正在下载: %d%% (%d/%d KB)", percent, received // 1024, total // 1024)
            sys.publish("FOTA_STATUS", "DOWNLOAD_PROGRESS", msg, percent)
        end
    end
end

-- ==================== fskv 操作 ====================

local function fskv_get_safe(key, default)
    local ok, val = pcall(fskv.get, key)
    if ok and val ~= nil then return val end
    return default
end

local function fskv_set_safe(key, val)
    pcall(fskv.set, key, val)
end

local function get_settings()
    local auto = fskv_get_safe(KV_AUTO_CHECK, true)
    local interval = fskv_get_safe(KV_INTERVAL, 86400)
    return auto, interval
end

local function save_settings(auto, interval)
    interval = tonumber(interval) or 86400
    if interval <= 0 then interval = 86400 end
    fskv_set_safe(KV_AUTO_CHECK, auto)
    fskv_set_safe(KV_INTERVAL, interval)
end

-- ==================== FOTA 核心流程 ====================

-- 上报待处理的升级结果（开机补报）
local function report_pending_result()
    local fota_sn = fskv_get_safe(KV_FOTA_SN, "")
    local result_code = fskv_get_safe(KV_FOTA_RESULT, nil)
    if fota_sn == "" or result_code == nil then return end
    log.info("fota_app", "补报上次升级结果", "fota_sn", fota_sn, "code", result_code)
    if libfota3 then
        libfota3.report_result(fota_sn, tonumber(result_code) or 0)
    end
    fskv_set_safe(KV_FOTA_SN, "")
    fskv_set_safe(KV_FOTA_RESULT, nil)
end

-- 第一步：检查更新
local function do_check(is_manual)
    if not libfota3 then
        sys.publish("FOTA_STATUS", "CHECK_FAIL", "FOTA模块未加载", -1)
        fota_running = false
        return
    end
    sys.publish("FOTA_STATUS", "CHECKING", "正在检测更新...")

    local result, err = libfota3.check()
    if not result then
        sys.publish("FOTA_STATUS", "CHECK_FAIL", err or "检测失败", -1)
        fota_running = false
        return
    end

    if result.code and result.code ~= 0 then
        sys.publish("FOTA_STATUS", "NO_NEW_VERSION", result.msg or "当前已是最新版本")
        fota_running = false
        return
    end

    -- 有新版本
    last_check_result = result
    local msg = string.format("新版本 %s (%s)",
        result.script_version or "?",
        result.size and (math.floor(result.size / 1024) .. "KB") or "未知大小")
    sys.publish("FOTA_STATUS", "NEW_VERSION", msg)

    if is_manual then
        -- 手动检测：弹窗询问是否下载
        sys.publish("FOTA_PROMPT_DOWNLOAD", "检测到新版本 " .. (result.script_version or "") .. "，是否下载升级？")
    else
        -- 定时检测：弹窗提示
        sys.publish("FOTA_AUTO_PROMPT_UPGRADE", "检测到新版本 " .. (result.script_version or "") .. "，是否下载升级？")
    end
    fota_running = false
end

-- 第二步：下载并安装
local function do_download()
    if not last_check_result then
        sys.publish("FOTA_STATUS", "CHECK_FAIL", "请先检测更新", -1)
        return
    end
    if not libfota3 then
        sys.publish("FOTA_STATUS", "CHECK_FAIL", "FOTA模块未加载", -1)
        return
    end

    fota_running = true
    last_percent = -1
    local result = last_check_result

    sys.publish("FOTA_STATUS", "DOWNLOAD_START", "开始下载升级包...")

    local ok, err = libfota3.download(result.url, result.sha256, download_progress_cb)
    if not ok then
        log.error("fota_app", "下载失败:", err)
        sys.publish("FOTA_STATUS", "DOWNLOAD_FAIL", err or "下载失败")
        fota_running = false
        return
    end

    -- 下载+写入成功，保存fota_sn待重启后上报
    fota_update_ready = true
    fskv_set_safe(KV_FOTA_SN, result.fota_sn or "")
    fskv_set_safe(KV_FOTA_RESULT, "0")  -- 预填成功，如果重启后升级失败再改

    sys.publish("FOTA_STATUS", "DOWNLOAD_SUCCESS", "升级包已就绪，重启即可升级")
    sys.publish("FOTA_PROMPT_REBOOT", "升级包下载完成，是否重启设备进行升级？")
    fota_running = false
end

-- ==================== 流程入口 ====================

local function check_manual_task()
    if fota_running then return end
    fota_running = true
    do_check(true)
end

local function check_auto_task()
    if fota_running then return end
    fota_running = true
    do_check(false)
end

-- ==================== 定时器 ====================

local function auto_check_func()
    sys.publish("FOTA_CHECK_AUTO")
end

local function on_settings_changed(auto, interval)
    if auto_timer_id then
        sys.timerStop(auto_timer_id)
        auto_timer_id = nil
    end
    if auto and interval and interval > 0 then
        auto_timer_id = sys.timerLoopStart(auto_check_func, interval * 1000)
    end
end

-- ==================== 事件订阅 ====================

sys.subscribe("FOTA_CHECK_NOW", function()
    sys.taskInit(check_manual_task)
end)

sys.subscribe("FOTA_CHECK_AUTO", function()
    sys.taskInit(check_auto_task)
end)

-- 下载（用户确认有新版本后触发）
sys.subscribe("FOTA_DOWNLOAD_START", function()
    sys.taskInit(do_download)
end)

-- 用户确认重启
sys.subscribe("FOTA_CONFIRM_REBOOT", function()
    -- 上报升级结果（预填成功码，服务器记录设备已开始升级）
    local fota_sn = fskv_get_safe(KV_FOTA_SN, "")
    if fota_sn ~= "" and libfota3 then
        libfota3.report_result(fota_sn, 0)
    end
    sys.publish("FOTA_STATUS", "REBOOTING", "正在重启...")
    sys.timerStart(rtos.reboot, 500)
end)

-- 自动升级弹窗的"立即升级"按钮（兼容旧事件名）
sys.subscribe("FOTA_AUTO_PROMPT_UPGRADE", function(message)
    sys.taskInit(function()
        local mw, mh = 300, 180
        local msg_font = 14
        local lcd_w, lcd_h = lcd.getSize()
        if lcd_w and lcd_h then
            local d = math.min(lcd_w, lcd_h)
            mw = math.floor(d * 0.85)
            mh = math.floor(d * 0.35)
            msg_font = math.max(math.floor(d * 0.036), 14)
        end
        airui.msgbox({
            w = mw, h = mh,
            style = { text_font_size = msg_font },
            title = "固件更新",
            text = message or "检测到新版本，是否下载升级？",
            buttons = { "稍后", "立即升级" },
            on_action = function(self, btn_label)
                self:destroy()
                if btn_label == "立即升级" then
                    sys.publish("FOTA_DOWNLOAD_START")
                end
            end
        })
    end)
end)

-- 获取/保存设置
sys.subscribe("FOTA_GET_SETTINGS", function()
    local auto, interval = get_settings()
    sys.publish("FOTA_SETTINGS", auto, interval)
end)

sys.subscribe("FOTA_SAVE_SETTINGS", function(auto, interval)
    save_settings(auto, interval)
    on_settings_changed(auto, interval)
end)

-- ==================== 开机流程 ====================

sys.taskInit(function()
    log.info("fota_app", "FOTA模块启动")

    -- 先补报上次未上报的升级结果
    report_pending_result()

    local ip_ready = sys.waitUntil("IP_READY", 60000)
    if not ip_ready then
        log.warn("fota_app", "IP_READY超时")
    end
    network_ready = true

    local auto, interval = get_settings()
    if auto and interval > 0 then
        on_settings_changed(auto, interval)
    end

    if auto then
        sys.wait(3000)
        sys.publish("FOTA_CHECK_AUTO")
    end
end)
