local sm3 = {}

--SM3测试
function sm3.test_sm3_update()
    log.info("GMSSL SM3 测试开始")
    local correct_val = "E64FD76F4078E51DCA428323D3FADBD5D52723BBF1379184650DA5CE6002B2BF"
    local update_val = gmssl.sm3update("lqlq666lqlq946")
    log.info("gmssl.sm3update",string.toHex(update_val))
    assert(string.toHex(update_val) == correct_val, "× SM3 测试失败")
end



return sm3
