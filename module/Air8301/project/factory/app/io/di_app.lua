--[[
@module  di_app
@summary DI输入监测管理（8301出厂固件）
@version 1.1
@date    2026.10.13
@author  江访
@usage
GPIO16(DI1) + GPIO17(DI2) 中断输入，双边沿触发（显式 gpio.BOTH）。

电平语义（依据原理图第 7 页 DI 隔离输入电路）：
  光耦 EL3H7 输出侧为集电极开路，R0601/R0604 = 4.7K 上拉到 3.3V
  → 无外部输入：引脚被上拉 = 1（无效）
  → 有外部输入（光耦导通）：引脚被拉低 = 0（有效）
- 初始化时读一次初始电平并发布 DI_STATUS_CHANGED(di1, di2)
- 电平变化时发布 DI_STATUS_CHANGED(di1, di2)
]]

local DI1_PIN = 16
local DI2_PIN = 17

local di1_current = 0
local di2_current = 0

--[[
DI1 中断回调：电平变化时更新缓存并发布 DI_STATUS_CHANGED(di1, di2)

@local
@function di1_irq_cb
@param pin number 触发中断的引脚
]]
local function di1_irq_cb(val)
    local changed = (val ~= di1_current)
    di1_current = val
    log.info("di_app", "DI1: 16 val:", val)
    if changed then
        sys.publish("DI_STATUS_CHANGED", di1_current, di2_current)
    end
end

--[[
DI2 中断回调：电平变化时更新缓存并发布 DI_STATUS_CHANGED(di1, di2)

@local
@function di2_irq_cb
@param val number 触发后读取到的引脚电平（0/1）
]]
local function di2_irq_cb(val)
    local changed = (val ~= di2_current)
    di2_current = val
    log.info("di_app", "DI2: 17 val:", val)
    if changed then
        sys.publish("DI_STATUS_CHANGED", di1_current, di2_current)
    end
end

-- 初始化（无 sys.wait，直接执行）
-- 1) gpio.debounce：20ms 冷却防抖（与官方 AirKEY demo 用法一致）
-- 2) 显式 gpio.BOTH：第 4 个参数 int_mode 不传时官方默认 gpio.FALLING（仅下降沿），
--    会导致"对 GND 短接"有事件、"松开"没有事件，与本模块的双边沿语义不符
-- 3) 先 setup 成上拉输入再读初值：setup 之前引脚尚未配置，gpio.get 结果不可靠
gpio.debounce(DI1_PIN, 20)
gpio.debounce(DI2_PIN, 20)
gpio.setup(DI1_PIN, di1_irq_cb, gpio.PULLUP, gpio.BOTH)
gpio.setup(DI2_PIN, di2_irq_cb, gpio.PULLUP, gpio.BOTH)

di1_current = gpio.get(DI1_PIN)
di2_current = gpio.get(DI2_PIN)

-- 发布初始状态
sys.publish("DI_STATUS_CHANGED", di1_current, di2_current)

log.info("di_app", "init done, DI1:", di1_current, "DI2:", di2_current)

-- ==================== DI 电平自检（现场排查用） ====================
-- 背景：DI 是光耦隔离输入（原理图第 7 页），触发完全依赖外部信号，
--       接线/电压不对时中断根本不触发，串口上"什么都看不到"，无法区分
--       「硬件没把电平拉低」还是「固件没上报」。
-- 本任务周期性打印两个通道的原始电平（1=无输入，0=有输入），
-- 现场接线时盯着日志即可判断硬件侧是否真的导通。
-- 出货前把 DI_LEVEL_PROBE_MS 置 0 即可关闭。
local DI_LEVEL_PROBE_MS = 5000

if DI_LEVEL_PROBE_MS and DI_LEVEL_PROBE_MS > 0 then
    sys.taskInit(function()
        while true do
            sys.wait(DI_LEVEL_PROBE_MS)
            log.info("di_app", "电平自检 DI1:", gpio.get(DI1_PIN), " DI2:", gpio.get(DI2_PIN))
        end
    end)
end
