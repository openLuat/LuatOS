--[[
@module  mem_monitor
@summary 内存使用监控功能模块
@version 1.0
@date    2026.09.28
@usage
周期性读取系统内存信息（rtos.meminfo("sys")），当历史最高已使用内存持续增长时，
打印告警日志，用于辅助分析内存泄漏问题。

本文件没有对外接口，直接在 main.lua 中 require "mem_monitor" 即可加载运行。
]]

-- 内存监控task处理函数
local function mem_monitor_task_func()
    -- 读取初始的总内存、已使用内存、历史最高已使用内存
    local tol, use, max_use = rtos.meminfo("sys")
    local last_max_use = max_use
    while true do
        -- 每100毫秒采样一次
        sys.wait(100)
        tol, use, max_use = rtos.meminfo("sys")
        -- 历史最高已使用内存创新高时，打印日志，便于分析内存是否持续增长
        if max_use > last_max_use then
            log.info("memory usage is increasing", max_use, "last_max_use", last_max_use)
            last_max_use = max_use
        end
    end
end

-- 创建并启动内存监控task
sys.taskInit(mem_monitor_task_func)
