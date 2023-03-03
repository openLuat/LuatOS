PROJECT = "errDump_leak"
VERSION = "1.0.0"

-- https://gitee.com/openLuat/LuatOS/issues/I6J4O1

local sys = require "sys"

errDump.config(true, 600)

function get_error()
    local error_string = ""
    local init_string = "^NO ERROR INFO!^"
    local buff = zbuff.create(4096)
    local new_flag = errDump.dump(buff, errDump.TYPE_USR)
    -- log.info("new_flag", #new_flag)
    if buff:used() > 0 then
        init_string = ""
        error_string = "USR_ERROR:\r\n" .. buff:toStr(0, buff:used()) .. "\r\n"
        buff:del()
    end
    log.info("error_string", #error_string)
    new_flag = errDump.dump(buff, errDump.TYPE_SYS)
    if buff:used() > 0 then
        init_string = ""
        error_string = error_string .. "SYS_ERROR:\r\n" .. buff:toStr(0, buff:used())
        buff:del()
    end
    -- log.info("new_flag", #new_flag)
    log.info("init_string", #init_string)
    log.info("error_string", #error_string)
    return init_string .. error_string
end

sys.timerLoopStart(function()
    errDump.record("NO IP ADDREES,REBOOT!!!ffffffffffffffffffffffffffffffffffffffffffffffffffffrrrrrrrrr")
    local data = get_error()
    log.info("get_error", #data)
end, 1000)

sys.run()
