--[[
@module  fota_manager
@summary FOTA 升级管理模块（V3.3：官方原版 libfota3 接口 + 下载失败重启兜底 + 写 flash 后 EN 断电隔离）
@version 3.3
@date    2026.09.01
@author  王城钧
@usage
    V3.1（按用户要求：libfota3 恢复官方原版 + 适配代码）：
    fota_manager 只做「配置注入 + 业务保护 + 状态维护」，检测/下载/刷写/上报全部交给官方 libfota3：
      - start()        → libfota3.request({...})  启动自动检测（含时间同步 + 定时检测 + 下载 + 刷写 + 重启）
      - check_update() → libfota3.check_update()  手动触发一次完整检测
      - downloading    → on_status 回调维护（aircloud 轮询让道读取）
      - on_confirm     → 业务繁忙保护：存/取/刷脸进行中拒绝下载/重启
      - link_lost      → 内部订阅 IP_READY/IP_LOSE + on_net_event() 兼容接口

    libfota3.lua 使用官方原版 v2.0（2026.06.18，1039 行）：
    检测/下载/刷写/上报全部官方实现，本模块不再自实现 http 检测/下载/刷写，也不做 EN 断电。
    注意：官方版写 flash 用 fota.file() 整包写（C 层同步循环，约 25-46 秒 CPU 阻塞），
    期间 Lua 主循环无法喂狗，由 main.lua 看门狗（wdt.init(60000) 超时 60 秒）覆盖。

    V3.2（下载失败重启兜底）：官方版下载失败后仅保存状态并等下一次定时检测，
    对 UART3 桥接链路不足。本版本在 on_status 收到 download_fail 时：
      - 读取 /fota_retry.json 跨重启计数，≤3 次则整机重启恢复 airlink 链路后重新检测
      - 超过 3 次则清空计数，放弃本轮重启，交给定时器自然检测（防止无限重启循环）
      - download_done（校验通过）或 no_new_version（链路健康）时清空计数

    V3.3（写 flash 完成后 EN 断电隔离 UART3）：官方原版 http_download() 在写 flash
    （fota.file 整包写，约 25-46 秒 CPU 阻塞）期间 6205 仍挂在 UART3 上，实测产生大量
    uart3 err 中断风暴。本版本在 on_status 收到 download_done（此时写 flash 已完成、
    即将确认重启）时拉高 EN(GPIO57) 断电 6205 隔离 UART3；若重启被业务保护拒绝
    （on_confirm 返回 false），则立即拉低 EN 恢复 6205 保证网络可用；
    upgrade_fail 分支也做恢复兜底。注意：官方库 download_done 回调发生在写 flash
    完成之后，本优化隔离的是「写 flash 完成后至重启前」的窗口，写 flash 期间的
    uart3 err 风暴由官方库行为决定（实测不影响升级成功）。

    配置（config.lua → config.fota）：
      enabled        是否启用
      project_key    FOTA项目密钥（必填）
      interval       自动检测间隔（秒，默认3600）
]]

local fota_manager = {}

local config = require "config"
local libfota3 = require "libfota3"

-- ==================== 模块状态 ====================

-- 下载中标志（供 aircloud 轮询让道，下载期间完全暂停业务流量）
fota_manager.downloading = false

-- 链路状态（内部订阅 IP_READY/IP_LOSE 更新，供日志观察）
fota_manager.link_lost = false

-- start() 防重入标志
local auto_started = false

-- ==================== Air6205 EN 控制（V3.3） ====================

-- Air6205 EN 引脚：GPIO57，低电平使能、高电平断电（与 netdrv_wifi.lua 保持一致）
local AIR6205_EN_PIN = 57

-- 断电 Air6205：拉高 EN，物理隔离 UART3（写 flash 完成后至重启前静默）
local function power_off_6205()
    pcall(gpio.setup, AIR6205_EN_PIN, 1)
    log.info("fota_manager", "已拉高 EN 禁用 Air6205，UART3 静默")
end

-- 恢复 Air6205：拉低 EN 重新使能（重启被拒绝或升级失败时保证网络可用）
local function power_on_6205()
    pcall(gpio.setup, AIR6205_EN_PIN, 0)
    log.info("fota_manager", "已拉低 EN 重新使能 Air6205")
end

-- ==================== 下载失败重启兜底（V3.2） ====================

-- 重试计数文件：跨重启持久化，防止无限重启循环
local RETRY_FILE = "/fota_retry.json"
-- 下载失败后整机重启重试的最大次数
local MAX_RETRY = 3
-- 重启调度标志：防止重复调度（on_status 可能被多次触发）
local reboot_scheduled = false

-- 读取跨重启重试计数（文件不存在或损坏时返回 0）
local function load_retry_count()
    local f = io.open(RETRY_FILE, "r")
    if not f then
        return 0
    end
    local data = f:read("*a")
    f:close()
    local ok, obj = pcall(json.decode, data)
    if ok and obj and type(obj.count) == "number" then
        return obj.count
    end
    return 0
