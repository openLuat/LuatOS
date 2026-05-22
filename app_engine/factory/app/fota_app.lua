--[[
@module  fota_app
@summary FOTA 固件升级管理模块
@version 2.0
@date    2026.05.20
@author  江访
@usage
升级流程：
1. 手动检测：点击立即检测 → 显示下载进度 → 下载完成弹窗"是否重启升级"
2. 定时检测：后台静默下载 → 下载完成后提示有更新，重启可升级
3. 用户点击确认重启 → 执行 rtos.reboot()

注意：libfota2 一次性完成检测+下载+安装（fota.file），
      完成后只需重启即可激活新固件。不再自动重启。
]]

-- ==================== 防御性加载 ====================

local libfota2_ok, libfota2 = pcall(require, "libfota2")
if not libfota2_ok then
    log.warn("fota_app", "libfota2 加载失败:", libfota2)
    libfota2 = nil
end

-- ==================== 局部变量 ====================

local network_ready = false
local auto_timer_id = nil
local fota_running = false         -- 升级操作进行中标志（防重入）
local fota_update_ready = false    -- 是否有已下载完成的升级包（重启可激活）
local boot_check_done = false

-- fskv 键名
local KV_AUTO_CHECK  = "fota_auto_check"
local KV_INTERVAL    = "fota_interval"

-- ==================== FOTA 进度回调 ====================

local last_percent = -1

