--[[
@module  battery
@summary 电池管理模块
@version 4.1
@date    2026.09.08
@usage
本模块的核心功能为：
1. 通过 YHM2712A 充电管理IC（exs_yhm2712a.status()）获取电池电压与充电状态
2. 同时提供充电阶段/电池在位/充电器在位/IC过热等完整状态
3. 后台任务周期轮询刷新缓存，对外接口全部非阻塞（读缓存）
4. V004.000.040 起：充电中电压可信门控——VBAT 系统轨在充电器在位时会被充电IC抬升，
   除以折算系数后仍可能产生 4.12V 假值；本模块以"最近可信基准"限制充电中单步变化，
   拒绝轨道电压污染缓存，杜绝假值被反复上报（预充/涓流阶段保留脏值问题一并根治）

硬件说明（依据 exs_yhm2712a v1.3 / 202608251200）：
- 本硬件无 VBUS 检测脚，充电器在位由充电IC的 FSM_MODE 判定，不能 GPIO 直读
- 电池电压仅在特定充电阶段可测：预充(1)/涓流(2)阶段不测量（返回-1），
  恒流(3)/恒压(5)阶段开电压跟随测量，充电完成(7)/放电(0)直接测

阻塞说明：
- exs_yhm2712a.status() 单次调用阻塞可达 20s（内部电池在位检测 50×100ms 循环），
  绝不能在 10s 上报循环里同步调用；本模块由后台任务轮询，业务侧只读缓存
]]

local battery = {}
local config = require "config"

-- 惰性加载充电IC驱动（require 有缓存，与 charge.lua 拿到同一实例）
local exs_yhm2712a_ok, exs_yhm2712a = pcall(require, "exs_yhm2712a")

-- 电池状态（由后台轮询任务更新，业务侧只读）
local battery_state = {
    voltage = 0,               -- 电池电压（mV），0=尚未获取到
    level = 100,               -- 电池电量（%）
    charging = false,          -- 充电状态（充电器在位即充电中，含充满未拔，与原VBUS语义一致）
    last_check_time = 0,       -- 最近一次成功获取状态的时间（os.time）
    charge_stage = -1,         -- 充电阶段：0放电/1预充/2涓流/3恒流/5恒压/7完成/8未知
    charge_complete = false,   -- 充电完成（电池在位且阶段=7）
    battery_present = true,    -- 电池在位
    charger_present = false,   -- 充电器在位（FSM_MODE判定）
    ic_overheat = false,       -- 充电IC过热（>120℃）
}

-- 最近一次"可信"电池电压（mV），nil=尚无可信基准（V004.000.040）
-- 未充电时的实测、充电中连续缓升的实测都会刷新它；充电中跳变(疑似系统轨污染)只拒绝不刷新
local ref_voltage = nil

-- 充电阶段名称（日志用）
local STAGE_NAME = {
    [0] = "放电", [1] = "预充", [2] = "涓流", [3] = "恒流",
    [5] = "恒压", [7] = "充电完成", [8] = "未知",
}

-- 计算电池电量百分比
-- @param voltage_mv 电池电压(mV)
-- @return number 电量百分比(0-100)
local function calculate_level(voltage_mv)
    local full = config.BATTERY_CONFIG.FULL_VOLTAGE or 4200
    local empty = config.BATTERY_CONFIG.LOW_VOLTAGE or 3300

    if voltage_mv >= full then return 100 end
    if voltage_mv <= empty then return 0 end

    return math.floor((voltage_mv - empty) / (full - empty) * 100)
end

