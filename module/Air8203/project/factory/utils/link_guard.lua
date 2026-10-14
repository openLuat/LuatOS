--[[
@module  link_guard
@summary 云链路自愈看护（工程侧实现）—— 补回合宙官方 excloud 不具备的两个自愈机制
@version 1.0（8203 新增）
@date    2026.09.28

=== 为什么需要这个模块 ===
本工程原先使用 iRTU 定制的 excloud，它在**库内部**内置了两个"链路自愈"机制。
按现场要求改用**合宙官方最新版** excloud 后（AGENTS.md §1.3：官方库不得修改，
官方库没有的能力要在工程侧补），在此把它们补回来：

  ① **复位看门狗自愈**（针对"协议栈死锁"）
     重连失败**且 getip 也失败** → 说明不是服务器问题而是本机协议栈卡死
     → 武装看门狗，10 分钟内恢复不了就主动重启设备；
     带两道保险：**每日限 5 次**（超限降级为 1 小时慢速重连、不再复位）、
     **鉴权失败态**（服务器持续回失败应答时，连接层的"成功"不得解除看门狗，
     防止"断开→重连成功→取消看门狗→又被回失败"的死循环）

  ② **发送失败自愈**（针对"连接假死空转"）
     TCP/UDP 发送失败时不空等，主动断开重连 —— 否则连接会卡在
     "发一次失败一次"的状态一直耗到超时。

=== 为什么能用官方回调实现 ===
官方 excloud 通过 `excloud.on(cb)` 暴露了完整的事件（数据取自官方库触发点）：
  connect_result  {success=bool, error=str}
  disconnect      {} / {error=str}
  reconnect_failed{count=n, max_reconnect=m [, getip_failed=true]}
  send_result     {success=bool, error_msg=str, sequence_num=n}
  auth_result     {success=bool, message=str, sequence_num=n}
  auth_key_error  {error=str}
其中 `reconnect_failed.getip_failed` 正好对应定制版"getip 也失败"的判定条件。

⚠️ `excloud.on()` 是**单回调**（官方实现是 `callback_func = cbfunc`，后注册的会覆盖先注册的），
   所以本模块**不自己调用** excloud.on，而是由 `create.lua` 现有的那一个回调**转发**进来
   （见 create.lua 里 excloud 事件分发处的 `link_guard.on_event(event, data)`）。

=== 与定制版的行为差异（有意为之，避免工程侧做危险动作）===
  · 定制版的"发送失败自愈"是**每次发送失败立即** cleanup+reconnect；
    工程侧无法安全地复用库内部状态，因此改为**连续失败达阈值（默认 3 次）
    且两次主动重连间隔 ≥ 30s** 才触发一次 close→open，防止重连风暴。
  · 定制版的"超限降级"用的是库内部 getip；工程侧改为直接 close→open 重连。
]]

local link_guard = {}

local mtnlog = require("mtnlog")

-- ==================== 复位看门狗参数（照搬 iRTU 定制版 excloud 的内置值） ====================
local WATCHDOG = {
    delay_ms = 10 * 60 * 1000,           -- 武装后 10 分钟触发复位
    daily_limit = 5,                     -- 每日最大复位次数
    fallback_delay_ms = 60 * 60 * 1000,  -- 超限后降级为 1 小时慢速重连
    count_key = "wdt_reboot_count",      -- fskv 键：当日复位计数
    date_key = "wdt_reboot_date",        -- fskv 键：最后复位日期（YYYYMMDD）
}

-- ==================== 发送失败自愈参数 ====================
local SEND_REPAIR = {
    threshold = 3,          -- 连续发送失败达该次数触发主动重连
    window_ms = 2 * 60 * 1000,  -- 失败计数的时间窗（窗内累计，超窗重新计数）
    min_gap_ms = 30 * 1000,     -- 两次主动重连的最小间隔
}

local state = {
    inited       = false,
    transport    = nil,   -- 由 create.lua 告知（tcp/udp/mqtt）
    armed        = false, -- 复位看门狗是否已武装
    auth_failed  = false, -- 鉴权失败态（武装期间连接层的成功不得解除看门狗）
    reboot_timer = nil,
    fallback_timer = nil,
    send_fail_cnt = 0,
    send_fail_start = 0,
    last_repair = 0,
    reboot_cnt = 0,       -- 本进程内触发复位的次数（统计用）
    silent_next = false,  -- 本次发送是否为"静默"（成功时不写运维日志）
}

