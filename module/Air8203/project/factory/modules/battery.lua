--[[
@module  battery
@summary 电池管理模块（Air8203：★ 当前仅占位 + 日志打印，硬件尚不支持电量读取）
@version 2.0（8203 缩减版）
@date    2026.09.28

=== ★★ 当前状态：功能已按现场要求缩减为"一个日志打印" ===
【已确认 2026-09-28】目前硬件**还不支持读取电池电量信息**。
因此本模块：
  · **不读 ADC、不推断充电状态、不采样、不发布充电事件**
  · 只保留：初始化日志 + 周期性的"功能未支持"提示日志
  · 对外接口**签名全部保留**（以免上层 active_mode / lowpower / 上报链路改动），
    但返回值一律为中性安全值，见下方"中性返回值"表

等硬件支持（分压通道与分压比确认）后，再按下文"恢复指引"重新开发。

=== 中性返回值（关键：必须"安全"，不能"像故障"） ===
  get_level()         → 100   ← ★ 必须是满值！level 若给 0 会让 active_mode 的
                                battery_monitor_task 误发 BATTERY_LOW / BATTERY_EMPTY，
                                进而触发 lowpower 的关机保护或低电量降档
  get_voltage()       → 0     ← 0 = "未知/未获取"（沿用原设计的语义，平台侧应按未知处理）
  is_charging()       → false ← 无充电状态可读；tools.lua 的黄灯因此恒灭（且本板黄灯多半为 nil）
  get_charge_stage()  → nil   ← 原设计即如此（TP4066 拿不到阶段）
  force_check()       → 同 get_data()
  get_data()          → 一张字段齐全、数值中性的表

=== 恢复指引（硬件支持后照此做，不要另起炉灶） ===
  1. 在 board.lua 的 voltage 段填入【待核】字段：
     adc_ch（电池分压落在哪个 ADC 通道）、r_up / r_down（分压比），并用万用表标定 offset_mv
  2. 充电状态：8203 的 TP4066 **无通信口**（【图】第 3 页，CHRG/STDBY 只驱动充电灯），
     只能按"相邻两轮电压爬升 ≥ config.CHARGE_CONFIG.INFER_RISE_MV"推断
  3. 恢复后必须重新发布 CHARGING_START / CHARGING_STOP 事件（utils/tools.lua 的 LED 状态机依赖）
  4. 恢复后确认 active_mode 的低电量上报（BATTERY_LOW / BATTERY_EMPTY）与
     lowpower_app 的截止动作能正常联动
]]

local battery = {}

local config = require("config")

-- 日志打印间隔
local LOG_INTERVAL_MS = 60 * 1000

-- 中性状态表（对外返回值统一从这里派生，保证"字段齐全 + 数值安全"）
local NEUTRAL = {
    voltage          = 0,      -- 0 = 未获取
    level            = 100,    -- ★ 满值：不触发低电量告警与关机保护
    charging         = false,
    last_check_time  = 0,
    charge_stage     = nil,
    charge_complete  = false,
    battery_present  = true,
    charger_present  = false,
    ic_overheat      = false,
    stage_capable    = false,
}

local state = {
    inited = false,
}

-- 返回中性表的副本（防止调用方就地修改污染全局）
local function neutral_copy()
    local t = {}
    for k, v in pairs(NEUTRAL) do t[k] = v end
    return t
end

--[[
初始化电池模块（★ 只打日志，不做任何采样）。

@return boolean 恒 true（模块"初始化完成"，只是功能未实现）
]]
function battery.init()
    if state.inited then return true end
    state.inited = true

    log.warn("battery", "★ 电池功能暂未支持：当前硬件无法读取电池电量信息，",
        "本模块已缩减为日志打印（不采样、不推断、不上报充电事件）")
    log.info("battery", string.format(
        "对外接口保留，返回中性值：level=%d%% voltage=%dmV charging=%s（0mV 表示未知）",
        NEUTRAL.level, NEUTRAL.voltage, tostring(NEUTRAL.charging)))
    log.info("battery", "恢复指引：硬件支持后填 board.lua 的 voltage.adc_ch / r_up / r_down，" ,
        "再按模块头注释的三步恢复；充电 IC TP4066 无通信口，只能按电压爬升推断")

    -- 周期性提示日志（便于现场从日志确认"不是坏了，是还没做"）
    sys.taskInit(function()
        while true do
            sys.wait(LOG_INTERVAL_MS)
            log.info("battery", "[占位] 电池电压/电量读取尚未开发（board.voltage.adc_ch 仍为【待核】）")
        end
    end)

    return true
end

--[[
获取电池数据（读缓存，非阻塞）。

@return table 字段齐全的中性状态表
]]
function battery.get_data()
    return neutral_copy()
end

--[[
获取电池电量百分比。

@return number 恒 100（★ 满值，避免误触发低电量保护）
]]
function battery.get_level()
    return NEUTRAL.level
end

--[[
获取电池电压（mV）。

@return number 恒 0（0 = 未知/未获取）
]]
function battery.get_voltage()
    return NEUTRAL.voltage
end

--[[
获取充电状态。

@return boolean 恒 false（无充电状态可读）
]]
function battery.is_charging()
    return NEUTRAL.charging
end

--[[
获取充电阶段。

@return nil 恒 nil（TP4066 无可通信接口，拿不到阶段 —— 硬件限制，不是 bug）
]]
function battery.get_charge_stage()
    return nil
end

--[[
兼容旧接口（原为"强制重新采样并阻塞返回"）。

★ 现在没有可采样的东西，直接返回中性表；签名保持不变，上层无需改动。
]]
function battery.force_check()
    return neutral_copy()
end

return battery
