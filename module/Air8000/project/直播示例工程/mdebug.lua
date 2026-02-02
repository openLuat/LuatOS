--[[
@module  mdebug
@summary 调试信息模块：内存监控、设备信息打印
@version 1.0
@author  Auto
@usage
本模块实现以下功能：
1. 内存监控：打印Lua和系统内存使用情况
2. 设备信息：打印IMEI、型号、硬件版本、唯一ID等
]]

local mdebug = {}

-- ==================== 内存监控 ====================

--[[
打印内存使用情况
包括Lua虚拟机内存和系统内存

@api mdebug.mem(timeout)
@number timeout 可选，保留参数（未使用）
@usage
mdebug.mem()  -- 打印内存信息
]]
function mdebug.mem(timeout)
    log.info("lua", rtos.meminfo())
    log.info("sys", rtos.meminfo("sys"))
end

-- ==================== 设备信息 ====================

--[[
打印本机设备信息
包括IMEI、设备型号、硬件版本、唯一ID等

@api mdebug.self_info()
@usage
mdebug.self_info()  -- 打印设备信息
]]
function mdebug.self_info()
    -- 打印IMEI、设备型号、硬件版本
    log.info("imei", mobile.imei(), hmeta.model(), hmeta.hwver())
    -- 打印设备唯一ID（十六进制格式）
    log.info("唯一id", mcu.unique_id():toHex())
end

-- ==================== 初始化 ====================

-- 可选：定时监控内存（已注释）
-- sys.timerLoopStart(mdebug.mem, 15000)

-- 启动时打印设备信息
mdebug.self_info()

return mdebug
