-- internal_wdt.lua
--[[
@summary 内部看门狗演示模块
@version 1.0
@date    2025.10.25
@author  陈媛媛
@usage
本模块演示内部看门狗的正常和异常场景：
1、正常场景：定期喂狗，系统正常运行
2、异常场景：模拟故障导致无法喂狗，触发看门狗复位
3、通过修改 DEMO_MODE 变量来选择演示模式：
- "normal": 正常喂狗模式
- "fault": 异常故障模式

注意：在异常模式下，设备会在运行一段时间后重启
]]

-- 演示模式选择： "normal" 或 "fault"
local DEMO_MODE = "fault"  -- 修改这个变量来切换演示模式

-- 喂狗函数
function feed_watchdog()
    wdt.feed()
    log.info("wdt", "喂狗完成")
end

-- 故障模拟函数
function simulate_fault()
    sys.wait(5000) -- 等待5秒，让系统先正常运行一会
    
    -- 在进入死循环前尝试喂狗一次，并检查返回值
    local success = wdt.feed()
    log.info("wdt", "故障前最后一次喂狗，成功 =", success)
    
    log.info("fault_task", "进入死循环模拟故障")
    log.info("fault_task", "看门狗喂狗任务被阻塞，系统将在约20秒后重启")
    
    while true do
        -- 模拟故障场景，真的进入死循环
        -- 这将导致无法喂狗，最终触发系统重启
    end
end

-- 内部看门狗演示函数
function internal_wdt_demo()
    -- 检查wdt库是否存在
    if wdt == nil then
        log.error("wdt", "wdt库不存在")
        return
    end
    
    log.info("wdt", "硬件看门狗已由底层固件启用")
    
    -- 检查开机原因
    local reason1, reason2, reason3 = pm.lastReson()
    log.info("reset_reason", "重启原因1:", reason1, "原因2:", reason2, "原因3:", reason3)
    
    -- 定期喂狗，防止系统重启
    -- 设置喂狗间隔为3秒，确保在20秒超时前完成喂狗
    sys.timerLoopStart(feed_watchdog, 3000) -- 每3秒喂一次狗
end

if DEMO_MODE == "fault" then
    -- 创建一个新的任务来模拟故障场景
    sys.taskInit(simulate_fault)
end

-- 启动演示
sys.taskInit(internal_wdt_demo)

return internal_wdt_demo