--[[
@module  mcu_test
@summary 测试mcu模块功能
@version 1.0
@date    2025.10.21
@author  孟伟
@usage
本demo演示的功能为：
    MCU死机时的处理模式设置
    唯一ID获取与显示
    系统tick计数功能测试
    64位tick计数和差值计算
    微秒、毫秒、秒级别的时间计数
    16进制字符串转换输出

    本文件没有对外接口,直接在main.lua中require "mcu_test"就可以加载运行；
]]
function mcu_test()
    -- 测试MCU 死机时的处理模式
    -- 死机后重启，一般用于正式产品_
    mcu.hardfault(1)

    -- 测试唯一ID
    local unique_id = mcu.unique_id()
    if #unique_id > 0 then
        log.info("mcu", "Unique ID(hex):", unique_id:toHex())
    else
        log.warn("mcu", "Unique ID not supported")
    end

    -- 测试ticks相关函数
    -- 获取启动后的 tick 数
    log.info("mcu", "ticks:", mcu.ticks())
    -- 获取每秒的 tick 数量
    log.info("mcu", "获取每秒的tick数量:", mcu.hz())


    -- 测试64位tick
    local tick_str, tick_per = mcu.tick64()
    log.info("mcu", "tick64:", tick_str:toHex(), "ticks per us:", tick_per)
    -- 测试mcu.dtick64接口获取ticks差值计算
    local tick1 = mcu.tick64()
    sys.wait(100)
    local tick2 = mcu.tick64()
    local result, diff_tick = mcu.dtick64(tick1, tick2)
    log.info("mcu", "dtick64 result:", result, "diff:", diff_tick)


    -- 测试ticks2函数
    local us_h, us_l = mcu.ticks2(0)
    local ms_h, ms_l = mcu.ticks2(1)
    local sec_h, sec_l = mcu.ticks2(2)
    log.info("mcu", "us:", us_h, us_l)
    log.info("mcu", "ms:", ms_h, ms_l)
    log.info("mcu", "sec:", sec_h, sec_l)

    -- 测试 转换 10 进制数为 16 进制字符串输出
    local value = mcu.x32(0x2009FFFC) --输出"0x2009fffc"
    log.info("mcu", "string", value)


end

sys.taskInit(mcu_test)
