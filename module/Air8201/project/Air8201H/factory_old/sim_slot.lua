--[[
@module  sim_slot
@summary SIM 卡槽在位检测与热插拔切换（SIM0 优先，拔出回落 SIM1）
@version 1.0
@date    2026.09.17
@usage
需求（用户确认）：
1. 开机先读检测脚电平：高 → 启动 SIM0；低 → 启动 SIM1
2. 随后把该脚配为中断：
   - 下降沿 = SIM0 拔出 → 进出一次飞行模式 → 切到 SIM1
   - 上升沿 = SIM0 插入 → 进出一次飞行模式 → 切回 SIM0

★ 时序处理（2026-09-17 实机教训）：
  开机瞬间的读数不可靠（引脚配置刚下发、SIM 供电未稳定），且**可能读到"错误但非 nil"的电平**，
  这类错误不会产生边沿、热插拔中断无法纠正。故本模块采用：
    · 开机：仅打印即时读数，**不用它决策**；先按 profile 的 boot_default 选卡（尽早下发 mobile.simid）
    · 开机后延迟（默认 500ms/1500ms 两轮）：以延迟读数为**最终判据**，与当前卡槽不一致则正式切卡

硬件依据（合宙官网）：
- 「Air780EHV SIM 卡电路设计说明」明确：USIM_DET 脚的常量为 **gpio.WAKEUP2**，
  官方热插拔示例即用该脚 + `gpio.debounce(...,500)` + `gpio.setup(pin, cb)`，
  拔卡进飞行模式、插卡"先进后出"飞行模式（等效重新注册网络）。
- 「mobile 蜂窝通信功能」明确三条硬约束：
  ① `mobile.simid()` 与 `mobile.flymode()` **不能同时使用，必须错开**；
  ② **切卡前必须退出飞行模式**（simid 内部会自动进出飞行，若当前已在飞行模式会因状态冲突失败）；
  ③ 切卡后**必须延时再读**卡槽（官方示例 `sys.wait(3000)`），设置返回值不可依赖。

引脚分配（硬件确认，三型号 SIM 检测脚与 G-Sensor 中断脚互不冲突，无需仲裁）：
  Air8202  SIM0 检测 = gpio.WAKEUP0  ｜ G-Sensor 中断 = gpio.WAKEUP2
  Air8201G SIM0 检测 = gpio.WAKEUP2  ｜ G-Sensor 中断 = GPIO20
  Air8201H SIM0 检测 = gpio.WAKEUP2  ｜ G-Sensor 中断 = gpio.WAKEUP0
各型号的检测脚引脚号由 board.profile.sim.det_pin 提供，业务层不感知板型。

对外接口：
  sim_slot.init()          开机识别电平 → 选定卡槽 → 注册热插拔中断（同步、无 sys.wait）
  sim_slot.get_state()     返回 {current, target, sim0_present, boot_slot, switching}
]]

local sim_slot = {}

local config = require "config"

-- 板级配置（board.profile.sim）
local CFG = (config.BOARD and config.BOARD.sim) or {}

local SLOT_SIM0, SLOT_SIM1 = 0, 1   -- 官方：0=SIM0(第一张卡) / 1=SIM1(第二张卡)

-- 飞行模式编号：工程内既有做法（create.lua）对双卡模块同时操作 0/1 两路
local FLY_INDEXES = { 0, 1 }

-- 状态
local state = {
    current = nil,      -- 当前生效卡槽（0/1），nil=尚未确定
    target = nil,       -- 期望卡槽
    sim0_present = nil, -- SIM0 是否在位（开机电平判据）
    boot_slot = nil,    -- 开机选定卡槽（日志用）
    switching = false,  -- 是否正在切换（切换期间新事件只记录不并发执行）
}

-- 待处理的 SIM0 在位状态（true=插入 / false=拔出 / nil=无事件）
-- 中断上下文只置此标志 + publish，真正的切换在任务里串行执行
local pending = nil