-- 从充电IC读取状态并更新缓存（阻塞，最长约20s，必须在task中运行）
-- @return boolean status.result 是否为 true（IC通信与各项检测均成功）
local function refresh_from_charger_ic()
    if not exs_yhm2712a_ok or not exs_yhm2712a then
        return false
    end

    local ok, status = pcall(exs_yhm2712a.status)
    if not ok or type(status) ~= "table" then
        log.warn("battery", "exs_yhm2712a.status 调用异常:", status)
        return false
    end

    local prev_charging = battery_state.charging

    -- 充电状态：充电器在位即视为充电中（含充满未拔，与原 VBUS 语义一致）
    battery_state.charger_present = status.charger_present and true or false
    battery_state.charging = battery_state.charger_present
    battery_state.charge_complete = status.charge_complete and true or false
    battery_state.battery_present = status.battery_present and true or false
    battery_state.ic_overheat = status.ic_overheat and true or false
    battery_state.charge_stage = status.charge_stage or 8

    -- 电池电压：充电中"系统轨污染"可信门控（V004.000.040）
    -- 背景：VBAT 轨在充电器在位时会被充电IC抬升（~4.1V 级，驱动注释 Vsys=1.03×Vreg≈4.12V），
    --       除以折算系数后仍可能产生 4.12V 假值；且预充/涓流阶段驱动返回 -1 会把脏旧值保留反复上报。
    -- 规则：
    --   * 未充电：轨=电芯，2200~4800mV 直接可信 → 接受并刷新可信基准
    --   * 充电中预充/涓流(1/2)或不可测(-1/-2/-3)：不更新（保留可信基准值，防脏值续传）
    --   * 充电中可测(0/3/5/7)：与可信基准差 ≤ CHARGING_MAX_STEP_MV 视为缓充合理 → 接受；
    --     单步跳变超阈值 → 判系统轨污染，拒绝更新并告警（避免一次污染持续保留）
    --   * 无基准时的充电首采：仅接受恒流/恒压(3/5)读数（该分支驱动开 SYS_TRACK 电压跟随测量）
    local v = status.vbat_voltage
    local charging_now = battery_state.charging
    local filter = config.BATTERY_RELIABILITY or {}
    local accept = false
    if type(v) == "number" and v >= 2200 and v <= 4800 then
        if not charging_now then
            accept = true                          -- 未充电：读到的就是电芯电压
        elseif filter.ENABLE == false then
            accept = true                          -- 防护关闭：保持原行为
        elseif battery_state.charge_stage == 1 or battery_state.charge_stage == 2 then
            accept = false                         -- 预充/涓流：保留基准（驱动正常时此阶段返回 -1）
        elseif ref_voltage then
            -- 有可信基准：限制单步变化幅度，遏制轨电压瞬间污染
            accept = math.abs(v - ref_voltage) <= (filter.CHARGING_MAX_STEP_MV or 400)
        else
            -- 无基准的充电首采：仅接受恒流/恒压阶段（SYS_TRACK 跟随语义）且落在电芯合理窗口内
            -- （≤3900mV：真实电芯充电初值不会凭空跳到 4V 级；≥2200 由外层过滤保证）
            accept = (battery_state.charge_stage == 3 or battery_state.charge_stage == 5)
                and v <= (filter.CHARGING_FIRST_READ_MAX_MV or 3900)
        end
        if accept then
            battery_state.voltage = v
            battery_state.level = calculate_level(v)
            ref_voltage = v
        elseif charging_now and ref_voltage and v > ref_voltage
            and not (battery_state.charge_stage == 1 or battery_state.charge_stage == 2) then
            -- 有基准但跳变超限且为"上升"（3.2V→4.12V 典型轨污染形态），拒绝并告警便于现场对日志
            log.warn("battery", "充电中电压读数异常(疑似系统轨污染):", v,
                "mV, 可信基准:", ref_voltage, "mV, 拒绝更新, 阶段:", battery_state.charge_stage,
                ", 充电:", tostring(charging_now))
        end
    end
    battery_state.last_check_time = os.time()

    log.debug("battery", "电压:", battery_state.voltage, "mV, 电量:", battery_state.level,
        "%, 阶段:", STAGE_NAME[battery_state.charge_stage] or tostring(battery_state.charge_stage),
        ", 充电:", battery_state.charging, ", 充满:", battery_state.charge_complete,
        ", 电池在位:", battery_state.battery_present)

    -- 充电状态变化时发布事件（tools.lua LED 状态机 / 充电60s上报间隔依赖）
    if battery_state.charging and not prev_charging then
        log.info("battery", "充电器已插入，开始充电")
        sys.publish("CHARGING_START")
    elseif not battery_state.charging and prev_charging then
        log.info("battery", "充电器已拔出，停止充电")
        sys.publish("CHARGING_STOP")
    end

    return status.result == true
end

-- 后台轮询任务：等待充电IC setup 完成后周期性刷新状态
local function battery_poll_task()
    local poll_ms = config.BATTERY_CONFIG.STATUS_POLL_MS or 30000

    -- 开机先等一会：charge.init() 的 setup+start 也在并行 task 中执行（约3s），
    -- YHM2712A 的 CMD 是单总线，必须避开与初始化通信的并发冲突
    sys.wait(5000)

    -- 启动阶段快速重试，直到首次成功（setup 尚未完成时 status() 会快速返回失败）
    while refresh_from_charger_ic() ~= true do
        sys.wait(5000)
    end
    log.info("battery", "充电IC状态首次获取成功，进入周期轮询（", poll_ms / 1000, "秒/次）")

    while true do
        sys.wait(poll_ms)
        refresh_from_charger_ic()
    end
end

-- 初始化电池管理模块
function battery.init()
    log.info("battery", "电池管理模块初始化（数据源：YHM2712A 充电IC exs_yhm2712a.status）")
    if not exs_yhm2712a_ok then
        log.error("battery", "加载 exs_yhm2712a 失败，电池状态将不可用")
        return
    end
    sys.taskInit(battery_poll_task)
    log.info("battery", "电池管理模块初始化完成")
end

-- 获取电池数据（读缓存，非阻塞；刷新由后台轮询任务负责）
-- @return table 包含电压/电量/充电状态/充电阶段等
function battery.get_data()
    return {
        voltage = battery_state.voltage,
        level = battery_state.level,
        charging = battery_state.charging,
        last_check_time = battery_state.last_check_time,
        charge_stage = battery_state.charge_stage,
        charge_complete = battery_state.charge_complete,
        battery_present = battery_state.battery_present,
        charger_present = battery_state.charger_present,
        ic_overheat = battery_state.ic_overheat,
    }
end

-- 获取电池电量
-- @return number 电量百分比（0-100）
function battery.get_level()
    return battery_state.level
end

-- 获取电池电压
-- @return number 电池电压（mV），0=尚未获取到
function battery.get_voltage()
    return battery_state.voltage
end

-- 获取充电状态
-- @return boolean true=充电器在位（充电中，含充满未拔）
function battery.is_charging()
    return battery_state.charging
end

-- 获取充电阶段
-- @return number 0放电/1预充/2涓流/3恒流/5恒压/7完成/8未知，-1=尚未获取
function battery.get_charge_stage()
    return battery_state.charge_stage
end

-- 兼容旧接口：原为强制重新采样并阻塞返回，现改为直接返回当前缓存。
-- 原因：exs_yhm2712a.status() 单次调用阻塞可达 20s，不能放进 10s 上报循环；
-- 数据新鲜度由后台轮询任务保证（默认 30s 刷新一次，插拔充电器检测延迟上限即为此值）。
function battery.force_check()
    return battery.get_data()
end

return battery
