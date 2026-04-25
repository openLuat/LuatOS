-- air153c_wdt.lua
--[[
@summary Air153C外部看门狗演示模块
@version 1.0
@date    2025.10.25
@author  陈媛媛
@usage
本模块演示Air153C外部看门狗的正常和异常场景：
1、正常场景：定期喂狗，系统正常运行
2、异常场景：模拟故障导致无法喂狗，触发看门狗复位
3、通过修改 DEMO_MODE 变量来选择演示模式：
- "normal": 正常喂狗模式
- "fault": 异常故障模式

注意：在异常模式下，设备会在运行一段时间后重启
]]

-- 演示模式选择： "normal" 或 "fault"
local DEMO_MODE = "normal"  -- 修改这个变量来切换演示模式

-- 看门狗喂狗任务函数
local function watchdogTask()
    -- 检查air153C_wtd库是否存在
    if air153C_wtd == nil then
        log.error("air153C_wtd", "air153C_wtd库不存在")
        return
    end
    
    -- 初始化看门狗引脚28
    air153C_wtd.init(28)
    log.info("air153C_wtd", "外部看门狗已初始化，引脚28")

    if DEMO_MODE == "normal" then
        -- 正常模式：主循环中定期喂狗
        while true do
            -- 每10秒喂一次狗
            air153C_wtd.feed_dog(28)
            log.info("wdt", "Watchdog fed")
            
            -- 执行其他业务逻辑
            sys.wait(10000)  -- 等待10秒
        end
    elseif DEMO_MODE == "fault" then
        -- 异常模式：先正常喂狗一段时间，然后停止喂狗
        local feed_count = 0
        while true do
            -- 每10秒喂一次狗
            air153C_wtd.feed_dog(28)
            feed_count = feed_count + 1
            log.info("wdt", "Watchdog fed")
            
            -- 执行其他业务逻辑
            sys.wait(10000)  -- 等待10秒
            
            -- 喂狗3次后（约30秒）停止喂狗，模拟故障
            if feed_count >= 3 then
                log.info("wdt", "Stopping watchdog feed to simulate fault")
                break
            end
        end
    end
end

-- 看门狗喂狗任务
sys.taskInit(watchdogTask)