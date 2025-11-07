--[[
@module  test_ioqueue
@summary IO队列功能测试
@version 1.0
@date    2025.10.18
@author  孟伟
@usage
本功能模块演示的内容为：
高精度固定间隔脉冲输出功能
输出脉冲信息：
输出固定间隔对称方波
- 低电平持续时间：20微秒（固定）
- 高电平持续时间：20微秒（固定）
- 脉冲周期：40微秒（完整周期）
- 占空比50%
- 脉冲数量：41个完整周期（通过循环40次生成）
- 使用ioqueue.setdelay的连续模式，所有延时间隔自动保持20us


本文件没有对外接口,直接在main.lua中require "fix_pulse_output"就可以加载运行；
]]

--  选好硬件定时器和输出引脚，这里使用硬件定时器0，输出引脚2
local hw_timer_id, out_pin = 0, 2

function fix_pulse_output_fun()
    local _, tick_us = mcu.tick64()
    --确保为GPIO功能
    gpio.setup(out_pin, nil, nil)
    -- 第一步：初始化
    -- 100个命令，循环10次（生成100个脉冲）
    ioqueue.init(hw_timer_id, 100, 10)

    -- 设置GPIO为输出模式，初始输出高电平
    ioqueue.setgpio(hw_timer_id, out_pin, false, 0, 1)


    -- 第二步：配置连续延时模式
    ioqueue.setdelay(hw_timer_id, 20, tick_us - 3, true)


    -- 第三步：生成脉冲序列
    -- 每个循环生成1个完整周期：低电平20us + 高电平20us = 40us周期
    for i = 0, 40, 1 do
        ioqueue.output(hw_timer_id, out_pin, 0) -- 输出低电平
        ioqueue.delay(hw_timer_id)              -- 延时20us
        ioqueue.output(hw_timer_id, out_pin, 1) -- 输出高电平
        ioqueue.delay(hw_timer_id)              -- 延时20us
    end

    -- 第四步：执行
    ioqueue.start(hw_timer_id)
    -- 等待执行完成，系统会在完成时发布这个事件
    sys.waitUntil("IO_QUEUE_DONE_" .. hw_timer_id)
    -- 停止硬件定时器
    ioqueue.stop(hw_timer_id)
    -- 释放硬件定时器资源，可以重新分配使用
    ioqueue.release(hw_timer_id)
end

sys.taskInit(fix_pulse_output_fun)
