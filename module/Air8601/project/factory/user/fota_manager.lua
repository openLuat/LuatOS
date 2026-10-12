--[[
@module  fota_manager
@summary FOTA 升级管理模块（基于官方 libfota3 扩展库）
@version 3.3
@date    2026.09.01
@author  王城钧
@usage
    功能：把 config.fota 的配置与回调注册给官方 libfota3，并在升级过程中做业务保护与状态记录。
          检测、下载、刷写、上报均由 libfota3 完成（本模块不修改该扩展库）。

    对外接口：
      start()          注册 FOTA 参数与回调（main.lua 联网后调用一次）
      check_update()   手动触发一次升级检测
      downloading      升级包下载中标志（true=下载中，供其它模块让出网络）
      link_lost        网络是否丢失（由 IP_READY / IP_LOSE 事件维护）
      on_net_event()   网络事件通知（外部模块可调用）

    libfota3 回调：
      on_status(status, msg, percent)    状态日志；维护 downloading 标志
      on_confirm(action, info, callback) 升级确认；业务忙时返回 false

    本模块不操作 Air6205 供电（GPIO57），该引脚由 netdrv_wifi.lua 管理。

    配置（config.lua → config.fota）：
      enabled        是否启用 FOTA
      project_key    FOTA项目密钥（必填）
      script_name    脚本名称，默认取 _G.PROJECT
      script_version 脚本版本，默认取 _G.VERSION
      auto           是否自动定时检测（false=仅 check_update() 手动触发）
      interval       自动检测间隔（秒），仅 auto=true 时生效
]]

local fota_manager = {}

local config = require "config"
local libfota3 = require "libfota3"

-- ==================== 模块状态 ====================

-- 升级包下载中标志：true=下载中（其它模块据此暂停占用网络）
fota_manager.downloading = false

-- 网络状态：true=网络丢失（由 IP_READY/IP_LOSE 更新）
fota_manager.link_lost = false

-- start() 是否已执行过（防止重复注册参数）
local auto_started = false

-- ==================== Air6205 供电 ====================

-- 本模块不操作 6205 供电（GPIO57），该引脚由 netdrv_wifi.lua 管理。

-- ==================== 业务保护 ====================

-- 检查当前是否允许升级（存取件业务与人脸识别都空闲）
-- @return boolean 是否允许
-- @return string 不允许时的原因
local function can_reboot_now()
    local ok_biz, busy = pcall(function()
        return require("ecbusiness").is_busy()
    end)
    if ok_biz and busy then
        return false, "存取件业务进行中"
    end
    local ok_face, face_busy = pcall(function()
        return require("face_manager").is_busy()
    end)
    if ok_face and face_busy then
        return false, "人脸识别进行中"
    end
    return true
end

-- 下载失败处理：输出错误日志（不自动重试，需重新调用 check_update()）
local function handle_download_fail(reason)
    log.error("fota_manager", "升级包下载失败：" .. tostring(reason or "未知")
              .. "（不自动重试，请排查网络/服务器后重新调用 check_update()）")
end

-- ==================== libfota3 回调 ====================

-- libfota3 状态回调：维护 downloading 标志并输出日志
-- status 取值：network_fail/checking/check_fail/no_new_version/new_version/
--   download_start/downloading/download_fail/download_done/rebooting/upgrade_success/upgrade_fail
local function on_status_cb(status, msg, percent)
    if status == "download_start" then
        fota_manager.downloading = true
    elseif status == "download_done" or status == "download_fail" then
        fota_manager.downloading = false
    end

    -- 下载失败：只记日志（不自动重试/重启，按需升级由人工判断处理）
    if status == "download_fail" then
        handle_download_fail(msg)
    end

    if percent then
        log.info("fota_manager", status, msg or "", percent)
    else
        log.info("fota_manager", status, msg or "")
    end
end

-- libfota3 确认回调：业务忙时返回 false，空闲时返回 true
-- 注意：libfota3 会阻塞等待本回调调用 callback，任何分支都必须调用一次。
-- action 取值："download"（确认下载）/ "reboot"（确认重启升级）
local function on_confirm_cb(action, info, callback)
    -- 检查业务状态：存取件业务或人脸识别进行中则拒绝本次升级
    local idle, why = can_reboot_now()
    if not idle then
        log.warn("fota_manager", "业务繁忙(" .. tostring(action) .. ")，拒绝本次升级，等待下次触发（"
                 .. tostring(why) .. "）")
        callback(false)
        return
    end
    if action == "download" then
        log.info("fota_manager", "业务空闲，自动确认下载", info and info.version, info and info.fota_sn)
    elseif action == "reboot" then
        log.info("fota_manager", "业务空闲，自动确认重启升级")
    end
    callback(true)
end

-- ==================== 对外接口 ====================

-- 启动 FOTA 自动检测（main.lua 网络就绪后调用；整机重启后会自动再次调用）
function fota_manager.start()
    if auto_started then return end
    auto_started = true

    local cfg = config.get("fota", {})
    if not cfg.enabled then
        log.info("fota_manager", "FOTA 未启用，跳过")
        return
    end
    if not cfg.project_key or cfg.project_key == "" then
        log.warn("fota_manager", "未配置 project_key，FOTA 无法使用（请在 config.lua 填写）")
        return
    end

    -- 读取配置：脚本名/版本可由 config 覆盖，auto 与 interval 取自 config
    local auto = cfg.auto ~= false
    local interval = cfg.interval or 86400
    log.info("fota_manager", "FOTA 配置注入：project_key=" .. tostring(cfg.project_key)
             .. ", auto=" .. tostring(auto) .. ", interval=" .. tostring(interval) .. "s"
             .. (auto and "" or "（按需模式：不自动检测，需调用 check_update() 触发）"))

    -- 向 libfota3 注册参数与回调（auto=false 时库不启动检测定时器）
    libfota3.request({
        project_key = cfg.project_key,
        script_name = cfg.script_name or _G.PROJECT,
        script_version = cfg.script_version or _G.VERSION,
        auto = auto,
        interval = interval,
        on_status = on_status_cb,
        on_confirm = on_confirm_cb,
    })
end

-- 手动触发一次升级检测
function fota_manager.check_update()
    -- 前置校验：未启用或未配置密钥时直接返回
    local cfg = config.get("fota", {})
    if not cfg.enabled then
        log.info("fota_manager", "FOTA 未启用，跳过手动检测")
        return
    end
    if not cfg.project_key or cfg.project_key == "" then
        log.warn("fota_manager", "未配置 project_key，无法检测升级（请在 config.lua 填写）")
        return
    end
    libfota3.check_update()
end

-- ==================== 网络事件（内部订阅 + 外部接口兼容） ====================

local function ip_ready_cb()
    fota_manager.link_lost = false
    log.info("fota_manager", "网络恢复(IP_READY)")
end

local function ip_lose_cb()
    fota_manager.link_lost = true
    log.warn("fota_manager", "网络丢失(IP_LOSE)")
end

-- 订阅网络事件，维护 link_lost
sys.subscribe("IP_READY", ip_ready_cb)
sys.subscribe("IP_LOSE", ip_lose_cb)

-- 网络事件通知（外部模块可调用，与内部订阅等效）
function fota_manager.on_net_event(evt)
    if evt == "IP_LOSE" then
        fota_manager.link_lost = true
        log.warn("fota_manager", "网络丢失(IP_LOSE)")
    elseif evt == "IP_READY" then
        fota_manager.link_lost = false
        log.info("fota_manager", "网络恢复(IP_READY)")
    end
end

return fota_manager
