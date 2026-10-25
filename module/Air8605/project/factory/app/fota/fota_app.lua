--[[
@module  fota_app
@summary FOTA 固件升级管理模块（适配共享库 script/libs/libfota3）
@version 5.0
@date    2026.09.23
@author  江访
@usage
本模块是 UI 消息协议 与 共享库 libfota3（request/check_update/config）之间的适配层。
升级全流程由 libfota3 内部完成（检测→下载→刷写→确认重启→重启，开机版本比对上报、
自动检测定时器、时间同步等待均由库管理），本模块职责：
1. 开机读取 fskv 设置 → libfota3.request() 启动自动检测
2. 把 libfota3 的 on_status 回调翻译成 FOTA_STATUS 消息（UI 状态栏）
3. 把 libfota3 的 on_confirm 回调做成全局确认弹窗（不依赖设置页在场）
4. 设置页的设置保存/读取（fskv 持久化 + libfota3.config() 同步定时器）

消息协议（订阅/发布）:
订阅: FOTA_CHECK_NOW                      → 手动检测升级（libfota3.check_update）
订阅: FOTA_CHECK_AUTO                     → 兼容保留，等同手动检测
订阅: FOTA_DOWNLOAD_START                 → 确认下载（回答下载确认弹窗）
订阅: FOTA_CONFIRM_REBOOT                 → 确认重启（回答重启确认弹窗；无待确认时直接重启）
订阅: FOTA_GET_SETTINGS                   → 获取升级设置（自动检测开关+间隔）
订阅: FOTA_SAVE_SETTINGS(auto,interval)   → 保存升级设置

发布: FOTA_STATUS(status, msg, percent)   → 升级状态（CHECKING/NEW_VERSION/CHECK_FAIL/...）
发布: FOTA_SETTINGS(auto, interval)       → 返回升级设置

确认弹窗由本模块直接创建在屏幕根上（任意界面在场都可操作，随 libfota3 的
on_confirm 自动出现）：下载确认「稍后/立即升级」、重启确认「稍后重启/立即重启」。
FOTA_PROMPT_DOWNLOAD / FOTA_PROMPT_REBOOT / FOTA_AUTO_PROMPT_UPGRADE 不再发布
（设置页保留其订阅代码作兼容，不会触发）。
]]

-- ==================== 防御性加载 ====================

local libfota3_ok, libfota3 = pcall(require, "libfota3")
if not libfota3_ok then
    log.warn("fota_app", "libfota3 加载失败:", libfota3)
    libfota3 = nil
end

-- ==================== 局部变量 ====================

-- 当前待回答的确认项：libfota3.on_confirm 的 callback + 动作类型
-- 同一时刻最多一个（libfota3 内部 running 标志串行化整个流程）
local pending_answer = nil
local pending_kind   = nil   -- "download" | "reboot"

-- fskv 键名（仅用于设置存储）
local KV_AUTO_CHECK  = "fota_auto_check"
local KV_INTERVAL    = "fota_interval"

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

-- ==================== 确认弹窗（on_confirm 适配） ====================

-- 回答当前待确认项
local function answer_pending(ok)
    local cb = pending_answer
    pending_answer = nil
    pending_kind = nil
    if cb then cb(ok) end
end

-- 只回答指定类型的待确认项（防止 FOTA_DOWNLOAD_START 误确认重启类弹窗）
local function answer_pending_if(kind, ok)
    if pending_kind == kind then
        answer_pending(ok)
    end
end

--[[
全局确认弹窗（屏幕根，切页不销毁；按钮必答，避免 libfota3 等待确认卡死）
@param string title    弹窗标题
@param string text     弹窗正文
@param string btn_no   取消按钮文案
@param string btn_yes  确认按钮文案
@param function on_decide function(ok) 按钮回调，ok=true 表示点确认
]]
local function show_confirm_dialog(title, text, btn_no, btn_yes, on_decide)
    local mw, mh = 300, 180
    local msg_font = 14
    if display and display.getSize then
        local lcd_w, lcd_h = display.getSize()
        if lcd_w and lcd_h and lcd_w > 0 then
            local d = math.min(lcd_w, lcd_h)
            mw = math.floor(d * 0.85)
            mh = math.floor(d * 0.35)
            msg_font = math.max(math.floor(d * 0.036), 14)
        end
    end
    airui.msgbox({
        w = mw, h = mh,
        style = { text_font_size = msg_font },
        title = title,
        text = text,
        buttons = { btn_no, btn_yes },
        on_action = function(self, btn_label)
            self:destroy()
            on_decide(btn_label == btn_yes)
        end
    })
