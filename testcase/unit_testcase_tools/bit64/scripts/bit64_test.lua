bit64_context = {}
local luatos_version, luatos_version_num , luatos_version_system = rtos.version(true)

function bit64_context.test_hexto32()
    log.info("bit64_context", "开始 HEX数据转为32bit输出测试")
    local date = "40E201000000000000"
    local computation = bit64.to32(string.fromHex(date))
    local expectation = 123456
    assert(computation == expectation,
        string.format("HEX数据转成32bit输出测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation, luatos_version_system))
    log.info("bit64_context", "bit64 HEX数据转成32bit输出测试通过")
end

function bit64_context.test_to32_positive_integer()
    log.info("bit64_context", "开始 整数转为bit32测试")
    local date = 12345678
    local computation = bit64.to32(bit64.to64(date))
    local expectation = 12345678
    assert(computation == expectation,
        string.format("整数转为bit32测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation, luatos_version_system))
    log.info("bit64_context", "整数转为bit32测试通过")
end

function bit64_context.test_to32_negative_integer()
    log.info("bit64_context", "开始 负数64位转为32位有符号整数测试")
    local date = -12345678
    local computation = bit64.to32(bit64.to64(date))
    local expectation = -12345678
    assert(computation == expectation, string.format(
        "负数64位转为32位有符号整数测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation, luatos_version_system))
    log.info("bit64_context", "负数64位转为32位有符号整数测试通过")
end

function bit64_context.test_to32_positive_float()
    log.info("bit64_context", "开始 正浮点数64位转为32位测试")
    local date = 12.34234
    local computation = bit64.to32(bit64.to64(date))
    local expectation = 12.34234
    assert(computation == expectation,
        string.format("正浮点数64位转为32位测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation, luatos_version_system))
    log.info("bit64_context", "正浮点数64位转为32位测试通过")
end

function bit64_context.test_to32_negative_float()
    log.info("bit64_context", "开始 负浮点数64位转为32位测试")
    local date = -12.34234
    local computation = bit64.to32(bit64.to64(date))
    local expectation = -12.34234
    assert(computation == expectation,
        string.format("负浮点数64位转为32位测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation, luatos_version_system))
    log.info("bit64_context", "负浮点数64位转为32位测试通过")
end

function bit64_context.test_plus_integer64()
    log.info("bit64_context", "开始 64位整数加法测试")
    local date = bit64.to64(87654321)
    local number = bit64.to64(12345678)
    local computation = bit64.plus(date, number)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = 99999999
    assert(computation_val == expectation,
        string.format("64位整数加法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位整数加法测试通过")
end

function bit64_context.test_minus_integer64()
    log.info("bit64_context", "开始64位整数减法测试")
    local date = bit64.to64(87654321)
    local number = bit64.to64(12345678)
    local computation = bit64.minus(date, number)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = 75308643
    assert(computation_val == expectation,
        string.format("64位整数减法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位整数减法测试通过")
end

function bit64_context.test_multi_integer64()
    log.info("bit64_context", "开始 64位整数乘法测试")
    local date = bit64.to64(87654321)
    local number = bit64.to64(12345678)
    local computation = bit64.multi(number, date)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = 1082152022374638
    assert(computation_val == expectation,
        string.format("64位整数乘法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位整数乘法测试通过")
end

function bit64_context.test_pide_integer64()
    log.info("bit64_context", "开始 64位整数除法测试")
    local date = bit64.to64(87654321)
    local number = bit64.to64(12345678)
    local computation = bit64.pide(date, number)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = 7
    assert(computation_val == expectation,
        string.format("64位整数除法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位整数除法测试通过")
end

function bit64_context.test_plus_64_32_integer()
    log.info("bit64_context", "开始 64位与32位整数加法测试")
    local date = bit64.to64(1234567)
    local number = 1234567
    local computation = bit64.plus(date, number)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = 2469134
    assert(computation_val == expectation,
        string.format("64位与32位整数加法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位与32位整数加法测试通过")
end

function bit64_context.test_minus_64_32_integer()
    log.info("bit64_context", "开始 64位与32位整数减法测试")
    local date = bit64.to64(87654321)
    local number = 1234567
    local computation = bit64.minus(date, number)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = 86419754
    assert(computation_val == expectation,
        string.format("64位与32位整数减法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位与32位整数减法测试通过")
end

function bit64_context.test_multi_64_32_integer()
    log.info("bit64_context", "开始 64位与32位整数乘法测试")
    local date = bit64.to64(87654321)
    local number = 1234567
    local computation = bit64.multi(date, number)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = 108215132114007
    assert(computation_val == expectation,
        string.format("64位与32位整数乘法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位与32位整数乘法测试通过")
end

function bit64_context.test_pide_64_32_integer()
    log.info("bit64_context", "开始 64位与32位整数除法测试")
    local date = bit64.to64(87654321)
    local number = 1234567
    local computation = bit64.pide(date, number)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = 71
    assert(computation_val == expectation,
        string.format("64位与32位整数除法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位与32位整数除法测试通过")
end

function bit64_context.test_plus_mixed_float_integer()
    log.info("bit64_context", "开始 64位混合类型加法测试")
    local date = bit64.to64(87654.326)
    local number = bit64.to64(12345)
    local computation = bit64.plus(date, number)
    local computation_val = bit64.show(computation, 10)
    local expectation = bit64.show(bit64.to64(99999.326), 10)
    assert(computation_val == expectation,
        string.format("64位混合类型加法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位混合类型加法测试通过")
end

function bit64_context.test_minus_mixed_float_integer()
    log.info("bit64_context", "开始 64位混合类型减法测试")
    local date = bit64.to64(87654.326)
    local number = bit64.to64(12345)
    local computation = bit64.minus(date, number)
    local computation_val = bit64.show(computation, 10)
    local expectation = bit64.show(bit64.to64(75309.326), 10)
    assert(computation_val == expectation,
        string.format("64位混合类型减法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位混合类型减法测试通过")
end

function bit64_context.test_multi_mixed_float_integer()
    log.info("bit64_context", "开始 64位混合类型乘法测试")
    local date = bit64.to64(87654.326)
    local number = bit64.to64(12345)
    local computation = bit64.multi(date, number)
    local computation_val = bit64.show(computation, 10)
    local expectation = bit64.show(bit64.to64(1082092654.47), 10)
    assert(computation_val == expectation,
        string.format("64位混合类型乘法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位混合类型乘法测试通过")
end

function bit64_context.test_pide_mixed_float_integer()
    log.info("bit64_context", "开始 64位混合类型除法测试")
    local date = bit64.to64(87654.326)
    local number = bit64.to64(12345)
    local computation = bit64.pide(date, number)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = tonumber(bit64.show(bit64.to64(7.100391), 10))
    assert(computation_val == expectation,
        string.format("64位混合类型除法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位混合类型除法测试通过")
end

function bit64_context.test_plus_float64()
    log.info("bit64_context", "开始 64位浮点数加法测试")
    local date = bit64.to64(87654.32)
    local number = bit64.to64(12345.67)
    local computation = bit64.plus(date, number)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = tonumber(bit64.show(bit64.to64(99999.99), 10))
    assert(computation_val == expectation,
        string.format("64位浮点数加法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位浮点数加法测试通过")
end

function bit64_context.test_minus_float64()
    log.info("bit64_context", "开始 64位浮点数减法测试")
    local date = bit64.to64(87654.32)
    local number = bit64.to64(12345.67)
    local computation = bit64.minus(date, number)
    local computation_val = bit64.to32(computation, 10)
    local expectation = 87654.32  - 12345.67
    log.info("bit64_context", "computation_val=", computation_val, "expectation=", expectation)
    assert(computation_val == expectation,
        string.format("64位浮点数减法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位浮点数减法测试通过")
end

function bit64_context.test_multi_float64()
    log.info("bit64_context", "开始 64位浮点数乘法测试")
    local date = bit64.to64(87654.32)
    local number = bit64.to64(12345.67)
    local computation = bit64.multi(date, number)
    local computation_val = bit64.show(computation, 10)
    local expectation = bit64.show(bit64.to64(1082151308.7944), 10)
    assert(computation_val == expectation,
        string.format("64位浮点数乘法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位浮点数乘法测试通过")
end

function bit64_context.test_pide_float64()
    log.info("bit64_context", "开始 64位浮点数除法测试")
    local date = bit64.to64(87654.32)
    local number = bit64.to64(12345.67)
    local computation = bit64.pide(date, number)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = tonumber(bit64.show(bit64.to64(7.100005), 10))
    assert(computation_val == expectation,
        string.format("64位浮点数除法测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位浮点数除法测试通过")
end

function bit64_context.test_pide_float64_to_int()
    log.info("bit64_context", "开始 64位浮点数除法强转整数测试")
    local date = bit64.to64(87654.32)
    local number = bit64.to64(12345.67)
    local computation = bit64.pide(date, number, nil, true)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = 7
    assert(computation_val == expectation, string.format(
        "64位浮点数除法强转整数测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位浮点数除法强转整数测试通过")
end

function bit64_context.test_shift_64bit()
    log.info("bit64_context", "开始 64位数据左移位测试")
    local date = bit64.to64(12345678)
    local number = 5
    local computation = bit64.shift(date, number, true)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = 395061696
    assert(computation_val == expectation,
        string.format("64位数据左移位测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位数据左移位测试通过")
end

function bit64_context.test_shiftright_64bit()
    log.info("bit64_context", "开始 64位数据右移位测试")
    local date = bit64.to64(12345678)
    local number = 5
    local computation = bit64.shift(date, number, false)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = 385802
    assert(computation_val == expectation,
        string.format("64位数据右移位测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "64位数据右移位测试通过")
end

function bit64_context.test_strtoll()
    log.info("bit64_context", "开始 字符串转LongLong测试")
    local date = "864040064024194"
    local number = 10
    local computation = bit64.strtoll(date, number)
    local computation_val = tonumber(bit64.show(computation, 10))
    local expectation = 864040064024194
    assert(computation_val == expectation,
        string.format("字符串转LongLong测试失败: 预期 %s, 实际 %s, 当前bit位数 %s", expectation, computation_val, luatos_version_system))
    log.info("bit64_context", "字符串转LongLong测试通过")
end

return bit64_context
