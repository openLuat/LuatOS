--[[
@module  gpio_irq_task
@summary GPIO中断功能模块
@version 1.0
@date    2025.10.21
@author  拓毅恒
@usage
本文件为 GPIO 按键短按和长按检测的代码示例，核心业务逻辑为：
1. 配置GPIO24为中断模式，上升沿和下降沿均触发
2. 实现按键短按(小于3秒)和长按(大于等于3秒)的检测功能
3. 可连接按键或直接用杜邦线轻触GND进行测试
4. 注意：使用杜邦线测试时，因为脉冲可能无法控制，所以不要加防抖防止程序测试异常
]]

-- 配置gpio24为中断模式，上升沿(gpio.RISING)和下降沿(gpio.FALLING)均触发(gpio.BOTH)
local gpio_pin = 24
-- gpio.debounce(gpio_pin, 100) -- 实际设计板子时，根据自己的需求可以更改防抖配置以及打开防抖

-- 按键状态变量
local long_press_threshold = 3000  -- 长按判断阈值，3秒
local current_state = 1  -- 跟踪当前按键状态，1为释放，0为按下

-- 定时器回调函数，处理长按事件
local function timer_callback(gpio_id)
    log.info("按键检测", "长按事件", gpio_id)
end

-- 定义GPIO中断处理函数
local function gpio_irq_handler()
    local pin_state = gpio.get(gpio_pin)  -- 获取GPIO当前状态
    
    -- 只有当状态发生变化时才处理
    if pin_state ~= current_state then
        current_state = pin_state  -- 更新当前状态
        
        if pin_state == 0 then
            -- 按键按下
            log.info("按键检测", "按键按下")
            if not sys.timerIsActive(timer_callback, gpio_pin) then
                -- 启动定时器，3秒后触发长按事件
                sys.timerStart(timer_callback, long_press_threshold, gpio_pin)
            end
        elseif pin_state == 1 then
            -- 按键释放
            log.info("按键检测", "按键释放")
            
            -- 如果定时器还在运行，说明是短按
            if sys.timerIsActive(timer_callback, gpio_pin) then
                sys.timerStop(timer_callback, gpio_pin)
                log.info("按键检测", "短按事件")
            end
        end
    end
end

-- 配置GPIO中断
gpio.setup(gpio_pin, gpio_irq_handler, gpio.PULLUP, gpio.BOTH)
