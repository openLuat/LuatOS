--[[
@module  otp_test
@summary otp_test测试功能模块
@version 1.0
@date    2025.11.21
@author  马亚丹
@usage
本demo演示的功能为：使用Air1601核心板演示otp核心库API的用法，演示写入，读取，擦除otp数据等操作。

运行核心逻辑：
1.读取指定 OTP 区域的数据
2.擦除指定的 OTP 区域的数据
3.擦除完成后向该区域写入数据
4.谨慎操作区域加锁(区域加锁后会永久变成只读无法写入)

注意：OTP区域取值请参考对应芯片手册；
写入 / 读取的长度需与 OTP 块大小对齐，按 4 字节对齐。
]]

local function otp_test()
    log.info("========otp read start=========")
    local otpdata = otp.read(1, 0, 64)
    if otpdata then
        log.info("otp 读取结果", otpdata, type(otpdata))
    else
        log.info("otp 读取失败")
    end
    
    log.info("========otp erase start=========")
    local erase_ok = otp.erase(1)
    if erase_ok then
        log.info("OTP 擦除成功")
    else
        log.info("OTP 擦除失败")
    end
    local write_data = "1234"
    log.info("=========向otp区域1写入数据==========")
    local write_ok = otp.write(1, write_data, 0)
    if write_ok then
        log.info("OTP 写入成功", write_data)
    else
        log.info("OTP 写入失败")
    end

    log.info("=========读取otp区域1数据==========")

    local otpdata_1 = otp.read(1, 0, 4)
    local otpdata_2 = otp.read(1, 0, 8)
    if otpdata_1 then
        log.info("读取4字节数据", otpdata_1, type(otpdata_1))
    else
        log.info("===========otp区域1读取失败=========")
    end
    if otpdata_2 then
        log.info("读取8字节数据", otpdata_2, type(otpdata_2))
    else
        log.info("===========otp区域1读取失败=========")
    end

    --=====锁定 OTP 区域，特别注意！！！ OTP一旦加锁即无法解锁,OTP 会变成只读!!!=============
    -- local lock_ok = otp.lock(1)
    -- if lock_ok then
    --     log.info("OTP 锁定成功")
    -- end
    --=================================================================================================
end

sys.taskInit(otp_test)
