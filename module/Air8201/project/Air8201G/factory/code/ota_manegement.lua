--[[
@module  ota_manegement
@summary OTA 远程升级管理（基于合宙官方 libfota2 + iot.openluat.com 平台）
@version 1.0
@date    2026.05.28
@description
    使用合宙官方 IoT 平台（iot.openluat.com）进行远程固件升级。
    触发机制：
      1. 开机首次：等待 IP_READY + 短暂联网稳定后主动获取一次升级
      2. 周期触发：之后每 24 小时获取一次升级信息
      3. 手动触发：mypower 模块的 PWRKEY 短按事件 (PWRKEY_SHORT_PRESS) 立即触发一次
         （独立于 24 小时定时器，不会重置或影响定时器）
    依赖：
      - 全局变量 PROJECT / VERSION（main.lua 顶部定义）
      - 全局变量 PRODUCT_KEY（本模块顶部定义，需用户去 iot.openluat.com 创建项目后替换）
    参考 demo：
      - https://gitee.com/openLuat/LuatOS/tree/master/module/Air8000/demo/fota/fota2(使用libfota2扩展库)/iot_server/psm_power_fota.lua
      - https://gitee.com/openLuat/LuatOS/tree/master/script/libs/libfota2.lua
      - 文档：https://docs.openluat.com/luatos_lesson/009_luatos_fota/
]] local libfota2 = require "libfota2"

-- ========== 合宙 IoT 平台配置 ==========
-- ⚠️ 用户必须修改：到 https://iot.openluat.com 创建项目后，将下方 "123" 替换为真实项目 ID
-- libfota2 默认从全局变量 _G.PRODUCT_KEY 读取，未配置时会返回错误码 5
-- if not _G.PRODUCT_KEY then
--     _G.PRODUCT_KEY = "123" -- TODO: 用户去 iot.openluat.com 创建项目后替换
-- end

-- ========== 模块对外暴露配置 ==========
local ota_manegement = {}

-- 周期检查间隔：24 小时
ota_manegement.CHECK_INTERVAL_MS = 24 * 3600 * 1000

-- 联网后多少毫秒触发首次检查（给基站对时/网络稳定留缓冲）
ota_manegement.FIRST_CHECK_DELAY_MS = 5000

-- 升级标识冷却时长：fota_in_progress 置为 true 后，若 5 分钟内未收到 fota_cb 回调
-- （cb 正常会立刻清掉 flag），则由本冷却定时器自动清掉，避免极端情况下永久卡 true
ota_manegement.IN_PROGRESS_COOLDOWN_MS = 5 * 60 * 1000   -- 300000ms = 5 分钟

-- 同时只允许一次升级请求在途，避免并发
local fota_in_progress = false

-- 升级标识冷却定时器句柄
local in_progress_timer_id = nil

-- 周期定时器句柄（仅"开机首次"完成后才启动，用于 24 小时周期）
local period_timer_id = nil

-- ========== libfota2 升级回调 ==========
-- result 含义（libfota2.lua 源码注释）：
--   0 -> 成功（已下载完成，需 reboot）
--   1 -> 连接失败（URL 拼写错误或服务器内网）
--   2 -> URL 错误
--   3 -> 服务器断开
--   4 -> 接收报文错误（含"已是最新版本"分支，云平台 code=27）
--   5 -> 版本号格式错误（必须 x.y.z）
local function fota_cb(result)
    -- 第一时间释放 in_progress 并停掉冷却定时器
    fota_in_progress = false
    if in_progress_timer_id then
        sys.timerStop(in_progress_timer_id)
        in_progress_timer_id = nil
    end
    log.info("OTA", "升级回调返回 result=" .. tostring(result))

    -- 升级流程结束，发布全局消息（与 demo 一致，便于其他模块感知）
    sys.publish("FOTA_END", result)

    if result == 0 then
        log.warn("OTA", "===> 升级包下载成功，3 秒后重启模组应用新固件")
        -- 留 3 秒让其他模块（如 report）完成最后一笔数据落盘
        sys.wait(3000)
        rtos.reboot()

    elseif result == 1 then
        log.warn("OTA", "连接失败：请检查 url 拼写或服务器配置")
    elseif result == 2 then
        log.warn("OTA", "URL 错误：检查 url 拼写")
    elseif result == 3 then
        log.warn("OTA", "服务器断开：检查服务器白名单配置")
    elseif result == 4 then
        log.info("OTA",
            "无升级包/已是最新版本/或服务端异常（参见 libfota2 内部日志的云平台 code）")
    elseif result == 5 then
        log.error("OTA", "版本号格式错误：iot 平台要求 VERSION = x.y.z 形式，当前 VERSION=" ..
            tostring(_G.VERSION))
    else
        log.warn("OTA", "未知 result=" .. tostring(result))
    end
end

