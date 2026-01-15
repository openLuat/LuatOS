--[[
@module  sim_switch_test
@summary 双卡切换功能测试模块
@version 1.0
@date    2026.1.6
@author  拓毅恒
@usage
本文件为 Air8000 核心板演示双卡切换功能的代码示例，提供三种切换方式：

1. 轮询主动指定simid切换sim卡（sim_switch_task）
   - 定期检查网络状态，网络异常时主动切换到指定SIM卡
   - 使用mobile.simid()直接指定SIM卡索引进行切换

2. 轮询自适应切换sim卡（sim_switch_adaptive_task）
   - 系统自动选择最优SIM卡，无需手动指定
   - 设置mobile.simid(2)启用自适应模式
   - 注：自适应模式需要设备使用V2022及以上固件才可以使用！！！

3. 中断方式主动指定simid切换sim卡（sim_switch_irq_task）
   - 按键触发（WAKEUP0引脚）中断切换SIM卡
   - 下降沿触发中断，带有500ms防抖
   - 实时打印当前SIM卡状态和网络状态

核心业务逻辑包括：
- SIM卡自动切换功能（卡1网络异常切换到卡2，卡2网络异常切换到卡1）
- 网络状态监控和自动恢复机制
- 合理的切换间隔和超时控制
- SIM卡状态订阅和监控

使用说明：
- 在main.lua中require此模块即可启用双卡切换功能
- 确保同时注释掉mobile_test模块以避免代码冲突
- 同时只能选择一种切换方式启用
- 模块会自动管理网络状态并在需要时执行SIM卡切换
]]

-- 开启SIM脱离后自动恢复，30秒搜索一次周围小区信息
mobile.setAuto(10000, 30000, 5, nil, 30000) -- 此函数仅需要配置一次

-- 轮询主动指定simid切换sim卡
local function sim_switch_task()
    -- 当前使用的SIM卡索引（0或1）
    local current_sim = 0 
    -- 初始选择SIM0
    mobile.simid(current_sim)
    log.info("sim_switch", "初始SIM卡:", current_sim)
    
    while true do
        -- 获取当前网络状态
        local status = mobile.status()
        log.info("sim_switch", "当前SIM卡:", current_sim, "网络状态:", status)

        -- 如果网络状态不是"REGISTERED"或"REGISTERED_ROAMING"，则等待一段时间后检查是否联网成功
        if status ~= mobile.REGISTERED and status ~= mobile.REGISTERED_ROAMING then
            log.info("sim_switch", "正在等待网络连接...")
            -- 联网超时时间（15秒）
            sys.wait(15000)
            
            -- 再次检查网络状态
            status = mobile.status()
            if status ~= mobile.REGISTERED and status ~= mobile.REGISTERED_ROAMING then
                -- 网络连接失败，切换到另一张SIM卡
                current_sim = current_sim == 0 and 1 or 0
                log.info("sim_switch", "网络连接失败，切换到SIM卡", current_sim)
                -- 切换SIM卡
                mobile.simid(current_sim)
            else
                log.info("sim_switch", "网络连接成功")
            end
        else
            log.info("sim_switch", "网络已经连接")
        end
        sys.wait(10000) -- 每10秒检查一次网络状态
    end
end



-- 轮询自适应切换sim卡
-- 注：自适应模式需要设备使用V2022及以上固件才可以使用！！！
local function sim_switch_adaptive_task()
    -- 自适应方式切换SIM卡
    mobile.simid(2)
    -- 等待设置完毕
    sys.wait(3000)
    -- 获取当前使用的SIM卡索引
    local current_sim = mobile.simid()
    log.info("sim_switch", "初始SIM卡:", current_sim)
    
    while true do
        -- 获取当前网络状态
        local status = mobile.status()
        current_sim = mobile.simid()
        log.info("sim_switch", "当前SIM卡:", current_sim, "网络状态:", status)

        -- 如果网络状态不是"REGISTERED"或"REGISTERED_ROAMING"，则等待一段时间后检查是否联网成功
        if status ~= mobile.REGISTERED and status ~= mobile.REGISTERED_ROAMING then
            log.info("sim_switch", "正在等待网络连接...")
            -- 联网超时时间（15秒）
            sys.wait(15000)
            
            -- 再次检查网络状态
            status = mobile.status()
            if status ~= mobile.REGISTERED and status ~= mobile.REGISTERED_ROAMING then
                -- 网络连接失败，切换到另一张SIM卡
                current_sim = current_sim == 0 and 1 or 0
                log.info("sim_switch", "网络连接失败，切换到SIM卡", current_sim)
                -- 进入飞行模式
                mobile.flymode(current_sim, true)
                -- 退出飞行模式
                mobile.flymode(current_sim, false)
            else
                log.info("sim_switch", "网络连接成功")
            end
        else
            log.info("sim_switch", "网络已经连接")
        end
        sys.wait(10000) -- 每10秒检查一次网络状态
    end
end

-- 全局变量：中断方式切换SIM卡时的当前SIM卡索引
local current_sim_irq = 0

-- 设置中断触发回调函数
local function sim_switch_callback()
    -- 按键触发后，切换到另一张SIM卡
    current_sim_irq = current_sim_irq == 0 and 1 or 0
    log.info("sim_switch", "按键触发，开始切换到SIM卡:", current_sim_irq)
    
    -- 指定simid切换SIM卡
    local result = mobile.simid(current_sim_irq)
    if result then
        log.info("sim_switch", "SIM卡切换成功，当前使用SIM卡:", current_sim_irq)
    else
        log.error("sim_switch", "SIM卡切换失败")
    end
end

-- 中断方式主动指定simid切换sim卡
local function sim_switch_irq_task()
    -- 初始化全局变量
    current_sim_irq = 0
    log.info("sim_switch", "初始SIM卡:", current_sim_irq)
    -- 设置默认使用SIM0
    mobile.simid(current_sim_irq)
    
    -- 配置WAKEUP0引脚防抖（500ms）
    gpio.debounce(gpio.WAKEUP0, 500)
    
    -- 配置WAKEUP0引脚为下降沿触发中断
    gpio.setup(gpio.WAKEUP0, sim_switch_callback, gpio.PULLUP, gpio.FALLING)
    
    -- 定时打印当前状态的循环
    while true do
        local status = mobile.status()
        log.info("sim_switch", "当前SIM卡:", current_sim_irq, "网络状态:", status)
        sys.wait(10000) -- 每10秒打印一次
    end
end



-- 获取sim卡的状态
local function get_sim_status_task(status)
    if status == 'RDY' then
        log.info("sim_switch", "SIM卡正常")
    end
    if status == 'NORDY' then
        log.info("sim_switch", "无SIM卡")
    end
end

sys.subscribe("SIM_IND", get_sim_status_task)

-- 启动双卡切换任务（三选一）
-- 轮询主动指定simid切换sim卡
sys.taskInit(sim_switch_task)
-- 轮询自适应切换sim卡
-- 注：自适应模式需要设备使用V2022及以上固件才可以使用！！！
-- sys.taskInit(sim_switch_adaptive_task)
-- 中断方式主动指定simid切换sim卡
-- sys.taskInit(sim_switch_irq_task)