-- 惰性取官方 excloud（本模块可能在 create.lua 之前加载）
local function get_excloud()
    local ok, m = pcall(require, "excloud")
    if ok and type(m) == "table" then return m end
    return nil
end

-- ==================== 复位看门狗 ====================

-- 读取当日复位计数（fskv 跨复位持久化，按自然日重置）
local function get_today_reboot_count()
    local today = os.date("%Y%m%d") or ""
    local last_date = fskv.get(WATCHDOG.date_key) or ""
    if last_date == today then
        return tonumber(fskv.get(WATCHDOG.count_key)) or 0
    end
    fskv.set(WATCHDOG.date_key, today)
    fskv.set(WATCHDOG.count_key, "0")
    return 0
end

-- 取消复位看门狗（幂等，可重复调用）
local function cancel_watchdog()
    if state.reboot_timer then
        sys.timerStop(state.reboot_timer)
        state.reboot_timer = nil
        log.info("link_guard", "复位看门狗已取消")
    end
    if state.fallback_timer then
        sys.timerStop(state.fallback_timer)
        state.fallback_timer = nil
        log.info("link_guard", "慢速重连定时器已取消")
    end
end

-- 执行复位（复位前自增计数并落盘，延迟 300ms 确保日志与 fskv 刷出）
local function execute_reboot(reason)
    state.reboot_timer = nil
    reason = reason or "重连失败超时"

    local today = os.date("%Y%m%d") or ""
    local count = tonumber(fskv.get(WATCHDOG.count_key)) or 0
    if (fskv.get(WATCHDOG.date_key) or "") ~= today then
        count = 0   -- 跨天保护：武装期间跨天则从 1 重新计数
    end
    count = count + 1
    fskv.set(WATCHDOG.count_key, tostring(count))
    fskv.set(WATCHDOG.date_key, today)
    state.reboot_cnt = state.reboot_cnt + 1

    -- 复位是跨重启事件，必须落盘才能被服务器拉到
    mtnlog.error("watchdog", "看门狗复位触发", "当日第", count, "次", "原因", reason)
    link_guard.flush_mtn_log()

    log.error("link_guard", "看门狗触发，执行设备复位（当日第 " .. count .. " 次，原因: " .. reason .. "）")
    sys.timerStart(rtos.reboot, 300)
end

-- 武装复位看门狗：delay_ms 内无法恢复则复位；每日限次，超限降级为慢速重连
local function arm_watchdog(reason)
    reason = reason or "重连失败超时"
    cancel_watchdog()

    local count = get_today_reboot_count()
    if count >= WATCHDOG.daily_limit then
        -- ★ 照搬定制版：超限时**不再复位**，降级为每 1 小时主动重连一次
        log.warn("link_guard", "复位看门狗已达当日上限 " .. count .. "/" .. WATCHDOG.daily_limit ..
            "，降级为 " .. (WATCHDOG.fallback_delay_ms / 60000) .. " 分钟慢速重连（不再复位）")
        state.fallback_timer = sys.timerLoopStart(function()
            log.warn("link_guard", "慢速重连：主动 close→open 重连一次")
            link_guard.repair_connection("看门狗超限降级慢速重连", true)
        end, WATCHDOG.fallback_delay_ms)
        return
    end

    state.armed = true
    state.reboot_timer = sys.timerStart(execute_reboot, WATCHDOG.delay_ms, reason)
    log.warn("link_guard", "复位看门狗已武装：若 " .. (WATCHDOG.delay_ms / 60000) ..
        " 分钟内无法恢复（原因: " .. reason .. "），将复位设备（当日第 " .. (count + 1) .. " 次）")
end

-- 解除鉴权失败态（服务器回成功应答时调用）：清状态并取消看门狗
local function clear_auth_failed()
    state.auth_failed = false
    state.armed = false
    cancel_watchdog()
    log.info("link_guard", "鉴权失败态已解除，复位看门狗取消")
end