--[[
读 SIM0 检测脚的物理电平

⚠️ 前置条件（官网《GPIO》原文）：
   "当管脚为输入模式或中断, 才能通过 gpio.get() 获取到电平"
   → 调用本函数前，该脚必须已由 gpio.setup() 配为输入/中断模式。
   本工程曾因"先读电平、后配中断"的顺序错误，导致开机首次读数为 nil →
   错误回落到默认卡槽 SIM1 → 插在 SIM0 的卡始终不被选中（实机已复现）。

@return boolean|nil true=SIM0 在位, false=拔出, nil=读取失败
@return number|nil  原始电平（排障用，用于标定 present_level 的极性）
]]
local function read_sim0_present()
    local lvl = gpio.get(CFG.det_pin)
    return lvl == (CFG.present_level or 1), lvl
end

-- 中断回调：仅判定"SIM0 是否在位"并发布事件，禁止在此做阻塞操作
-- （flymode / simid 均为阻塞调用且会挂起 Lua 进程，不能放在中断上下文）
-- @param val 触发边的指示值（官方口径：0=下降沿, 1=上升沿）。
--            注意：边值与该次跳变后的新电平数值一致，因此同样可用
--            present = (val == present_level) 判定；此处优先用 gpio.get 取真实电平，
--            读失败时回退到 val，避免依赖不同固件版本的 val 语义。
local function on_det_change(val)
    local present = read_sim0_present()
    if present == nil then
        present = (val == (CFG.present_level or 1))
    end

    -- 去重：与"最新已知状态"一致则忽略（机械触点抖动会产生重复边沿）
    -- 最新已知状态优先取待处理值：同一处理周期内的连续变化（如快速拔插）不会被误丢
    local last = pending
    if last == nil then last = state.sim0_present end
    if last ~= nil and last == present then
        return
    end

    pending = present
    log.info("sim_slot", "SIM0 检测脚变化: val=", tostring(val),
        " → SIM0", present and "在位" or "拔出")
    sys.publish("SIM_DET_CHANGE")
end

-- 飞行模式切换（双卡模块两路一起操作，与 create.lua 既有做法一致）
local function fly_all(enable)
    for _, idx in ipairs(FLY_INDEXES) do
        local ok, err = pcall(mobile.flymode, idx, enable)
        if not ok then
            log.debug("sim_slot", "flymode", idx, enable, "调用异常:", tostring(err))
        end
    end
end

--[[
执行一次"卡槽切换"（必须在任务中调用，含多次阻塞等待）

严格遵循官网约束的执行顺序：
  1) 先确保两路都退出飞行模式（切卡前必须不在飞行模式，否则 simid 会因状态冲突失败）
  2) 进出一次飞行模式（用户要求：插拔均重注册网络；与官方热插拔示例的"先进后出"一致）
  3) 调 mobile.simid(target) 切卡
  4) 延时后再读回确认（官方：立即读会拿到旧值，设置返回值不可依赖）
]]
local function switch_slot(target, sim0_present)
    state.switching = true
    state.target = target

    log.info("sim_slot", "开始切换: SIM0", sim0_present and "在位" or "拔出",
        "→ 目标卡槽 SIM" .. target)

    -- 1) 确保退出飞行模式（关键前置条件）
    fly_all(false)
    sys.wait(CFG.fly_off_ms or 1000)

    -- 2) 进出一次飞行模式
    fly_all(true)
    sys.wait(CFG.fly_on_ms or 1000)
    fly_all(false)
    sys.wait(CFG.fly_off_ms or 1000)

    -- 3) 切卡（底层会自行进出飞行模式完成通道切换）
    local ok, err = pcall(mobile.simid, target)
    if not ok then
        log.error("sim_slot", "mobile.simid 调用异常:", tostring(err))
    end

    -- 4) 延时后读回（官方口径）
    sys.wait(CFG.switch_wait_ms or 3000)
    local now = nil
    do
        local ok2, cur = pcall(mobile.simid)
        if ok2 and type(cur) == "number" then now = cur end
    end

    if now == nil or now == -1 then
        -- -1 = 获取失败或目标卡槽未插卡：保留期望值，后续有插拔事件会再次纠正
        state.current = target
        log.warn("sim_slot", "切卡后读取卡槽失败或目标卡槽无卡(now=", tostring(now),
            ")，暂按 SIM" .. target .. " 记录")
    else
        state.current = now
        log.info("sim_slot", "卡槽切换完成，当前生效 SIM" .. now)
    end

    state.switching = false
