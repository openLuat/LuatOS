--[[
@module  exril_5101_wdt
@summary 看门狗模块
@version 1.0
@date    2026.04.14
@author  王世豪
@usage
管理Air5101蓝牙模块的看门狗
说明：
    1. 本模块负责看门狗的初始化和喂狗
    2. 使用exril_5101.wdt接口，自动处理模式切换
]]

local exril_5101 = require("exril_5101")
 
-- 配置参数
local config = {
    timeout = 60,           -- 看门狗超时时间（秒）
    level = 0,              -- 超时动作电平
    width = 100,            -- 复位脉冲宽度（毫秒）
    feed_interval = 20000,  -- 喂狗间隔（毫秒）
}

-- 喂狗任务
local function watchdog_feed_task()
    log.info("exril_5101_wdt", "喂狗任务启动，间隔:", config.feed_interval / 1000, "秒")
    
    while true do
        sys.wait(config.feed_interval)
        
        -- 使用wdt.feed()，它会自动处理：
        -- 1. 检查看门狗是否已初始化
        -- 2. 自动切换到AT模式（如果需要）
        -- 3. 执行喂狗（最高优先级）
        -- 4. 自动切回原模式
        local success = exril_5101.wdt.feed()
        if success then
            log.debug("exril_5101_wdt", "喂狗成功")
        else
            log.error("exril_5101_wdt", "喂狗失败")
        end
    end
end

-- 看门狗初始化任务
local function wdt_init_task()
    log.info("exril_5101_wdt", "初等待主模块初始化完成...")

    local result = sys.waitUntil("EXRIL_5101_MAIN_READY", 30000)
    if not result then
        log.error("exril_5101_wdt", "等待主模块初始化超时（30秒），看门狗初始化失败")
        return
    end
    
    log.info("exril_5101_wdt", "收到主模块初始化完成信号，开始初始化看门狗...")
    
    -- 1. 检查当前工作模式
    local success, mode = exril_5101.mode()
    if not success then
        log.error("exril_5101_wdt", "获取模式失败:", mode)
        return
    end
    log.info("exril_5101_wdt", "当前工作模式:", mode)
    
    -- 2. 如果不是AT模式，先切换到AT模式
    if mode ~= exril_5101.MODE_AT then
        success, mode = exril_5101.mode(exril_5101.MODE_AT)
        if not success then
            log.error("exril_5101_wdt", "切换AT模式失败:", mode)
            return
        end
        log.info("exril_5101_wdt", "已切换到:", mode)
    end
    
    -- 3. 初始化看门狗
    success = exril_5101.wdt.init(config.timeout, config.level, config.width)
    if success then
        log.info("exril_5101_wdt", "看门狗初始化成功")
        
        -- 启动喂狗任务
        sys.taskInit(watchdog_feed_task)
    else
        log.error("exril_5101_wdt", "看门狗初始化失败")
    end
end

-- 启动初始化任务
sys.taskInit(wdt_init_task)