-- 鉴权失败武装。
-- ★ 关键（照搬定制版）：持续收到失败应答时**不重置 10 分钟倒计时**（从首次失败起算），
--   否则设备每 10 秒上报一次、每次都被回失败 → 倒计时无限顺延 → 永不复位。
local function arm_on_auth_fail(detail)
    if state.auth_failed then
        log.warn("link_guard", "鉴权失败持续中（", tostring(detail), "），复位看门狗已武装，不重置倒计时")
        mtnlog.warn("auth", "鉴权失败持续", "不重置倒计时", "detail", tostring(detail))
        return
    end

    state.auth_failed = true
    mtnlog.error("auth", "鉴权失败触发复位看门狗", "detail", tostring(detail),
        "10分钟后复位", "当日限次", WATCHDOG.daily_limit)
    arm_watchdog("服务器鉴权失败")
end

-- ==================== 发送失败自愈 ====================

--[[
主动重连（close → 短暂等待 → open）。

@param string reason 触发原因（写日志用）
@param boolean force  true=跳过最小间隔限流（看门狗降级慢速重连时用）
@return boolean 是否真的执行了重连
]]
function link_guard.repair_connection(reason, force)
    -- 仅 TCP/UDP 需要：MQTT publish 失败属 QoS 语义，不强制重连（与定制版一致）
    if state.transport == "mqtt" then
        return false
    end

    local now = mcu.ticks()
    if not force and (now - state.last_repair) < SEND_REPAIR.min_gap_ms then
        log.warn("link_guard", "距上次主动重连不足 " .. (SEND_REPAIR.min_gap_ms / 1000) ..
            "s，本次跳过（原因: " .. tostring(reason) .. "）")
        return false
    end
    state.last_repair = now

    local excloud = get_excloud()
    if not excloud then
        log.warn("link_guard", "excloud 不可用，无法主动重连")
        return false
    end

    log.error("link_guard", "发送持续失败，主动断开并重连（原因: " .. tostring(reason) .. "）")
    mtnlog.error("socket", "发送持续失败，主动断开重连", "原因", tostring(reason))

    sys.taskInit(function()
        pcall(excloud.close)
        sys.wait(200)
        pcall(excloud.open)
    end)
    return true
end

-- 记录一次发送失败，达到阈值则触发自愈
local function on_send_failed(err_msg)
    local now = mcu.ticks()
    if state.send_fail_cnt == 0 or (now - state.send_fail_start) > SEND_REPAIR.window_ms then
        state.send_fail_cnt = 1
        state.send_fail_start = now
    else
        state.send_fail_cnt = state.send_fail_cnt + 1
    end

    mtnlog.error("send", "上报失败", "原因", tostring(err_msg),
        "连续失败", state.send_fail_cnt .. "/" .. SEND_REPAIR.threshold)

    if state.send_fail_cnt >= SEND_REPAIR.threshold then
        link_guard.repair_connection("连续发送失败 " .. state.send_fail_cnt .. " 次")
        state.send_fail_cnt = 0
    end
end

-- ==================== 对外接口 ====================

--[[
转发官方 excloud 的回调事件（由 create.lua 的那一个 excloud.on 回调调用）。

@param string event 事件名
@param table  data  事件数据
]]
function link_guard.on_event(event, data)
    data = data or {}

    if event == "connect_result" then
        if data.success then
            -- getip/连接成功说明服务端可达 → 解除看门狗
            -- ★ 但鉴权失败态除外：TCP 通不代表鉴权恢复，否则会形成
            --   "服务器断开 → 重连成功 → 取消看门狗 → 又收到失败应答" 的死循环
            if not state.auth_failed then
                state.armed = false
                cancel_watchdog()
            else
                log.warn("link_guard", "连接成功但处于鉴权失败态，保持复位看门狗武装")
            end
        else
            log.warn("link_guard", "连接失败:", tostring(data.error))
        end

    elseif event == "reconnect_failed" then
        if data.getip_failed then
            -- ★ 官方版用 getip_failed 标志表达"getip 也失败"，正是定制版里
            --   "协议栈死锁兜底" 的判定条件
            arm_watchdog("重连失败且 getip 不可达（协议栈死锁兜底）")
        else
            log.warn("link_guard", "重连失败 count=", tostring(data.count),
                "/", tostring(data.max_reconnect), "（库内仍会自动重连，暂不干预）")
        end

    elseif event == "auth_result" then
        if data.success then
            if state.auth_failed then clear_auth_failed() end
        else
            arm_on_auth_fail("auth_reply=" .. tostring(data.message))
        end

    elseif event == "auth_key_error" then
        arm_on_auth_fail("未能获取到auth_key")

    elseif event == "send_result" then
        -- ★ 补回定制版行为：把"上报结果"写入运维日志。
        --   官方 excloud 的 send 内部**完全不写**运维日志（既不写成功也不写失败），
        --   而定制版会写，并额外提供 silent 参数让调用方跳过"成功"那条（保活帧用它避免刷屏）。
        if data.success then
            if not state.silent_next then
                mtnlog.info("send", "上报成功", "序号", tostring(data.sequence_num or ""))
            end
            state.send_fail_cnt = 0
        else
            -- 失败一律记录（与定制版一致：silent 只跳过"成功"记录）
            on_send_failed(data.error_msg)
        end
    end
