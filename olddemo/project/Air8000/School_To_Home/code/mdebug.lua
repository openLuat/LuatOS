--[[
调试信息类, 可全部关掉的, 也可以只关掉部分.
]]

local mdebug = {}

-- 内存监控
function mdebug.mem(timeout)
    log.info("lua", rtos.meminfo())
    log.info("sys", rtos.meminfo("sys"))
end

function mdebug.self_info()
    -- 打印本机信息
    log.info("imei", mobile.imei(), hmeta.model(), hmeta.hwver())
    log.info("唯一id", mcu.unique_id():toHex())
    log.info("PCB版本号", pcb.hver())
    log.info("是否出厂测试过", pcb.test())
----------------------------
end

-- sys.timerLoopStart(mdebug.mem, 15000)
mdebug.self_info()

return mdebug
