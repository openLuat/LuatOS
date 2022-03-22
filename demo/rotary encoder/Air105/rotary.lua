-- 旋转编码器
-- 正反方向根据实际情况决定
local s1_pin = pin.PC09
local s2_pin = pin.PA10
local pin_need = 1
local s1_last = nil
local s2_last = nil
local s1_up = false
local s2_up = false
local s1_down = false
local s2_down = false
local _,us_tick = mcu.tick64()
us_tick = us_tick * 1000 --低于1ms的当杂波去除，可以根据实际需要修改

local function stage1()
    pin_need = 0
    -- log.info("wait down")
    ioqueue.exti(s1_pin, nil, gpio.FALLING, true)
    ioqueue.exti(s2_pin, nil, gpio.FALLING, true)
end

local function stage2()
    pin_need = 1
    -- log.info("wait up")
    ioqueue.exti(s1_pin, nil, gpio.RISING, true)
    ioqueue.exti(s2_pin, nil, gpio.RISING, true)
    s1_up,s2_up,s1_down,s2_down = false,false,false,false
end

local function s1_irq(val, tick)
    if gpio.get(s1_pin) ~= pin_need then return end
    if s1_last then
        local result,_ = mcu.dtick64(tick, s1_last, us_tick)
        if result then
            -- log.info("s1", mcu.dtick64(tick, s1_last))
            if pin_need > 0 then
                s1_up = true
            else
                s1_down = true
            end
            -- log.info("s1", s1_up, s1_down)
        else
            return
        end
    else
        -- log.info("s1")
        s1_up = true
    end
    if pin_need > 0 and s1_up and s2_up then
        stage1()
    end
    if s2_down then
        log.info("s2pin先检测到，右转+1")
        stage2()
    end
    s1_last = tick

end

local function s2_irq(val, tick)
    if gpio.get(s2_pin) ~= pin_need then return end
    if s2_last then
        local result,_ = mcu.dtick64(tick, s2_last, us_tick)
        if result then 
            -- log.info("s2", mcu.dtick64(tick, s2_last))
            if pin_need > 0 then
                s2_up = true
            else
                s2_down = true
            end
            -- log.info("s2", s2_up, s2_down)
        else
            return
        end
    else
        -- log.info("s2")
        s2_check = true
    end
    if pin_need > 0 and s1_up and s2_up then
        stage1()
    end
    if s1_down then
        log.info("s1pin先检测到，左转+1")
        stage2()
    end
    s2_last = tick
end

sys.subscribe("IO_QUEUE_EXTI_" .. s1_pin, s1_irq)
sys.subscribe("IO_QUEUE_EXTI_" .. s2_pin, s2_irq)

function rotary_start()
    pin_need = 1
    ioqueue.exti(s1_pin, nil, gpio.RISING, true)
    ioqueue.exti(s2_pin, nil, gpio.RISING, true)
    -- sys.timerLoopStart(clear, 10000)
end