PROJECT = "rtos_demo"
VERSION = "1.0.0"
-- RTOS 功能测试脚本
local sys = require("sys")

-- 1. 系统信息查询测试
log.info("固件信息", "版本:", rtos.version())
log.info("编译信息", "日期:", rtos.buildDate(), "BSP:", rtos.bsp())
log.info("完整描述", rtos.firmware())

-- 2. 内存信息测试
local total_lua, used_lua, max_used_lua = rtos.meminfo("lua")
local total_sys, used_sys, max_used_sys = rtos.meminfo("sys")
log.info("内存信息", 
    "Lua - 总:", total_lua, "已用:", used_lua, "峰值:", max_used_lua,
    "系统 - 总:", total_sys, "已用:", used_sys, "峰值:", max_used_sys)

-- 3. 定时器测试
-- 测试用例1: 基本单次定时器测试

    local timer_id = 1001
    log.info( "单次定时器测试开始 (ID:"..timer_id..")")  
    -- 启动3秒后触发的单次定时器
    rtos.timer_start(timer_id, 3000, 0)    
    -- 定时器回调处理
            local msg = rtos.receive(100)  -- 等待消息
            if msg == timer_id then
                log.info("测试1", "单次定时器触发成功")
            end
-- 启动定时器 (2秒触发一次，共触发5次)
rtos.timer_start(timer_id, 2000, 5)
log.info("定时器", "已启动ID:", timer_id, "间隔2秒")


rtos.timer_stop(timer_id)



-- 5. 内存自动回收配置
rtos.autoCollectMem(200, 75, 85)  -- 配置较宽松的自动回收

-- 6. 空函数测试（性能测试用）
local function test_nop()
    local start = os.clock()
    for i = 1, 1000 do
        rtos.nop()
    end
    log.info("性能测试", "1000次nop耗时:", os.clock()-start, "秒")
end

-- 10秒后执行空函数测试
sys.timerStart(test_nop, 10000)

-- 7. 重启测试（注释掉防止意外重启）
-- sys.timerStart(function()
--     log.info("系统", "准备重启...")
--     rtos.reboot()
-- end, 30000)

log.info("RTOS测试", "所有测试已启动")
sys.run()