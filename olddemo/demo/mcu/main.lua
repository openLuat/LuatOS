PROJECT = "mcu_test_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

_G.sys = require("sys")
 mcu.hardfault(1) -- 设置为死机后重启
-- 初始化看门狗（如果支持）
if wdt then
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end

-- 测试函数
local function testMcuFunctions()
    -- 1. 测试主频获取
    local mhz = mcu.getClk()
    if mhz == -1 then
        log.error("mcu", "getClk failed")
    else
        log.info("mcu", "Current clock:", mhz, "MHz", mhz == 0 and "(可能处于32k省电模式)" or "")
    end
    
    -- 2. 测试唯一ID
    local unique_id = mcu.unique_id()
    if #unique_id > 0 then
        log.info("mcu", "Unique ID(hex):", unique_id:toHex())
    else
        log.warn("mcu", "Unique ID not supported")
    end

    -- 3. 测试ticks相关函数
    log.info("mcu", "ticks:", mcu.ticks())
    log.info("mcu", "获取每秒的tick数量:", mcu.hz())
    
    -- 4. 测试64位tick
    local tick_str, tick_per = mcu.tick64()
    log.info("mcu", "tick64:", tick_str:toHex(), "ticks per us:", tick_per)
    
    -- 5. 测试ticks2函数
    local us_h, us_l = mcu.ticks2(0)
    local ms_h, ms_l = mcu.ticks2(1)
    local sec_h, sec_l = mcu.ticks2(2)
    log.info("mcu", "us:", us_h, us_l)
    log.info("mcu", "ms:", ms_h, ms_l)
    log.info("mcu", "sec:", sec_h, sec_l)

    --6.测试
    local value = mcu.x32(0x2009FFFC) --输出"0x2009fffc"
    log.info("mcu","string",value)

    -- 7. 测试tick差值计算
    local tick1 = mcu.tick64()
    sys.wait(100)
    local tick2 = mcu.tick64()
    local result, diff_tick = mcu.dtick64(tick1, tick2)
    log.info("mcu", "dtick64 result:", result, "diff:", diff_tick)



    -- 9. 测试IO复用功能（需要根据具体硬件支持）
mcu.iomux(mcu.UART, 2, 2)    -- Air780E的UART2复用到gpio6和gpio7
mcu.iomux(mcu.I2C, 0, 1)    -- Air780E的I2C0复用到gpio12和gpio13

--10.
local us_h, us_l = mcu.ticks2(0)
local ms_h, ms_l = mcu.ticks2(1)
local sec_h, sec_l = mcu.ticks2(2)
log.info("us_h", us_h, "us_l", us_l)
log.info("ms_h", ms_h, "ms_l", ms_l)
log.info("sec_h", sec_h, "sec_l", sec_l)
    -- 10. 测试晶振参考时钟输出（需要硬件支持）
    -- mcu.XTALRefOutput(true, false)
end

-- 创建测试任务
sys.taskInit(function()
    sys.wait(1000) -- 等待系统稳定
    
    -- 每隔5秒运行一次测试
        testMcuFunctions()
        log.info("End MCU Function Test")
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!