local function fota_progress_cb(total_len, received_len, userdata)
    if total_len and total_len > 0 then
        local percent = math.floor(received_len * 100 / total_len)
        if percent ~= last_percent then
            last_percent = percent
            local msg = string.format("正在下载: %d%% (%d/%d KB)", percent, received_len // 1024, total_len // 1024)
            log.info("fota_app", "下载进度:", msg)
            sys.publish("FOTA_STATUS", "DOWNLOAD_PROGRESS", msg, percent)
        end
    end
end

-- ==================== libfota2 封装 ====================

-- 执行 libfota2 检测+下载+安装（不自动重启）
-- @param boolean is_manual true=用户手动触发（显示进度+弹窗），false=定时触发（静默）
local function fota_check_with_libfota2(is_manual)
    log.info("fota_app", ">>>>> 开始固件检查, is_manual:", is_manual, "fota_update_ready:", fota_update_ready)

    if not libfota2 then
        log.error("fota_app", "libfota2 不可用")
        sys.publish("FOTA_STATUS", "CHECK_FAIL", "FOTA模块未加载", -1)
        fota_running = false
        return
    end

    -- 如果已有下载好的升级包，直接提示重启，不用重复下载
    if fota_update_ready then
        log.info("fota_app", "已有待激活的升级包，提示用户重启")
        sys.publish("FOTA_STATUS", "DOWNLOAD_SUCCESS", "升级包已就绪，重启即可升级")
        if is_manual then
            sys.publish("FOTA_PROMPT_REBOOT", "升级包已下载完成，是否重启设备进行升级？")
        end
        fota_running = false
        return
    end

    local opts = {
        project_key = _G.PROJECT_KEY or _G.PRODUCT_KEY,
        timeout = 120000,
        callback = fota_progress_cb,
        userdata = "fota_progress",
    }
    log.info("fota_app", "调用 libfota2.request")

    -- 使用闭包在回调中区分手动/定时
    local ok, err = pcall(libfota2.request, function(ret)
        log.info("fota_app", "libfota2 回调, ret:", ret)

        if ret == 0 then
            -- 下载+安装成功，标记升级包已就绪，不自动重启
            fota_update_ready = true
            log.info("fota_app", ">>>>> 升级包下载安装完成，等待用户重启 <<<<<")
            sys.publish("FOTA_STATUS", "DOWNLOAD_SUCCESS", "升级包下载完成，重启即可升级")

            if is_manual then
                -- 手动检测：弹窗询问是否重启
                sys.publish("FOTA_PROMPT_REBOOT", "升级包已下载完成，是否重启设备进行升级？")
            else
                -- 定时检测：下载完成后也弹窗询问是否升级
                sys.publish("FOTA_STATUS", "UPDATE_READY", "有新版本，重启即可升级")
                sys.publish("FOTA_AUTO_PROMPT_UPGRADE", "检测到新版本已下载完成，是否立即升级？")
            end
        elseif ret == 4 then
            log.info("fota_app", "当前已是最新版本")
            sys.publish("FOTA_STATUS", "NO_NEW_VERSION", "当前已是最新版本")
        else
            local msg = "操作失败"
            if ret == 1 then msg = "连接失败"
            elseif ret == 2 then msg = "URL错误"
            elseif ret == 3 then msg = "服务器断开"
            elseif ret == 5 then msg = "版本号格式错误"
            else msg = "未知错误(" .. tostring(ret) .. ")" end
            log.error("fota_app", "升级失败:", msg)
            sys.publish("FOTA_STATUS", "CHECK_FAIL", msg, ret)
        end

        fota_running = false
    end, opts)

    if not ok then
        log.error("fota_app", "libfota2.request 调用失败:", err)
        sys.publish("FOTA_STATUS", "CHECK_FAIL", "FOTA调用失败", -1)
        fota_running = false
    end
end

-- ==================== 升级流程控制 ====================

-- 手动检测（显示进度+弹窗）
local function check_manual_task()
    log.info("fota_app", ">>>>> 手动检测 <<<<<")
    if fota_running then
        log.warn("fota_app", "操作进行中，跳过")
        return
    end
    fota_running = true
    fota_check_with_libfota2(true)  -- is_manual = true
end

-- 定时检测（静默下载）
local function check_auto_task()
    log.info("fota_app", ">>>>> 定时检测 <<<<<")
    if fota_running then
        log.warn("fota_app", "操作进行中，跳过")
        return
    end
    fota_running = true
    fota_check_with_libfota2(false)  -- is_manual = false
end

-- ==================== fskv 操作（防御性） ====================

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
    log.info("fota_app", "设置 - auto:", auto, "interval:", interval)
    return auto, interval
end

local function save_settings(auto, interval)
    interval = tonumber(interval) or 86400
    if interval <= 0 then interval = 86400 end
    fskv_set_safe(KV_AUTO_CHECK, auto)
    fskv_set_safe(KV_INTERVAL, interval)
    log.info("fota_app", "设置已保存, auto:", auto, "interval:", interval)
end

-- ==================== 定时器管理 ====================

local function auto_check_func()
    log.info("fota_app", "定时器触发")
    sys.publish("FOTA_CHECK_AUTO")
end

local function on_settings_changed(auto, interval)
    sys.timerStop(auto_check_func)
    if auto_timer_id then
        sys.timerStop(auto_timer_id)
        auto_timer_id = nil
    end
    if auto and interval and interval > 0 then
        auto_timer_id = sys.timerLoopStart(auto_check_func, interval * 1000)
        log.info("fota_app", "定时器启动, 间隔:", interval)
    end
end

-- ==================== 事件处理 ====================

-- 手动检测（从UI按钮触发）
sys.subscribe("FOTA_CHECK_NOW", function()
    sys.taskInit(check_manual_task)
end)

-- 定时检测（从定时器触发）
sys.subscribe("FOTA_CHECK_AUTO", function()
    sys.taskInit(check_auto_task)
end)

-- 用户确认重启
sys.subscribe("FOTA_CONFIRM_REBOOT", function()
    log.info("fota_app", "用户确认重启，执行 rtos.reboot()")
    sys.publish("FOTA_STATUS", "REBOOTING", "正在重启...")
    sys.timerStart(rtos.reboot, 500)
end)

-- 自动触发升级提示（定时/开机检测下载完成后弹窗）
sys.subscribe("FOTA_AUTO_PROMPT_UPGRADE", function(message)
    log.info("fota_app", "自动检测完成，弹窗询问是否升级")
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
            w = mw,
            h = mh,
            style = { text_font_size = msg_font },
            title = "固件更新",
            text = message or "检测到新版本，是否立即升级？",
            buttons = { "稍后", "立即升级" },
            on_action = function(self, btn_label)
                self:destroy()
                if btn_label == "立即升级" then
                    sys.publish("FOTA_CONFIRM_REBOOT")
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
    log.info("fota_app", ">>>>> FOTA模块启动 <<<<<")

    local ip_ready = sys.waitUntil("IP_READY", 60000)
    if not ip_ready then
        log.warn("fota_app", "IP_READY超时")
    end
    network_ready = true
    log.info("fota_app", "IP_READY已到达")

    local auto, interval = get_settings()
    if auto and interval > 0 then
        on_settings_changed(auto, interval)
    end

    if auto then
        log.info("fota_app", "开机检测已启用，延迟3秒")
        sys.wait(3000)
        boot_check_done = true
        sys.publish("FOTA_CHECK_AUTO")  -- 开机用定时模式（静默）
    else
        boot_check_done = true
    end
end)
