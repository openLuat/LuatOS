
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "otpdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--[[
提示: OTP是比较高级的API, 一般用于存储密钥等核心数据, 不建议用于普通数据的存放

OTP有个非常重要的特性, 就是一旦加锁就永久无法解锁, 这点非常非常重要

OTP通常由多个zone, 0,1,2, 每个zone通常由256字节, 但这个非常取决于具体模块.

OTP在没有加锁之前是可以抹除的, 每次都是整个zone一起抹除.
]]

sys.taskInit(function()
    sys.wait(3000)

    -- 擦除区域
    -- otp.erase(2)

    -- 写otp区域
    local ret = otp.write(2, "1234", 0)
    log.info("otp", "write", ret)

    -- 读取otp区域
    for zone = 0, 2, 1 do
        local otpdata = otp.read(zone, 0, 64)
        if otpdata then
            log.info("otp", zone, otpdata:toHex())
            log.info("otp", zone, otpdata)
        end
    end

    -- 锁定otp区域, 别轻易尝试, 加锁之后就无法解锁了
    -- otp.lock(2)
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
