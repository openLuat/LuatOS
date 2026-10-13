--[[
@module  di_app
@summary DI输入监测管理
@version 2.0
@date    2026.08.04
@author  江访
@usage
GPIO16(DI1) + GPIO17(DI2) 中断输入，双边沿触发。
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
local function di1_irq_cb(pin)
    local val = gpio.get(pin)
    local changed = (val ~= di1_current)
    di1_current = val
    log.info("di_app", "DI1:", pin, "val:", val)
    if changed then
        sys.publish("DI_STATUS_CHANGED", di1_current, di2_current)
    end
end

--[[
DI2 中断回调：电平变化时更新缓存并发布 DI_STATUS_CHANGED(di1, di2)

@local
@function di2_irq_cb
@param pin number 触发中断的引脚
]]
local function di2_irq_cb(pin)
    local val = gpio.get(pin)
    local changed = (val ~= di2_current)
    di2_current = val
    log.info("di_app", "DI2:", pin, "val:", val)
    if changed then
        sys.publish("DI_STATUS_CHANGED", di1_current, di2_current)
    end
end

-- 初始化（无 sys.wait，直接执行；DI 引脚方向已由 board_init 设置）
di1_current = gpio.get(DI1_PIN)
di2_current = gpio.get(DI2_PIN)

gpio.setup(DI1_PIN, di1_irq_cb, gpio.PULLUP)
gpio.setup(DI2_PIN, di2_irq_cb, gpio.PULLUP)

-- 发布初始状态
sys.publish("DI_STATUS_CHANGED", di1_current, di2_current)

log.info("di_app", "init done, DI1:", di1_current, "DI2:", di2_current)