end

--[[
开机后延迟确认卡槽（★ 避开上电时序问题）

为什么必须做：
  `sim_slot.init()` 是同步执行的 —— 既不能 sys.wait（非协程上下文），
  且 mobile.simid() 需要尽早下发。因此开机那次读数是在"刚下发引脚配置"之后立刻进行的，
  此时引脚可能尚未真正切到输入/中断态、SIM 卡供电也可能未稳定。后果有两类：
    ① 读失败（返回非数值）→ 回落默认卡槽；
    ② **读到一个"错误但非 nil"的电平**（如尚未切输入态时 gpio.get 恒为 0）
       → 判成"SIM0 不在位" → 选 SIM1。这一类最危险：电平稳定、不产生边沿，
         热插拔中断也不会纠正，表现为"插在 SIM0 的卡永久不识别，拔插也无反应"。

做法：
  **无论开机读数成功与否**，都在开机后延迟复检（默认 500ms / 1500ms 两轮），
  以延迟读数为最终判据；若与当前卡槽不一致，执行一次正式切卡。
]]
local function confirm_slot_later()
    for _, delay in ipairs(CFG.confirm_delays_ms or { 500, 1500 }) do
        sys.wait(delay)

        local present = read_sim0_present()
        if present == nil then
            log.warn("sim_slot", "延迟确认(", delay, "ms)：检测脚仍不可读，继续等待")
        else
            state.sim0_present = present
            local target = present and SLOT_SIM0 or SLOT_SIM1
            log.info("sim_slot", "延迟确认(", delay, "ms): SIM0", present and "在位" or "拔出",
                "→ 目标卡槽 SIM" .. target, "（开机决策 SIM" .. tostring(state.boot_slot) .. "）")

            if target ~= state.current then
                switch_slot(target, present)
            end
            return   -- 读到有效电平即完成确认
        end
    end

    log.warn("sim_slot", "延迟确认全部失败，保持开机卡槽 SIM" .. tostring(state.current),
        "（此后插拔卡片会触发中断纠正）")
end

-- 热插拔处理任务：串行执行切换，切换期间到来的新事件只记录（保留最新状态）
local function sim_task()
    log.info("sim_slot", "热插拔处理任务启动")
    while true do
        sys.waitUntil("SIM_DET_CHANGE", 60000)
        local p = pending
        pending = nil
        if p ~= nil then
            local target = p and SLOT_SIM0 or SLOT_SIM1
            if state.switching then
                -- 理论上不会走到（切换期间新事件已重新置 pending），保守兜底
                pending = p
                log.warn("sim_slot", "切换进行中，事件延后处理")
            elseif state.current == target then
                state.sim0_present = p
                log.info("sim_slot", "SIM0", p and "插入" or "拔出",
                    "，当前已在 SIM" .. target .. "，无需切换")
            else
                state.sim0_present = p
                switch_slot(target, p)
            end
        end
    end
end

