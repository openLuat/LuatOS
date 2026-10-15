--[[
@module  net_guard
@summary 网络注册看护（Air8203：单卡 SIM0 + CD 未接的补偿机制）
@version 1.0（8203 新增）
@date    2026.09.28

=== 为什么需要这个模块 ===
★【已确认 2026-09-28】8203 的 SIM 卡槽：
  · **只支持单卡 SIM0**
  · 卡座的 **CD（在位检测）脚没有接**

因此"卡没插好 / 没插卡 / 注网卡住"这类问题**没有任何硬件信号可用**：
  - sim_slot.lua 的在位检测已被禁用（detect_enable=false）
  - 平台侧只会看到设备一直离线，且现场无人知道原因

本模块就是补这个盲区：**用"能不能注上网"反推卡与网络是否正常**，并给一次重试机会。

=== 看护策略（按现场要求） ===
  1. 上电后先等 **30s**（正常注网通常 5~15s，留足余量，避免误判打断正常注网）
  2. 30s 后仍未注册 → **进出一次飞行模式**（mobile.flymode true → 2s → false），
     相当于给射频/协议栈一次"重新搜网"的机会
  3. 连续 **3 次**仍失败 → 转入**每 30 分钟**再试一次（不再每 30s 折腾）
  4. 一旦注册成功 → 任务**直接退出**，此后不再干预网络（把网络全权交回协议栈）

⚠️ 为什么是"进出飞行"而不是"重启射频"：
   8203 走的是标准 LuatOS 协议栈，mobile.flymode() 是官方提供的重新搜网手段，
   不需要也不应该用 pm 重启等重手段（会连带打断 GNSS/上报业务）。

=== 判据（官方 mobile.status() 返回值） ===
  0 未注册（可能在注网中） ｜ 1 已注册本地网络 ｜ 2 正在搜索 ｜
  3 注册被拒绝 ｜ 4 未知 ｜ 5 已注册漫游网络
  → 只有 1 / 5 才算"有网"
]]

local net_guard = {}

local config = require("config")

-- ==================== 可调参数 ====================
local FIRST_DELAY_MS    = 30000            -- 上电后首次检查的等待时长
local FAST_GAP_MS       = 30000            -- 每次进出飞行后的观察窗口
local MAX_FAST_RETRY    = 3                -- 快速重试上限（超过则转慢重试）
local SLOW_GAP_MS       = 30 * 60 * 1000   -- 慢重试间隔：30 分钟
local FLY_MS            = 2000             -- 停留飞行模式的时长

local state = {
    started     = false,
    online      = false,
    retry_cnt   = 0,     -- 累计"进出飞行"次数
    last_status = nil,   -- 最近一次 mobile.status()
}

--[[
判断当前是否已注册到网络（官方 mobile.status() 语义）。

@return boolean
]]
local function is_online()
    local st = mobile.status()
    state.last_status = st
    return st == 1 or st == 5
end

--[[
进出一次飞行模式（重新搜网）。

依据：官方 mobile.flymode(simid, enable) —— 参数为卡槽号（0 起）与开关；
      它是阻塞 API，内部会等到飞行模式切换完成才返回。
⚠️ 这里操作的是 **SIM0**（8203 单卡，见 board.lua 的 sim 段）。
]]
local function toggle_flymode()
    log.warn("net_guard", "未注册网络 → 进出一次飞行模式（第", state.retry_cnt, "次）")

    local ok1 = mobile.flymode(0, true)     -- 进入飞行模式
    log.info("net_guard", "进入飞行模式:", tostring(ok1))
    sys.wait(FLY_MS)

    local ok2 = mobile.flymode(0, false)    -- 退出飞行模式，重新注网
    log.info("net_guard", "退出飞行模式:", tostring(ok2))

    if not ok1 or not ok2 then
        log.warn("net_guard", "mobile.flymode 返回异常（ok进入=", tostring(ok1),
            " ok退出=", tostring(ok2), "）—— 若本固件不含 mobile 库或卡槽号不是 0，需要修正本模块")
    end
end

--[[
看护主任务。
]]
local function guard_task()
    local gap = config.BOARD and config.BOARD.sim and config.BOARD.sim.boot_default or 0

    log.info("net_guard", string.format(
        "网络看护启动：%ds 后开始检查；未注册则进出飞行模式（最多 %d 次快速重试，间隔 %ds），"
        .. "之后每 %d 分钟重试一次；卡槽 = SIM%d",
        FIRST_DELAY_MS / 1000, MAX_FAST_RETRY, FAST_GAP_MS / 1000, SLOW_GAP_MS / 60000, gap))

    sys.wait(FIRST_DELAY_MS)

    local fast_used = 0
    while true do
        if is_online() then
            state.online = true
            log.info("net_guard", "网络已注册（mobile.status()=", tostring(state.last_status),
                "），看护任务退出，网络交回协议栈自行管理")
            return
        end

        if fast_used < MAX_FAST_RETRY then
            fast_used = fast_used + 1
            state.retry_cnt = state.retry_cnt + 1
            toggle_flymode()
            sys.wait(FAST_GAP_MS)      -- 观察窗口：等它重新注网
        else
            state.retry_cnt = state.retry_cnt + 1
            log.warn("net_guard", "连续", MAX_FAST_RETRY, "次进出飞行仍未注册（最近 status=",
                tostring(state.last_status), "）→ 转入每", SLOW_GAP_MS / 60000,
                "分钟重试一次。请现场检查：SIM0 是否插好 / 是否欠费 / 天线是否接好")

            sys.wait(SLOW_GAP_MS)
            if is_online() then
                state.online = true
                log.info("net_guard", "网络已注册，看护任务退出")
                return
            end
            toggle_flymode()
            sys.wait(FAST_GAP_MS)
        end
    end
end

--[[
启动网络看护（幂等）。

@return boolean 是否本次真正启动了任务
]]
function net_guard.start()
    if state.started then return false end
    state.started = true
    sys.taskInit(guard_task)
    return true
end

--[[
查询看护状态（供排障/日志使用）。
]]
function net_guard.get_status()
    return {
        started     = state.started,
        online      = state.online,
        retry_cnt   = state.retry_cnt,
        last_status = state.last_status,
    }
end

return net_guard
