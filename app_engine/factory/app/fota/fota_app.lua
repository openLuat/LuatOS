--[[
@module  fota_app
@summary FOTA 固件升级管理模块（两步协议：检查→下载→开机上报）
@version 4.0
@date    2026.06.08
@author  江访
@usage
升级流程：
1. 手动/定时检测 → 有新版本 → 生成状态文件(/fota_state.json)
2. 下载完成 → 更新状态文件（下载完成）
3. 重启设备
4. 开机后读取状态文件 → 根据版本比对判断升级结果 → 上报服务器 → 删除状态文件
5. 上报完成后（无论成功失败），进行下次升级检查

事件接口（与 settings_fota_win.lua 兼容）：
  订阅: FOTA_CHECK_NOW / FOTA_CHECK_AUTO / FOTA_CONFIRM_REBOOT / FOTA_GET_SETTINGS / FOTA_SAVE_SETTINGS
  发布: FOTA_STATUS / FOTA_PROMPT_DOWNLOAD / FOTA_PROMPT_REBOOT / FOTA_SETTINGS / FOTA_AUTO_PROMPT_UPGRADE
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
local last_check_result = nil     -- 最近一次check结果（供下载使用）
local last_percent = -1            -- 下载进度

-- fskv 键名（仅用于设置存储）
local KV_AUTO_CHECK  = "fota_auto_check"
local KV_INTERVAL    = "fota_interval"

-- 状态文件路径
local FOTA_STATE_FILE = "/fota_state.json"

-- ==================== 状态文件操作 ====================

-- 状态文件结构: { fota_sn, status: "has_update"|"download_done", old_version, new_version }
local function fota_state_save(state)
    local ok, err = pcall(function()
        io.writeFile(FOTA_STATE_FILE, json.encode(state))
    end)
    if ok then
        log.info("fota_app", "state file saved", state.status)
    else
        log.error("fota_app", "save state file failed", err)
    end
end

local function fota_state_load()
    if not io.exists(FOTA_STATE_FILE) then return nil end
    local ok, data = pcall(function()
        return json.decode(io.readFile(FOTA_STATE_FILE))
    end)
    if ok and type(data) == "table" then return data end
    return nil
end

local function fota_state_clear()
    if io.exists(FOTA_STATE_FILE) then
        os.remove(FOTA_STATE_FILE)
        log.info("fota_app", "state file removed")
    end
end


-- ==================== fskv 操作（设置） ====================

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

-- 开机检测：根据状态文件判断上次升级结果并上报
local function report_last_upgrade()
    local state = fota_state_load()
    if not state then
        log.info("fota_app", "no state file, skip report")
        return
    end

    -- 当前设备信息
    local cur_version = rtos.version()
    local cur_core_version = cur_version and cur_version:gsub("^V", "") or "0"
    local cur_core_id = select(2, rtos.version(true)) or "0"
    local cur_script_version = _G.VERSION or "0.0.0"

    -- 旧信息（升级前）
    local old_core_id = state.old_core_id or "?"
    local old_core_version = state.old_core_version or "?"
    local old_script_version = state.old_script_version or "?"

    -- 目标信息（升级后期望达到的版本）
    local new_core_id = state.new_core_id or "?"
    local new_core_version = state.new_core_version or "?"
    local new_script_version = state.new_script_version or "?"

    log.info("fota_app", "=== 升级版本比对 ===")
    log.info("fota_app", string.format("core_id:     old=%s  new=%s  cur=%s", old_core_id, new_core_id, cur_core_id))
    log.info("fota_app", string.format("core_version:old=%s  new=%s  cur=%s", old_core_version, new_core_version, cur_core_version))
    log.info("fota_app", string.format("script_ver:  old=%s  new=%s  cur=%s", old_script_version, new_script_version, cur_script_version))

    -- 判断升级结果：core 或 script 任一变化即为成功
    local core_changed = (cur_core_version ~= old_core_version) or (cur_core_id ~= old_core_id)
    local script_changed = (cur_script_version ~= old_script_version)
    local result_code = 3  -- 默认：其他错误

    if core_changed or script_changed then
        result_code = 1  -- 升级成功
        log.info("fota_app", "upgrade success",
            "core_changed", core_changed,
            "script_changed", script_changed)
    else
        result_code = 2  -- 无变化，升级失败
        log.info("fota_app", "upgrade failed, no version change")
    end

    if libfota3 and state.fota_sn and state.fota_sn ~= "" then
        log.info("fota_app", "上报上次升级结果", "fota_sn", state.fota_sn, "code", result_code)
        libfota3.report_result(state.fota_sn, result_code)
    end

    -- 上报完成，删除状态文件
    fota_state_clear()
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

    -- 有新版本 → 生成状态文件（has_update），记录升级前的完整版本信息
    last_check_result = result
    local cur_ver = rtos.version()
    local state = {
        fota_sn = result.fota_sn or "",
        status = "has_update",
        old_core_id = select(2, rtos.version(true)) or "0",
        old_core_version = cur_ver and cur_ver:gsub("^V", "") or "0",
        old_script_version = _G.VERSION or "0.0.0",
        new_core_id = result.core_id or "?",
        new_core_version = result.core_version or "?",
        new_script_version = result.script_version or "0.0.0"
    }
    fota_state_save(state)

    local msg = string.format("新版本 %s (%s)",
        result.script_version or "?",
        result.size and (math.floor(result.size / 1024) .. "KB") or "未知大小")
    sys.publish("FOTA_STATUS", "NEW_VERSION", msg)

    if is_manual then
        sys.publish("FOTA_PROMPT_DOWNLOAD", "检测到新版本 " .. (result.script_version or "") .. "，是否下载升级？")
    else
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

    local ok, err = libfota3.download(result.url, result.sha256, function(received, total)
        if total and total > 0 then
            local percent = math.floor(received * 100 / total)
            if percent ~= last_percent then
                last_percent = percent
                local msg = string.format("正在下载: %d%% (%d/%d KB)", percent, received // 1024, total // 1024)
                sys.publish("FOTA_STATUS", "DOWNLOAD_PROGRESS", msg, percent)
            end
        end
    end)
    if not ok then
        -- 下载失败 → 更新状态文件，标记下载失败以便上报
        local state = fota_state_load()
        if state then
            state.status = "download_fail"
            fota_state_save(state)
        end
        log.error("fota_app", "下载失败:", err)
        sys.publish("FOTA_STATUS", "DOWNLOAD_FAIL", err or "下载失败")
        fota_running = false
        return
    end

    -- 下载成功 → 更新状态文件（download_done）
    local state = fota_state_load()
    if state then
        state.status = "download_done"
        fota_state_save(state)
    end

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

-- 用户确认重启（重启前不上报，等开机后再判断结果）
sys.subscribe("FOTA_CONFIRM_REBOOT", function()
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

    -- 1. 检测上次升级状态文件，若存在则上报
    report_last_upgrade()

    -- 2. 等待网络就绪
    local ip_ready = sys.waitUntil("IP_READY", 60000)
    if not ip_ready then
        log.warn("fota_app", "IP_READY超时")
    end
    network_ready = true

    -- 3. 启动定时器
    local auto, interval = get_settings()
    if auto and interval > 0 then
        on_settings_changed(auto, interval)
    end

    -- 4. 无论上次是否成功，都进行升级检查
    if auto then
        sys.wait(3000)
        sys.publish("FOTA_CHECK_AUTO")
    end
end)