--[[
开机初始化（同步，禁止 sys.wait）

流程（★ 顺序不可颠倒）：
  ① 先 gpio.debounce + gpio.setup 把检测脚配成"中断模式"（等价于输入模式）
  ② 再读电平定卡槽
  ③ mobile.simid 选卡
  ④ 启动热插拔处理任务

★ 为什么必须先配脚后读数：
  官网《GPIO》明确"当管脚为输入模式或中断, 才能通过 gpio.get() 获取到电平"。
  若先读后配，开机首次 gpio.get 必然失败 → 回落默认卡槽 → 插在 SIM0 的卡不被选中。
  （2026-09-17 实机复现：日志 "SIM0 检测脚读取失败，使用默认卡槽 SIM1"）
]]
function sim_slot.init()
    local slot = CFG.boot_default or SLOT_SIM1
    local lvl_str = "未检测"

    -- 检测是否启用（gpio 是核心库，无需判断是否存在/是否支持）
    local det_ok = CFG.detect_enable and CFG.det_pin ~= nil

    -- ===== ① 先配置检测脚（中断模式 + 防抖）=====
    -- 检测脚上下拉：默认**使用内部上拉**
    -- 依据【官网-GPIO】：
    --   ① "所有 WAKEUP 中断与 GPIO 中断…支持软件配置内部上下拉，也支持取消内部上下拉改用外部上下拉"；
    --   ② "WAKEUP 悬空时电压 ≥1.3V 均属正常…若外部高电平可能把 WAKEUP 拉到 1.3V 以下，必须外加（内部或外部）上拉"；
    --   ③ 【官网-DESIGN】"Wakeup IO 不要用 VDD_EXT 或普通 GPIO 上拉"（否则休眠高脉冲会误触发中断→无法休眠）。
    --   → 内部上拉同时满足"确保电平门限"与"不借用 VDD_EXT"两条要求。
    -- profile 可用 sim.det_pull 覆盖：填 gpio.PULLDOWN 等常量；填 false 表示不指定（完全用硬件默认）。
    local pull
    if det_ok then
        gpio.debounce(CFG.det_pin, CFG.debounce_ms or 500)

        pull = CFG.det_pull
        if pull == nil then pull = gpio.PULLUP end

        if pull == false then
            gpio.setup(CFG.det_pin, on_det_change, nil, gpio.BOTH)
        else
            gpio.setup(CFG.det_pin, on_det_change, pull, gpio.BOTH)
        end
        log.info("sim_slot", "SIM0 检测脚已配置（pin=", CFG.det_pin,
            "防抖=", CFG.debounce_ms or 500, "ms，双边沿，上下拉=",
            pull == false and "硬件默认" or tostring(pull), "）")
    end

    -- ===== ② 开机即时读数（★ 仅供参考，不作为选卡判据） =====
    -- ⚠️ 开机瞬间引脚配置可能尚未生效、SIM 卡供电也可能未稳定，此时读数不可信：
    --    既可能读失败，也可能读到一个"错误但非 nil"的电平（尚未切到输入/中断态时可能恒为 0）。
    --    若据此选卡，会把"卡在 SIM0"误判为不在位 → 选 SIM1；而该电平是稳定的、不产生边沿，
    --    热插拔中断同样不会纠正 → 表现为"插卡永久不识别、拔插无反应"。
    -- 因此这里**只打印、不决策、也不写入 state.sim0_present**（避免污染后续去重状态）；
    -- 实际选卡先用 profile 的 boot_default，由 confirm_slot_later() 在开机后延迟复检，
    -- 以延迟读数为最终判据并自动纠正。
    if det_ok then
        local present, raw = read_sim0_present()
        if present == nil then
            log.warn("sim_slot", "开机即时读数不可用（时序未稳），先用兜底卡槽 SIM" .. slot)
        else
            lvl_str = string.format("开机即时读数 原始电平=%s（仅供参考，稍后延迟复检为准）",
                tostring(raw))
        end
    else
        log.info("sim_slot", "SIM 在位检测未启用，固定使用 SIM" .. slot)
    end

    -- ===== ③ 选卡：必须在任何联网动作（FOTA/驻网/云连接）之前完成 =====
    -- 注意：官方明确"设置后立即读回可能拿到旧值"，此处不同步读回，仅记录决策
    local ok, err = pcall(mobile.simid, slot)
    if not ok then
        log.error("sim_slot", "mobile.simid 调用异常:", tostring(err))
    end
    state.current = slot
    state.target = slot
    state.boot_slot = slot
    log.info("sim_slot", "开机卡槽选择: SIM" .. slot .. "（检测脚", tostring(CFG.det_pin),
        " ", lvl_str, "）")

    -- ===== ④ 开机后延迟确认卡槽（避开上电时序，见 confirm_slot_later 说明） =====
    -- 无论开机读数是否成功都执行：开机瞬间的读数可能是"错误但非 nil"的，
    -- 这种情况不会产生边沿，只能靠延迟复检纠正。
    sys.taskInit(confirm_slot_later)

    -- ===== ⑤ 启动热插拔处理任务 =====
    if not state.task_on then
        state.task_on = true
        sys.taskInit(sim_task)
    end

    return slot
end

-- 获取当前状态（诊断/日志用）
function sim_slot.get_state()
    return {
        current = state.current,
        target = state.target,
        sim0_present = state.sim0_present,
        boot_slot = state.boot_slot,
        switching = state.switching,
        detect_enable = CFG.detect_enable == true,
    }
end

return sim_slot
