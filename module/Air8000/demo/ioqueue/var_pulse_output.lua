--[[
@module  test_ioqueue
@summary IO队列功能测试
@version 1.0
@date    2025.10.18
@author  孟伟
@usage
本功能模块演示的内容为：
高精度可变间隔脉冲输出
输出脉冲信息：
输出可变间隔非对称脉冲
- 10次完整序列
- 输出波形：低电平20us → 高电平30us → 低电平40us → 高电平50us→ 低电平60us → 高电平70us
- 使用ioqueue.setdelay 单次模式，每个延时独立配置


本文件没有对外接口,直接在main.lua中require "fix_pulse_output"就可以加载运行；
]]

--[[
@module  test_ioqueue
@summary IO队列功能测试
@version 1.0
@date    2025.10.18
@author  孟伟
@usage
本功能模块演示的内容为：
高精度可变间隔脉冲输出功能

本文件没有对外接口,直接在main.lua中require "var_pulse_output"就可以加载运行；
]]


--  选好硬件定时器和输出引脚，这里使用硬件定时器0，输出引脚2
local hw_timer_id, out_pin = 0, 2

function var_pulse_output_fun()
    local _, tick_us = mcu.tick64()
    --确保为GPIO功能
    gpio.setup(out_pin, nil, nil)
    log.info('output 2 start')
    --测试高精度可变间隔定时输出
    ioqueue.init(hw_timer_id, 100, 10)
    --设置成输出口，电平1
    ioqueue.setgpio(hw_timer_id, out_pin, false, 0, 1)
    --单次延迟20us，如果不准，对time_tick微调
    ioqueue.setdelay(hw_timer_id, 20, tick_us - 3)
    --低电平
    ioqueue.output(hw_timer_id, out_pin, 0)
    --单次延迟30us
    ioqueue.setdelay(hw_timer_id, 30, tick_us - 3)
    --高电平
    ioqueue.output(hw_timer_id, out_pin, 1)
    --单次延迟40us
    ioqueue.setdelay(hw_timer_id, 40, tick_us - 3)
    --低电平
    ioqueue.output(hw_timer_id, out_pin, 0)
    --单次延迟50us
    ioqueue.setdelay(hw_timer_id, 50, tick_us - 3)
    --高电平
    ioqueue.output(hw_timer_id, out_pin, 1)
    --单次延迟60us
    ioqueue.setdelay(hw_timer_id, 60, tick_us - 3)
    --低电平
    ioqueue.output(hw_timer_id, out_pin, 0)
    --单次延迟70us
    ioqueue.setdelay(hw_timer_id, 70, tick_us - 3)
    --高电平
    ioqueue.output(hw_timer_id, out_pin, 1)
    ioqueue.start(hw_timer_id)
    sys.waitUntil("IO_QUEUE_DONE_" .. hw_timer_id)
    log.info('output 2 done')
    ioqueue.stop(hw_timer_id)
    ioqueue.release(hw_timer_id)
    sys.wait(500)
end

sys.taskInit(var_pulse_output_fun)
