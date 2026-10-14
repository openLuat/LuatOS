--[[
@module  wdt_app
@summary 硬件看门狗（Air8203 由 BLE 芯片 MS1631C 兼任）—— 【框架骨架，P0 待确认】
@version 0.2（改名 wdt.lua → wdt_app.lua）
@date    2026.09.28

=== ★ 为什么文件名是 wdt_app.lua 而不是 wdt.lua ===
合宙**核心库**里已经有 `wdt`（luat_lib_wdt.c）。核心库在固件启动时会注册进
package.loaded，若脚本文件也叫 wdt.lua，`require("wdt")` 会拿到**核心库**而不是本模块
（本文件根本不会被加载）→ 表现为"喂狗模块完全没跑、且没有任何报错"，
而看门狗恰恰是 8203 的 P0 风险项，静默失效后果严重。
→ 因此按项目约定给文件名加后缀：**wdt → wdt_app**（audio → audio_app 同理）。
⚠️ 改名的只有**文件名**，对外接口名一律不变（wdt_app.init / feed / get_status）。

=== 为什么这个模块在 8203 上是 P0 ===

【图】Air8203 V1.0 原理图第 6 页图注原文：
  「当主控不按时喂 MS1631C 时，拉高该信号，通过三极管反向后，拉低主控 RESET_N 复位」

→ Air8203 **没有 Air153C**，看门狗职责压在 BLE 芯片 MS1631C 上。
→ 后果：喂狗机制一旦搞错，设备会陷入**周期复位循环**（能开机、日志正常、但反复重启）。

=== 已知教训（【官网-faq 2026-08-24】案例 24/25） ===
  · 外部硬件看门狗上电即开始工作，**不会**因为脚本没喂它就暂停
  · 典型事故：注网/联网耗时数秒到十几秒，业务逻辑在这段阻塞期间没喂狗 → 超时复位
    → 表现为"插卡反复重启、不插卡正常"
  · 正确做法：喂狗放在**独立定时器/协程**里，确保注网、socket 阻塞等任何流程下都不停

=== 因此本模块的设计约束 ===
  1. init() 必须在 main.lua 的**最早期**调用（现行顺序：board → wdt → ble_link → sim_slot → …）
  2. 喂狗任务必须是独立协程，不等待网络、不依赖任何业务状态、不读配置
  3. 机制未确认前，**不猜测**喂狗引脚与周期：只告警，不做动作
     （猜错引脚在本板上等于"不停复位主控"，风险高于不喂）

=== 【待核】清单（P0） ===
  a) 喂狗物理形式：专用 GPIO 脉冲  还是  串口 AT 心跳（发 AT 本身即喂狗）？
     线索：原理图第 6 页把"喂狗"与"主控发 AT 指令给 MS1631C"写在同一段图注里，
           且复位路径是 BLE 侧拉高 → 反相 → 主控 RESET_N。
           → 倾向"BLE 侧超时"是**独立的**，与 AT 通道是否活跃相关，需向合宙确认。
  b) 喂狗信号落到主控哪个 GPIO（候选：BLE_TXD/RXD 之外的一根专用线，或 ARM 侧的 PA17/PA19）
  c) 超时时长（Air153C 是固定 240s；MS1631C 是否可配？）
  d) 上电后到首次可喂狗之间的"宽限期"有多长（决定 main.lua 里能放多少同步初始化）

=== 在确认之前，本模块的行为 ===
  · CHIP = "MS1631C"、FEED_PIN = nil、FEED_INTERVAL = nil
  · init() 打印一条 WARN，列出上述 4 项待确认
  · **不注册任何喂狗任务**（宁可不喂，也不误操作 RESET 路径）
  · 提供 wdt.feed() 空实现，供业务层占位调用（后续补上真实机制即可，调用方零改动）
]]

local wdt = {}

local config = require("config")
local CFG = config.WDT_CONFIG or {}

local state = {
    enabled  = false,
    feed_cnt = 0,
    timer    = nil,
}

--[[
初始化看门狗。

@return boolean 是否已进入"可喂狗"状态
]]
function wdt.init()
    log.info("wdt", "看门狗模块初始化: impl=" .. tostring(CFG.IMPL)
        .. " chip=" .. tostring(CFG.CHIP)
        .. " feed_pin=" .. tostring(CFG.FEED_PIN)
        .. " interval=" .. tostring(CFG.FEED_INTERVAL)
        .. " enable=" .. tostring(CFG.ENABLE))

    -- ⚠️ 机制未确认：只告警，不动作
    if not CFG.ENABLE or not CFG.FEED_PIN or not CFG.FEED_INTERVAL then
        log.warn("wdt", "★ 8203 看门狗（BLE 芯片 MS1631C 兼任）喂狗机制尚未确认，本模块暂不喂狗。",
            "待确认 4 项：",
            "① 喂狗物理形式（GPIO 脉冲 / 串口 AT 心跳）",
            "② 喂狗信号所在主控引脚",
            "③ 超时时长",
            "④ 上电到首次可喂狗的宽限期",
            "—— 依据：【图】原理图第 6 页图注「主控不按时喂 MS1631C → 拉高 → 反相 → 拉低主控 RESET_N」")
        return false
    end

    -- 机制确认后走这里（占位，待实现）
    state.enabled = true
    log.info("wdt", "看门狗喂狗已启用，引脚:", CFG.FEED_PIN, "周期:", CFG.FEED_INTERVAL, "s")

    local function feed_task()
        while true do
            sys.wait((CFG.FEED_INTERVAL or 180) * 1000)
            wdt.feed()
        end
    end
    sys.taskInit(feed_task)

    return true
end

--[[
喂狗（占位实现）。

★ 设计约束：本函数将来无论是"拉一次 GPIO 脉冲"还是"发一条 AT 心跳"，
  都必须满足：非阻塞、不依赖网络、不读 fskv、失败不抛异常。
  这样它才能被放在独立协程里，在注网/socket 阻塞期间照常执行。
]]
function wdt.feed()
    if not state.enabled then return false end
    state.feed_cnt = state.feed_cnt + 1
    -- TODO【待实现】按确认后的机制填充：
    --   方案 A（GPIO 脉冲）：gpio.set(pin, 0) → sys.wait(20) → gpio.set(pin, 1)  ← 注意不可用 sys.wait 阻塞喂狗协程
    --   方案 B（AT 心跳）  ：ble_link.at("AT+PING")
    log.debug("wdt", "喂狗 #" .. state.feed_cnt)
    return true
end

function wdt.get_status()
    return {
        enabled  = state.enabled,
        feed_cnt = state.feed_cnt,
        impl     = CFG.IMPL,
        chip     = CFG.CHIP,
    }
end

return wdt
