
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "test"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()

    local _,tick_us = mcu.tick64()
    local hw_timer_id = 1
    local capture_pin = pin.PD06
    local out_pin = pin.PD07
    local buff1 = zbuff.create(100)
    local buff2 = zbuff.create(100)
    local cnt1,cnt2,i,lastTick,bit1Tick,nowTick,j,bit
    mcu.setXTAL(true)   --为了测试更准确，调整到外部时钟
    bit1Tick = 100 * tick_us
    while 1 do
        --测试单总线DHT11
        ioqueue.stop(hw_timer_id)   --确保硬件定时器1是空闲的
        ioqueue.init(hw_timer_id,100,1) --io队列设置100个命令，重复1次，实际上用不到那么多命令
        ioqueue.setgpio(hw_timer_id, capture_pin, true, gpio.PULLUP)   --数据线拉高，上拉输入
        ioqueue.setdelay(hw_timer_id, 10000, 0, false)  --单次延迟10ms
        ioqueue.setgpio(hw_timer_id, capture_pin, false, 0, 0)   --数据线拉低
        ioqueue.setdelay(hw_timer_id, 18000, 0, false)  --单次延迟18ms
        ioqueue.set_cap(hw_timer_id, capture_pin, gpio.PULLUP, gpio.FALLING, 100000 * tick_us)   --设置成下降沿中断捕获，最大计时100000us, 上拉输入，这里已经代替了输出20~40us高电平
        for i = 1,42,1 do
            ioqueue.capture(hw_timer_id)    --捕获42次外部中断发生时的tick值，2个start信号+40bit数据
        end
        ioqueue.cap_done(hw_timer_id, capture_pin)  --停止捕获
        ioqueue.setgpio(hw_timer_id, capture_pin, true, gpio.PULLUP)   --数据线拉高，上拉输入
        ioqueue.start(hw_timer_id)
        sys.waitUntil("IO_QUEUE_DONE_"..hw_timer_id)
        ioqueue.stop(hw_timer_id)
        --开始解析捕获的数据
        cnt1,cnt2 = ioqueue.get(hw_timer_id, buff1, buff2)
        if cnt2 ~= 42 then
            log.info('test fail')
            goto TEST_OUT
        end
        lastTick = buff2:query(6 + 2, 4, false) --以第二次中断的tick作为起始tick，第一次的tick没有用
        j = 0
        bit = 8
        buff1[0] = 0
        for i = 2,41,1 do
            --检查一下是不是对应pin的下降沿中断，不过也不太需要
            if buff2[i * 6 + 0] ~= capture_pin or buff2[i * 6 + 1] ~= 0 then
                log.error("capture", buff2[i * 6 + 0], buff2[i * 6 + 1])
            end
            --通过计算tick差值来确定是bit1还是bit0
            nowTick = buff2:query(i * 6 + 2, 4, false)
            buff1[j] = buff1[j] << 1 
            if (nowTick - lastTick) > bit1Tick then
               buff1[j] = buff1[j] + 1
            end
            bit = bit - 1
            if bit == 0 then
                j = j + 1
                bit = 8
            end
            lastTick = nowTick
        end
        buff1[5] = buff1[0] + buff1[1] + buff1[2] + buff1[3]
        if buff1[4] ~= buff1[5] then
            log.info('check fail', buff1[4], buff1[5])
        else
            log.info("湿度", buff1[0] .. '.' .. buff1[1], "温度", buff1[2] .. '.' ..  buff1[3])
        end
        ::TEST_OUT::
        ioqueue.release(hw_timer_id)

        --测试高精度固定间隔定时输出,1us间隔翻转电平
        ioqueue.init(hw_timer_id, 100, 100)
        ioqueue.setgpio(hw_timer_id, out_pin, false,0,1)   --设置成输出口，电平1
        ioqueue.setdelay(hw_timer_id, 0, 45, true)  --设置成连续延时，每次1个us，如果不准，对time_tick微调，延时开始
        for i = 0,40,1 do
            ioqueue.output(hw_timer_id, out_pin, 0)
            ioqueue.delay(hw_timer_id)     --连续延时1次
            ioqueue.output(hw_timer_id, out_pin, 1)
            ioqueue.delay(hw_timer_id)     --连续延时1次
        end
        ioqueue.start(hw_timer_id)
        sys.waitUntil("IO_QUEUE_DONE_"..hw_timer_id)
        log.info('output 1 done')
        ioqueue.stop(hw_timer_id)
        ioqueue.release(hw_timer_id)
        sys.wait(500)
        --测试高精度可变间隔定时输出
        ioqueue.init(hw_timer_id, 100, 100)
        ioqueue.setgpio(hw_timer_id, out_pin, false,0,1)   --设置成输出口，电平1
        ioqueue.setdelay(hw_timer_id, 0, 45)  --单次延迟1us，如果不准，对time_tick微调
        ioqueue.output(hw_timer_id, out_pin, 0) --低电平
        ioqueue.setdelay(hw_timer_id, 1, 45)  --单次延迟2us
        ioqueue.output(hw_timer_id, out_pin, 1) --高电平
        ioqueue.setdelay(hw_timer_id, 2, 45)  --单次延迟3us
        ioqueue.output(hw_timer_id, out_pin, 0) --低电平
        ioqueue.setdelay(hw_timer_id, 3, 45)  --单次延迟4us
        ioqueue.output(hw_timer_id, out_pin, 1) --高电平
        ioqueue.setdelay(hw_timer_id, 4, 45)  --单次延迟5us
        ioqueue.output(hw_timer_id, out_pin, 0) --低电平
        ioqueue.setdelay(hw_timer_id, 5, 45)  --单次延迟6us
        ioqueue.output(hw_timer_id, out_pin, 1) --高电平
        ioqueue.start(hw_timer_id)
        sys.waitUntil("IO_QUEUE_DONE_"..hw_timer_id)
        log.info('output 2 done')
        ioqueue.stop(hw_timer_id)
        ioqueue.release(hw_timer_id)
        sys.wait(500)
    end
end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
