--[[
@module  charge
@summary 充电模块（Air8203：**占位空壳**，充电状态推断全在 modules/battery.lua）
@version 1.0（8203 移植版）
@date    2026.09.28
@usage
=== 为什么这个文件变成了空壳（T11） ===

基线（8202G）的 charge.lua 是 `exs_yhm2712a`（YHM2712A 充电 IC，CMD 单总线）的薄封装：
  setup({pin, v_battery, cap_battery, i_charge}) → start()
这套逻辑在 8203 上**整体作废**，原因是硬件根本不同：

  · 8203 的充电 IC 是 **TP4066**（【图】原理图第 3 页）
  · TP4066 是纯硬件线性充电 IC，**无任何通信口**：
      - 没有 YHM2712A 那样的 CMD 单总线 → 无法配置浮充电压/充电电流/电池容量
      - 只有 CHRG(7)/STDBY(6) 两个开漏状态脚，且原理图中用于驱动充电灯 LED202，
        **未接入主控 GPIO** → 连状态都读不到

=== 8203 的充电状态去哪了 ===
按 irtu-8203-docs/TASKS.md 里 T10/T11 的决定：**全部合并进 modules/battery.lua**，
实现为充电源 `CHG_TP4066`（"相邻两轮电压上升 ≥ INFER_RISE_MV → 判为充电中"的推断器），
不在这里重复造一份。

本文件保留为**空壳**的唯一理由：保持启动链结构一致
（app.lua 的 init_all_modules() 会调 charge.init()），
避免每换一个硬件就要改上层装配清单。这不是"死代码"，是**接口占位**。

对外接口（保持与基线同名，行为为空）：
  init()   —— 空实现，只打印一条说明日志，恒返回 false（未启用）
]]

local charge = {}

local config = require "config"

--[[
初始化充电模块（★8203：空实现）

@return boolean 恒 false —— 8203 无可通信充电 IC，本模块不参与任何控制
]]
function charge.init()
    local cfg = config.CHARGE_CONFIG or {}
    log.info("charge", string.format(
        "8203 无充电 IC 通信能力（%s，ENABLE=%s），本模块不参与控制，仅作占位保持启动链结构一致；"
        .. "充电状态由 modules/battery.lua 按电压爬升推断（INFER_RISE_MV=%s mV）",
        tostring(cfg.IC), tostring(cfg.ENABLE), tostring(cfg.INFER_RISE_MV)))
    return false
end

return charge