end

-- ==================== libfota3 回调适配 ====================

-- libfota3 状态码 → FOTA_STATUS 状态码（boot_report 仅日志不打扰用户）
local STATUS_MAP = {
    checking        = "CHECKING",
    check_fail      = "CHECK_FAIL",
    no_new_version  = "NO_NEW_VERSION",
    new_version     = "NEW_VERSION",
    download_start  = "DOWNLOAD_START",
    downloading     = "DOWNLOAD_PROGRESS",
    download_fail   = "DOWNLOAD_FAIL",
    download_done   = "DOWNLOAD_SUCCESS",
    rebooting       = "REBOOTING",
    upgrade_success = "UPGRADE_SUCCESS",
    upgrade_fail    = "UPGRADE_FAIL",
    network_fail    = "CHECK_FAIL",
    boot_report     = false,
}

local function on_status(status, msg, percent)
    local mapped = STATUS_MAP[status]
    if mapped == false then
        log.info("fota_app", status, msg)
        return
    end
    sys.publish("FOTA_STATUS", mapped or status, msg, percent)
end

-- libfota3 确认请求（"download" 下载确认 / "reboot" 重启确认）
-- 弹窗挂起 callback，由按钮事件异步回答（true=确认 false=取消）
local function on_confirm(action, info, callback)
    -- 理论上同一时刻只有一个待确认项；若有残留（弹窗被异常销毁等），按取消兜底
    if pending_answer then
        answer_pending(false)
    end
    pending_answer = callback
    pending_kind = action

    if action == "download" then
        local text = string.format("检测到新版本 %s，是否下载升级？",
            (type(info) == "table" and info.version) or "")
        show_confirm_dialog("固件更新", text, "稍后", "立即升级",
            function(ok) answer_pending_if("download", ok) end)
    elseif action == "reboot" then
        show_confirm_dialog("固件更新", "升级包下载完成，是否重启设备进行升级？",
            "稍后重启", "立即重启",
            function(ok) answer_pending_if("reboot", ok) end)
    else
        -- 未知动作默认放行
        answer_pending(true)
    end
end

-- ==================== 消息订阅 ====================

sys.subscribe("FOTA_CHECK_NOW", function()
    if libfota3 then libfota3.check_update() end
end)

-- 兼容保留：旧版定时器事件，现自动定时检测由 libfota3 内部管理
sys.subscribe("FOTA_CHECK_AUTO", function()
    if libfota3 then libfota3.check_update() end
end)

sys.subscribe("FOTA_DOWNLOAD_START", function()
    answer_pending_if("download", true)
end)

sys.subscribe("FOTA_CONFIRM_REBOOT", function()
    if pending_kind == "reboot" then
        answer_pending(true)
    else
        -- 兼容旧语义：无待确认弹窗时直接重启
        sys.publish("FOTA_STATUS", "REBOOTING", "正在重启...")
        sys.timerStart(rtos.reboot, 500)
    end
end)

-- 获取/保存设置
sys.subscribe("FOTA_GET_SETTINGS", function()
    local auto, interval = get_settings()
    sys.publish("FOTA_SETTINGS", auto, interval)
end)

sys.subscribe("FOTA_SAVE_SETTINGS", function(auto, interval)
    save_settings(auto, interval)
    -- 同步到 libfota3：库内部自动刷新定时器（auto/interval 变化才重启计时）
    if libfota3 then
        libfota3.config({ auto = auto, interval = interval })
    end
end)

-- ==================== 开机流程 ====================

-- 开机版本比对上报由 libfota3 加载时自动完成（handle_boot），此处不再重复。
-- request() 内部：等待时间同步 → 按 fskv 设置启动/关闭自动检测定时器。
if libfota3 then
    local auto, interval = get_settings()
    libfota3.request({
        project_key    = _G.PROJECT_KEY or _G.PRODUCT_KEY,
        script_name    = _G.PROJECT,
        script_version = _G.VERSION,
        auto           = auto,
        interval       = interval,
        on_status      = on_status,
        on_confirm     = on_confirm,
    })
    log.info("fota_app", "FOTA模块启动", "libfota3", libfota3.version(),
        "auto", auto, "interval", interval)
else
    log.warn("fota_app", "libfota3 不可用，FOTA 功能停用")
end

return true
