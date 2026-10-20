--[[
@module  rtos_app
@summary rtos应用模块
@version 1.0
@date    2025.12.2
@author  王城钧
@usage
本文件为rtos应用模块，核心业务逻辑为：
1、对rtos核心库的各项功能进行测试，包括系统信息查询、内存信息获取、内存自动回收配置以及性能测试

本文件没有对外接口，直接在其他功能模块中require "rtos_app"就可以加载运行；
]]

-- 1. 系统信息查询测试
-- 读取版本号及数字版本号, 2025.11.1之后的固件支持
-- 如果不是数字固件,luatos_version_num 会是0
-- 如果是不支持的固件, luatos_version_num 会是nil
local luatos_version, luatos_version_num = rtos.version(true)
log.info("固件信息", "版本:", luatos_version, luatos_version_num )

log.info("编译信息", "日期:", rtos.buildDate(), "BSP:", rtos.bsp())
log.info("完整描述", rtos.firmware())

-- 2. 内存信息测试
local total_lua, used_lua, max_used_lua = rtos.meminfo("lua")
local total_sys, used_sys, max_used_sys = rtos.meminfo("sys")
log.info("内存信息", 
    "Lua - 总:", total_lua, "已用:", used_lua, "峰值:", max_used_lua,
    "系统 - 总:", total_sys, "已用:", used_sys, "峰值:", max_used_sys)

-- 3. 定时器测试
-- rtos.timer_start()和rtos.timer_stop()两个接口，仅仅给sys核心库使用
-- 如果要使用定时器，直接使用sys核心库提供的定时器接口即可
-- 用户脚本中不要直接使用rtos.timer_start()和rtos.timer_stop()两个接口
-- 否则和sys核心库中的定时器功能出现冲突而导致系统异常的问题

-- 4. 内存自动回收配置
rtos.autoCollectMem(200, 75, 85)  -- 配置较宽松的自动回收

-- 5. 空函数测试（性能测试用）
local function test_nop()
    local start = mcu.ticks()
    for i = 1, 1000 do
        rtos.nop()
    end
    local duration = mcu.ticks() - start
    log.info("性能测试", "1000次nop耗时:", duration, "毫秒")
end

-- 10秒后执行空函数测试
sys.timerStart(test_nop, 10000)

-- 6. 重启测试（注释掉防止意外重启）
-- local function reboot()
--     log.info("系统", "准备重启...")
--     rtos.reboot()
-- end
-- sys.timerStart(reboot, 30000)

log.info("RTOS测试", "所有测试已启动")
