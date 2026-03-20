--[[
@module  fota_app
@summary FOTA升级应用模块，使用libfota2
@version 1.0
@date    2026.03.20
@author  江访
@usage
订阅消息：
- "FOTA_CHECK"：手动触发升级
- "FOTA_AUTO_SETTINGS_CHANGED"：自动设置变化时重启定时器
- "FOTA_GET_SETTINGS"：获取当前自动升级设置
- "FOTA_SAVE_SETTINGS"：保存自动升级设置

发布消息：
- "FOTA_STATUS"：状态更新
- "FOTA_SETTINGS"：返回当前设置（auto, interval）
]]

local libfota2 = require("libfota2")

local auto_timer_id = nil          -- 可选，保留用于调试
local network_ready = false        -- 网络就绪标志

-- 自动升级检查函数（具名函数，便于定时器停止）
local function auto_check_func()
    sys.publish("FOTA_CHECK")
end

-- 等待网络就绪（带超时）
local function wait_network(timeout)
    if network_ready then return true end
    local ret = sys.waitUntil("IP_READY", timeout or 30000)
    network_ready = (ret == "IP_READY")
    return network_ready
end

-- FOTA 结果回调（libfota2 主回调）
local function fota_result_cb(ret)
    log.info("fota_app.fota_result_cb", ret)
    if ret == 0 then
        sys.publish("FOTA_STATUS", "DOWNLOAD_SUCCESS", "升级包下载成功，即将重启")
        sys.timerStart(rtos.reboot, 2000)
    elseif ret == 4 then
        sys.publish("FOTA_STATUS", "NO_NEW_VERSION", "当前已是最新版本")
    else
        local msg = "操作失败"
        if ret == 1 then
            msg = "连接失败"
        elseif ret == 2 then
            msg = "URL错误"
        elseif ret == 3 then
            msg = "服务器断开"
        elseif ret == 5 then
            msg = "版本号格式错误，需使用xxx.yyy.zzz形式"
        else
            msg = "未知错误(" .. ret .. ")"
        end
        sys.publish("FOTA_STATUS", "CHECK_FAIL", msg, ret)
    end
end

-- 下载进度回调
local function fota_progress_cb(total_len, received_len, userdata)
    if total_len > 0 then
        local percent = math.floor(received_len * 100 / total_len)
        local msg = string.format("正在下载：%d%% (%d/%d KB)", percent, received_len//1024, total_len//1024)
        sys.publish("FOTA_STATUS", "DOWNLOAD_PROGRESS", msg, percent)
    end
end

-- 执行FOTA升级（手动或自动触发）
local function fota_task()
    if not wait_network() then
        log.error("fota_app", "网络未就绪，取消升级")
        sys.publish("FOTA_STATUS", "CHECK_FAIL", "网络未就绪", -1)
        return
    end

    sys.publish("OPEN_FOTA_PROGRESS_WIN")
    sys.publish("FOTA_STATUS", "DOWNLOADING", "正在连接服务器...")

    local opts = {
        project_key = PROJECT_KEY or nil,
        callback = fota_progress_cb,
        userdata = "fota_progress",
        timeout = 120000
    }
    libfota2.request(fota_result_cb, opts)
end

-- 启动自动更新定时器（通过函数名管理）
local function start_auto_timer(interval)
    -- 先停止已有定时器（通过函数名停止）
    sys.timerStop(auto_check_func)
    if auto_timer_id then
        sys.timerStop(auto_timer_id)
        auto_timer_id = nil
    end
    if interval > 0 then
        auto_timer_id = sys.timerLoopStart(auto_check_func, interval * 1000)
        log.info("fota_app", "auto timer started, interval=", interval)
    end
end

-- 处理自动设置变化
local function on_auto_settings_changed(auto, interval)
    if auto then
        start_auto_timer(interval)
    else
        -- 通过函数名停止定时器
        sys.timerStop(auto_check_func)
        if auto_timer_id then
            sys.timerStop(auto_timer_id)
            auto_timer_id = nil
        end
    end
end

-- 初始化自动更新定时器（读取存储）
local function init_auto_timer()
    local auto = fskv.get("fota_auto_update")
    if auto == nil then auto = false end
    local interval = fskv.get("fota_auto_interval")
    if interval == nil then interval = 3600 end
    if auto and interval > 0 then
        start_auto_timer(interval)
    end
end

-- 获取当前设置
local function get_settings()
    local auto = fskv.get("fota_auto_update")
    if auto == nil then auto = false end
    local interval = fskv.get("fota_auto_interval")
    if interval == nil then interval = 3600 end
    return auto, interval
end

-- 保存设置
local function save_settings(auto, interval)
    if interval == nil or interval <= 0 then
        interval = 3600
    end
    fskv.set("fota_auto_update", auto)
    fskv.set("fota_auto_interval", interval)
    log.info("fota_app", "settings saved", auto, interval)
    on_auto_settings_changed(auto, interval)
end

-- 订阅消息
sys.subscribe("FOTA_CHECK", function()
    sys.taskInit(fota_task)
end)

sys.subscribe("FOTA_AUTO_SETTINGS_CHANGED", on_auto_settings_changed)

sys.subscribe("FOTA_GET_SETTINGS", function()
    local auto, interval = get_settings()
    sys.publish("FOTA_SETTINGS", auto, interval)
end)

sys.subscribe("FOTA_SAVE_SETTINGS", function(auto, interval)
    save_settings(auto, interval)
end)

-- 系统启动后立即初始化自动更新定时器，并监听网络
sys.taskInit(function()
    init_auto_timer()
    sys.waitUntil("IP_READY", 30000)
    network_ready = true
end)