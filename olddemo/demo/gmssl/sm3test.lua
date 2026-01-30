
sys.taskInit(function()

    -- SM3 算法, hash类
    if gmssl.sm3update then
        log.info("=== SM3测试")
        encodeStr = gmssl.sm3update("lqlq666lqlq946")
        log.info("gmssl.sm3update",string.toHex(encodeStr))
    end
end)