end

--[[
统一的上行发送入口：转发给**官方** `excloud.send`，并在工程侧补回"静默发送"语义。

背景：合宙官方 excloud.send 的签名是 `send(data, need_reply, is_auth_msg)` —— **只有 3 个参数**，
第 4 个 silent 参数是 iRTU 定制版的扩展（成功时不写运维日志）。
工程侧无法干预官方库内部的日志写入，但**可以在自己的回调里决定写不写** ——
本函数就通过一个瞬时标志把 silent 语义完整复现出来：

  · 官方 send 内部是**同步**触发 `send_result` 回调的（库代码里 callback_func 紧跟发送结果），
    所以 `silent_next` 标志在回调发生时一定有效，返回后立即清除。

@param table   data        本次要发送的数据（同官方）
@param boolean need_reply  是否需要回执（同官方）
@param boolean is_auth_msg 是否鉴权消息（同官方）
@param boolean silent      可选。true = **成功时**不写运维日志（失败仍会记录）
@return boolean, string    同官方 excloud.send
]]
function link_guard.send(data, need_reply, is_auth_msg, silent)
    local excloud = get_excloud()
    if not excloud or type(excloud.send) ~= "function" then
        return false, "excloud unavailable"
    end

    state.silent_next = silent and true or false
    local ok, err = excloud.send(data, need_reply, is_auth_msg)
    state.silent_next = false   -- 兜底清除（正常路径下 flag 已在回调里被消费）
    return ok, err
end

--[[
工程主动 close 云连接时调用：清除鉴权失败态并解除看门狗，
避免后台定时器泄漏或在主动维护期间误复位。
]]
function link_guard.on_manual_close()
    state.auth_failed = false
    state.armed = false
    cancel_watchdog()
end

--[[
尽力把运维日志落盘（复位前调用，保证"看门狗复位"这条日志能被服务器拉到）。

⚠️ 定制版此处调用 `exmtn.flush()`，但官方 exmtn 没有该接口。
   补偿手段见 `utils/mtnlog.lua` 的 `mtnlog.flush()` 说明：
   真正需要"每条立即落盘"时应改用 MTN_LOG_ADD_WRITE 模式，而不是改库。
]]
function link_guard.flush_mtn_log()
    return mtnlog.flush()
end

--[[
初始化（幂等）。由 create.lua 在建立云连接前调用。

@param string transport "tcp" / "udp" / "mqtt"
]]
function link_guard.start(transport)
    if state.inited then
        state.transport = transport or state.transport
        return true
    end
    state.inited = true
    state.transport = transport

    log.info("link_guard", "链路自愈看护已启动（transport=", tostring(transport),
        "，看门狗:", WATCHDOG.delay_ms / 60000, "分钟/当日限", WATCHDOG.daily_limit, "次）")
    return true
end

function link_guard.get_status()
    return {
        inited        = state.inited,
        transport     = state.transport,
        armed         = state.armed,
        auth_failed   = state.auth_failed,
        send_fail_cnt = state.send_fail_cnt,
        reboot_cnt    = state.reboot_cnt,
        today_reboot  = get_today_reboot_count(),
        daily_limit   = WATCHDOG.daily_limit,
    }
end

return link_guard
