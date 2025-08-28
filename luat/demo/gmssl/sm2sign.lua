
sys.taskInit(function()

    -- SM2签名和验签
    if gmssl.sm2sign then
        local originStr = string.fromHex("434477813974bf58f94bcf760833c2b40f77a5fc360485b0b9ed1bd9682edb45")
        local pkx = "ABE87C924B7ECFDEA1748A06E89003C9F7F4DC5C3563873CE2CAE46F66DE8141"
        local pky = "9514733D38CC026F2452A6A3A3A4DA0C28F864AFA5FE2C45E0EB6B761FBB5286"
        local private = "129EDC282CD2E9C1144C2E7315F926D772BC96600D2771E8BE02060313FE00D5"

        -- 不带id的情况,即默认id="1234567812345678"
        local sig = gmssl.sm2sign(private, originStr, nil)
        log.info("sm2sign", sig and sig:toHex())
        if sig then
            local ret = gmssl.sm2verify(pkx, pky, originStr, nil, sig)
            log.info("sm2verify", ret or "false")
        end

        -- 带id的情况
        local id = "1234"
        local sig = gmssl.sm2sign(private, originStr, id)
        log.info("sm2sign", sig and sig:toHex())
        if sig then
            local ret = gmssl.sm2verify(pkx, pky, originStr, id, sig)
            log.info("sm2verify", ret or "false")
        end
    end
end)
