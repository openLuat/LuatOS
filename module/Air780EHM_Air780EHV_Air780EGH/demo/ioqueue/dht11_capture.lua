--[[
@module  test_ioqueue
@summary IO队列功能测试
@version 1.0
@date    2025.10.18
@author  孟伟
@usage
本功能模块演示的内容为：
DHT11 温湿度传感器数据读取

本文件没有对外接口,直接在main.lua中require "dht11_capture"就可以加载运行；
]]

-- 定义硬件定时器ID和捕获引脚号，这里使用硬件定时器0，捕获引脚25
local hw_timer_id, capture_pin = 0, 25

-- 测试单总线DHT11
function dht11_capture()
    local _, tick_us = mcu.tick64()
    --确保为GPIO功能
    gpio.setup(capture_pin, nil, nil)
    local buff1 = zbuff.create(100)
    local buff2 = zbuff.create(100)
    local cnt1, cnt2, i, lastTick, bit1Tick, nowTick, j, bit
    bit1Tick = 100 * tick_us
    -- 第一步：确保硬件定时器空闲
    ioqueue.stop(hw_timer_id)

    -- 第二步：初始化io队列
    ioqueue.init(hw_timer_id, 100, 1)


    -- 第三步：初始状态设置
    ioqueue.setgpio(hw_timer_id, capture_pin, true, gpio.PULLUP)
    -- 参数详解：
    -- 10000: 延时10ms（10000微秒）
    -- 0: 时间微调值
    -- false: 单次延时（非连续模式）
    -- 作用：初始空闲状态时长为10ms，给传感器足够的准备时间
    ioqueue.setdelay(hw_timer_id, 10000, 0, false)


    -- 第四步：配置DHT11传感器的启动信号，主机主动拉低总线开始通信
    ioqueue.setgpio(hw_timer_id, capture_pin, false, 0, 0)

    -- 18000: 延时18ms，这是DHT11协议要求的启动信号最小时间
    ioqueue.setdelay(hw_timer_id, 18000, 0, false)

    -- 第五步：配置捕获参数，为接收传感器数据做准备，此命令仅配置参数，实际捕获需配合后续的capture()命令执行
    -- 参数详解：
    -- gpio.PULLUP: 设置引脚为上拉输入模式（释放总线控制权）
    -- gpio.FALLING: 只捕获下降沿，捕获到后会记录io编号，电平高低，以及时间
    -- 100000 * tick_us: 单个capture()命令的最大等待时间100ms，超时后继续执行后续命令，每个capture()都是独立的100ms等待窗口
    ioqueue.set_cap(hw_timer_id, capture_pin, gpio.PULLUP, gpio.FALLING, 100000 * tick_us)
    --[[关于一个捕获周期含义：
        set_cap不等于开始捕获，只是配置参数捕获参数
        其中set_cap配置的最大等待时间是防止因传感器故障导致程序永久卡住
        开始：当执行 ioqueue.capture() 命令时开始一个捕获周期
        结束：满足以下任一条件时结束：
            检测到下降沿 → 立即记录时间戳并结束本次捕获周期，然后执行下一条命令
            达到100ms超时 → 直接结束，不记录数据，然后执行下一条命令
            调用cap_done() → 强制结束命令队列
        以上面代码为例：
        在100ms内，一次下降沿也没有检测到，则直接结束，执行队列中的下一条命令
        在100ms内，检测到一次下降沿，立即记录时间戳并结束，然后执行队列中的下一条命令；
        ]]

    -- 第六步：预分配捕获缓冲区 ，对io操作队列增加42次捕获IO状态命令
    for i = 1, 42, 1 do
        ioqueue.capture(hw_timer_id)
    end

    -- 停止捕获，不再监听该引脚的边沿变化
    ioqueue.cap_done(hw_timer_id, capture_pin)

    -- 恢复数据线为上拉输入状态，释放总线
    ioqueue.setgpio(hw_timer_id, capture_pin, true, gpio.PULLUP)


    -- 第七步：执行整个命令序列
    -- 开始按顺序执行前面设置的所有命令
    ioqueue.start(hw_timer_id)

    -- 等待执行完成，系统会在完成时发布这个事件
    -- 这是异步操作，不会阻塞其他任务
    sys.waitUntil("IO_QUEUE_DONE_" .. hw_timer_id)

    -- 停止硬件定时器
    ioqueue.stop(hw_timer_id)


    -- 第八步：读取捕获的数据
    cnt1, cnt2 = ioqueue.get(hw_timer_id, buff1, buff2)
    -- 参数详解：
    -- buff1: 存储输入数据的缓冲区
    -- buff2: 存储捕获数据的缓冲区
    -- cnt1: 读取io数据的数量，此返回值对应ioqueue.input()接口所配置的对读取gpio命令数量，此代码中是nil
    -- cnt2: 捕获数据的数量（应该是42）

    if cnt2 ~= 42 then
        log.info('test fail')
        goto TEST_OUT
    end
    -- 如果捕获数据不是42个，说明通信失败

    -- 第九步：解析数据
    -- 从捕获缓冲区读取第二个下降沿的时间戳
    -- 数据结构：每个捕获点占6字节
    -- 字节0: GPIO ID编号
    -- 字节1: 电平状态（0=下降沿，1=上升沿）
    -- 字节2-5: 32位时间戳（4字节）
    -- 所以第二个捕获点在偏移量6处，时间戳在6+2处
    lastTick = buff2:query(6 + 2, 4, false)


    j = 0
    bit = 8
    buff1[0] = 0

    for i = 2, 41, 1 do -- 遍历40个数据位（跳过第1个下降沿的DHT11响应信号）
        -- 验证数据完整性
        if buff2[i * 6 + 0] ~= capture_pin or buff2[i * 6 + 1] ~= 0 then
            log.error("capture", i, buff2[i * 6 + 0], buff2[i * 6 + 1])
        end

        -- 计算时间间隔
        -- 当前位的时间戳
        nowTick = buff2:query(i * 6 + 2, 4, false)
        -- 左移1位，为新的数据位腾出空间
        buff1[j] = buff1[j] << 1

        -- DHT11数据编码原理：
        -- 每个数据位都以50us低电平开始
        -- 然后高电平持续时间不同：
        --   26-28us → 数据0
        --   70us    → 数据1
        -- bit1Tick 是100us阈值，总时间 > 100us → 判断为位1，≤ 100us → 判断为位0
        if (nowTick - lastTick) > bit1Tick then
            buff1[j] = buff1[j] + 1 -- 设置最低位为1
        end

        bit = bit - 1
        if bit == 0 then   -- 完成1字节（8位）
            j = j + 1      -- 移动到下一字节
            bit = 8        -- 重置位计数器
        end
        lastTick = nowTick -- 更新参考时间戳
    end

    -- 第十步：数据校验
    buff1[5] = buff1[0] + buff1[1] + buff1[2] + buff1[3]
    -- DHT11协议：第5字节是前4字节的校验和
    if buff1[4] ~= buff1[5] then
        log.info('check fail', buff1[4], buff1[5])
    else
        log.info("湿度", buff1[0] .. '.' .. buff1[1], "温度", buff1[2] .. '.' .. buff1[3])
        -- buff1[0]: 湿度整数部分
        -- buff1[1]: 湿度小数部分
        -- buff1[2]: 温度整数部分
        -- buff1[3]: 温度小数部分
        -- buff1[4]: 校验和
    end

    ::TEST_OUT::
    -- 释放硬件定时器资源，可以重新分配使用
    ioqueue.release(hw_timer_id)
end

sys.taskInit(dht11_capture)