-- ========== 内部：单次发起升级检查 ==========
-- @param trigger string  触发来源标识（仅日志用："BOOT" / "PERIOD" / "PWRKEY"）
local function do_request(trigger)
    if fota_in_progress then
        log.warn("OTA", "[" .. trigger .. "] 已有升级请求在进行，跳过本次")
        return false
    end

    if not _G.PRODUCT_KEY or _G.PRODUCT_KEY == "" then
        log.error("OTA", "[" .. trigger .. "] PRODUCT_KEY 未配置，无法使用合宙 IoT 平台")
        return false
    end

    fota_in_progress = true
    log.info("OTA", "==========================================")
    log.info("OTA", "[" .. trigger .. "] 发起升级请求")
    log.info("OTA", "  PROJECT     = " .. tostring(_G.PROJECT))
    log.info("OTA", "  VERSION     = " .. tostring(_G.VERSION))
    log.info("OTA", "  PRODUCT_KEY = " .. tostring(_G.PRODUCT_KEY))
    log.info("OTA", "  COOLDOWN    = " .. ota_manegement.IN_PROGRESS_COOLDOWN_MS .. "ms")
    log.info("OTA", "==========================================")

    -- 启动 5 分钟冷却定时器：若 fota_cb 在此期间未被调用就强制清掉 flag
    -- 正常情况下 cb 会先触发并 stop 掉本 timer，本 timer 仅作为兜底
    if in_progress_timer_id then
        sys.timerStop(in_progress_timer_id)
        in_progress_timer_id = nil
    end
    in_progress_timer_id = sys.timerStart(function()
        in_progress_timer_id = nil
        if fota_in_progress then
            log.warn("OTA", "[" .. trigger .. "] 冷却到期，5 分钟内未收到 fota_cb，强制清 in_progress")
            fota_in_progress = false
        end
    end, ota_manegement.IN_PROGRESS_COOLDOWN_MS)

    -- libfota2.request(cbFnc, opts)
    -- 不传 opts.url → 默认使用 http://iot.openluat.com/api/site/firmware_upgrade
    -- 内部自动拼接 imei/project_key/firmware_name/version
    libfota2.request(fota_cb)
    return true
end

--[[
@api ota_manegement.check_now(trigger)
@summary 立即发起一次 OTA 检查（不影响 24 小时周期定时器）
@param string trigger 触发来源标识，仅用于日志，可选值如 "PWRKEY"/"MANUAL" 等
@return boolean 是否成功发起（false 表示已有请求在途或未配置 PRODUCT_KEY）
]]
function ota_manegement.check_now(trigger)
    return do_request(trigger or "MANUAL")
end

-- ========== 开机引导 task：等联网 → 首次检查 → 启动 24 小时周期 ==========
local function boot_task()
    log.info("OTA", "boot_task 启动，等待 IP_READY 后开始首次 OTA 检查")
    while not socket.adapter(socket.dft()) do
        log.warn("excloud_task_func", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 5000)
    end
    log.info("OTA", "已联网，等待 " .. ota_manegement.FIRST_CHECK_DELAY_MS .. " ms 让网络稳定...")
    sys.wait(ota_manegement.FIRST_CHECK_DELAY_MS)

    -- ① 开机首次主动获取一次升级
    do_request("BOOT")

    -- ② 启动 24 小时周期定时器（独立于 PWRKEY 短按触发）
    -- 使用 sys.timerLoopStart 循环触发，每 24 小时自动调用一次 do_request("PERIOD")
    period_timer_id = sys.timerLoopStart(function()
        do_request("PERIOD")
    end, ota_manegement.CHECK_INTERVAL_MS)

    log.info("OTA", "周期检查定时器已启动: 每 " .. (ota_manegement.CHECK_INTERVAL_MS / 1000 / 3600) ..
        " 小时一次, timer_id=" .. tostring(period_timer_id))
end

-- ========== PWRKEY 短按监听 task ==========
-- 订阅 mypower.lua 发布的 "PWRKEY_SHORT_PRESS" 全局消息
-- 短按事件独立触发一次 OTA 检查，不影响 24 小时周期定时器
local function pwrkey_listener_task()
    log.info("OTA", "PWRKEY 短按 OTA 监听 task 已启动")
    while true do
        sys.waitUntil("PWRKEY_SHORT_PRESS")
        log.info("OTA", "收到 PWRKEY 短按事件，立即触发 OTA 检查（不影响周期定时器）")
        do_request("PWRKEY")
    end
end

--[[
@api ota_manegement.init()
@summary 初始化 OTA 管理模块（启动开机首次检查 task + 周期定时器 + PWRKEY 短按监听）
@return boolean 始终返回 true
]]
function ota_manegement.init()
    -- 启动开机首次检查 + 周期定时器引导 task
    sys.taskInit(boot_task)
    -- 启动 PWRKEY 短按事件订阅 task
    sys.taskInit(pwrkey_listener_task)
    log.info("OTA", "ota_manegement 初始化完成")
    return true
end

return ota_manegement
