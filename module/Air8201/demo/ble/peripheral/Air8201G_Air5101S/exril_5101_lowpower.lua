--[[
@module  lowpower
@summary 低功耗控制模块
@version 1.1
@date    2026.03.02
@author  王世豪
@usage
Air5101蓝牙模块的低功耗模式演示
说明：
    1. 本模块会发布"POWER_STATE_CHANGED"消息，用于通知其他模块功耗状态改变
    2. 支持三种功耗模式：
        - P0: 常规模式
        - P1: 低功耗模式1，唤醒后继续保持低功耗模式1
        - P3: 低功耗模式3，唤醒后自动恢复常规模式0

本文件没有对外接口，直接在main.lua中require "lowpower"就可以加载运行。
]]

local exril_5101 = require("exril_5101")

-- 配置参数
local config = {
    enable = true,              -- 是否启用低功耗控制
    normal_duration = 10000,    -- 常规模式持续时间（毫秒）
    lowpower_duration = 10000,  -- 低功耗模式持续时间（毫秒）
    lowpower_mode = exril_5101.P1,  -- 低功耗模式
    wakeup_retry = 3,           -- 唤醒重试次数
    wakeup_delay = 300,         -- 唤醒重试间隔（毫秒）
}

-- 当前功耗状态
local current_power_mode = exril_5101.P0


-- 切换到低功耗模式
local function enter_lowpower()
    log.info("lowpower", "进入低功耗模式...")
    
    -- 检查并切换到AT模式
    local success, mode = exril_5101.mode()
    if success and mode ~= exril_5101.MODE_AT then
        log.info("lowpower", "当前不在AT模式，切换到AT模式...")
        local success = exril_5101.mode(exril_5101.MODE_AT)
        if not success then
            log.error("lowpower", "切换到AT模式失败")
            return false
        end
    end
    
    local success, msg = exril_5101.power(config.lowpower_mode)
    if success then
        current_power_mode = config.lowpower_mode
        sys.publish("POWER_STATE_CHANGED", current_power_mode)
        log.info("lowpower", "已进入低功耗模式:", current_power_mode)
        return true
    else
        log.error("lowpower", "进入低功耗模式失败:", msg)
        return false
    end
end

-- 唤醒并切换到常规模式
local function wakeup_to_normal()
    log.info("lowpower", "唤醒到常规模式...")
    
    for i = 1, config.wakeup_retry do
        log.info("lowpower", "尝试唤醒 (" .. i .. "/" .. config.wakeup_retry .. ")...")
        
        local success, msg = exril_5101.power(exril_5101.P0, true)
        if success then
            current_power_mode = exril_5101.P0
            sys.publish("POWER_STATE_CHANGED", current_power_mode)
            log.info("lowpower", "第" .. i .. "次唤醒成功")
            return true
        else
            log.error("lowpower", "第" .. i .. "次唤醒失败:", msg)
        end
        
        if i < config.wakeup_retry then
            sys.wait(config.wakeup_delay)
        end
    end
    
    log.error("lowpower", "多次唤醒失败")
    return false
end

-- 低功耗控制主任务
local function lowpower_task()
    if not config.enable then
        log.info("lowpower", "低功耗控制已禁用")
        return
    end
    
    while true do
        -- 常规模式阶段
        sys.wait(config.normal_duration)
        
        -- 进入低功耗模式
        if enter_lowpower() then
            -- 低功耗模式阶段
            sys.wait(config.lowpower_duration)
            
            -- 唤醒到常规模式
            wakeup_to_normal()
        end
    end
end

-- 启动低功耗控制任务
sys.taskInit(lowpower_task)