end

-- 保存重试计数
local function save_retry_count(count)
    local f = io.open(RETRY_FILE, "w")
    if f then
        f:write(json.encode({count = count}))
        f:close()
    end
end

-- 清空重试计数（下载成功/链路健康时调用）
local function clear_retry_count()
    if io.exists(RETRY_FILE) then
        os.remove(RETRY_FILE)
    end
end

-- 下载失败兜底：整机重启恢复 airlink 链路后重新检测（≤MAX_RETRY 次）
local function handle_download_fail(reason)
    local count = load_retry_count()
    if count >= MAX_RETRY then
        -- 已达上限：清空计数，放弃本轮重启，交给 libfota3 定时器自然检测
        clear_retry_count()
        log.warn("fota_manager", "下载连续失败已达上限 " .. MAX_RETRY
                 .. " 次，本轮放弃重启，等待定时器自然检测")
        return
    end
    count = count + 1
    save_retry_count(count)
    log.warn("fota_manager", "下载失败，第 " .. count .. "/" .. MAX_RETRY
             .. " 次重试：整机重启恢复链路后重新检测（原因：" .. tostring(reason or "未知") .. "）")
    if not reboot_scheduled then
        reboot_scheduled = true
        -- 延迟 2 秒重启：让 libfota3 完成定时器状态保存与日志输出
        sys.timerStart(function()
            rtos.reboot()
        end, 2000)
    end
end

-- ==================== libfota3 回调 ====================

-- on_status 状态回调：维护 downloading 标志 + 日志
-- status 取值见 libfota3：network_fail/checking/check_fail/no_new_version/new_version/
-- download_start/downloading/download_fail/download_done/rebooting/upgrade_success/upgrade_fail
local function on_status_cb(status, msg, percent)
    if status == "download_start" then
        fota_manager.downloading = true
    elseif status == "download_done" or status == "download_fail" then
        fota_manager.downloading = false
    end

    -- V3.2 下载失败兜底：整机重启恢复链路后重新检测（≤3 次）
    if status == "download_fail" then
        handle_download_fail(msg)
    elseif status == "download_done" or status == "no_new_version" then
        -- 下载成功（校验通过）或链路健康（检测到无更新）：历史失败作废
        clear_retry_count()
    end

    -- V3.3 写 flash 完成后 EN 断电隔离 UART3
    -- 说明：官方库 download_done 在 fota.file 写 flash 完成后、确认重启前回调，
    --       此时断电 6205 可隔离「写 flash 完成后至重启前」的 UART3 中断。
    if status == "download_done" then
        power_off_6205()
    elseif status == "upgrade_fail" then
        -- 升级失败/无变化：恢复 6205 保证网络可用（防御性兜底）
        power_on_6205()
    end

    if percent then
        log.info("fota_manager", status, msg or "", percent)
    else
        log.info("fota_manager", status, msg or "")
    end
end

-- on_confirm 确认回调：业务繁忙保护
-- 说明：libfota3.wait_confirm() 会阻塞轮询等待 callback 被调用，本回调必须保证调用 callback。
-- action 取值："download"（确认下载）/ "reboot"（确认重启升级）
local function on_confirm_cb(action, info, callback)
    local ecbusiness = require "ecbusiness"
    if ecbusiness.is_busy() then
        log.warn("fota_manager", "业务繁忙，拒绝", action)
        -- V3.3 边界处理：若 download_done 已断电 6205 而 reboot 被拒绝（不重启），
        -- 必须立即恢复 6205，否则设备将失去 WiFi 网络
        if action == "reboot" then
            power_on_6205()
        end
        callback(false)
        return
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

    local interval = cfg.interval or 3600
    log.info("fota_manager", "启动 FOTA 自动检测（libfota3.request），project_key="
             .. tostring(cfg.project_key) .. ", interval=" .. interval .. "s")

    -- libfota3.request：等待时间同步 → 启动自动检测定时器（内部含网络检测/下载/刷写/重启）
    libfota3.request({
        project_key = cfg.project_key,
        script_name = _G.PROJECT or "",
        script_version = _G.VERSION or "",
        auto = true,
        interval = interval,
        on_status = on_status_cb,
        on_confirm = on_confirm_cb,
    })
end

-- 手动触发一次完整检测（复用 libfota3 running 互斥）
function fota_manager.check_update()
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

-- 内部订阅网络事件（主项目 netdrv_wifi.lua 仅打印日志，不转发给本模块，故内部自行订阅）
sys.subscribe("IP_READY", ip_ready_cb)
sys.subscribe("IP_LOSE", ip_lose_cb)

-- 网络事件通知（兼容接口：外部模块可调用，与内部订阅等效，仅记录状态供日志观察）
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
