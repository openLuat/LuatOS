local mcu_tests = {}

function mcu_tests.test_mcu_uniqueId()
    log.info("===== 测试 mcu.unique_id() =====")
    local unique_id = mcu.unique_id()
    assert(type(unique_id) == "string",
        string.format("获取设备唯一 ID类型错误: 预期类型：string, 实际类型 %s", unique_id))
    assert(unique_id ~= "", "获取设备唯一 ID失败,返回了空字符串")
    assert(#unique_id <= 32, string.format("设备唯一ID长度超限: 最大32字节, 实际 %d 字节", #unique_id))
end

function mcu_tests.test_mcu_ticks()
    log.info("===== 测试 mcu.ticks() =====")
    local tick = mcu.ticks()
    assert(type(tick) == "number",
        string.format("mcu.ticks()类型错误: 预期类型：number, 实际类型 %s", type(tick)))
    assert(tick >= 0 and tick <= 0x7fffffff,
        string.format("mcu.ticks()超出范围: 值 %d 不在0~0x7fffffff范围内", tick))

    -- 测试tick是否递增
    local tick1 = mcu.ticks()
    sys.wait(100)
    local tick2 = mcu.ticks()
    assert(tick2 >= tick1, string.format("tick未递增: tick1=%d, tick2=%d", tick1, tick2))

end

function mcu_tests.test_mcu_hz()
    log.info("===== 测试 mcu.hz() =====")
    local hz = mcu.hz()
    assert(type(hz) == "number", string.format("mcu.hz()类型错误: 预期类型：number, 实际类型 %s", type(hz)))
    assert(hz > 0, string.format("mcu.hz()值异常: 应大于0, 实际为 %d", hz))

    -- 验证典型的tick频率
    local common_hz_values = {1000, 1000000, 32768} -- 常见值
    local is_common = false
    for _, common in ipairs(common_hz_values) do
        if hz == common then
            is_common = true
            break
        end
    end
    if not is_common then
        log.warn("警告: mcu.hz()返回不常见的值:", hz)
    end

end

function mcu_tests.test_mcu_X32Hexadecimal()
    log.info("===== 测试 mcu.X32(Hexadecimal) =====")
    local value = mcu.x32(0x2009FFFC)
    local expected_value = "0x2009fffc"
    assert(type(value) == "string", string.format(
        "mcu.X32(Hexadecimal)返回值类型错误: 预期类型：string, 实际类型 %s", type(value)))
    assert(value == expected_value,
        string.format("mcu.X32(Hexadecimal)值异常: 预期为%s, 实际为 %s", expected_value, value))
end

function mcu_tests.test_mcu_X32Decimal()
    log.info("===== 测试 mcu.X32(Decimal) =====")
    local value = mcu.x32(453453)
    local expected_value = string.format("0x%x", 453453)
    assert(type(value) == "string",
        string.format("mcu.X32(Decimal)返回值类型错误: 预期类型：string, 实际类型 %s", type(value)))
    assert(value == expected_value,
        string.format("mcu.X32(Decimal)值异常: 预期为%s, 实际为 %s", expected_value, value))
end

function mcu_tests.test_mcu_X32_error_type()
    log.info("===== 测试 mcu.X32()错误类型测试 =====")
    local success, err = pcall(function()
        mcu.x32("hello") -- 不是有效的格式字符
    end)
    assert(success ~= true, "错误数据类型应该返回错误")
    log.info("mcu_X32", "错误数据类型正确返回错误:", err)
end

function mcu_tests.test_mcu_tick64_basic()
    log.info("===== 测试 mcu.tick64() 基本功能 =====")

    -- 测试不带参数（默认模式）
    local tick_str, tick_per = mcu.tick64()

    -- 断言1: 第一个返回值类型
    assert(type(tick_str) == "string",
        string.format("mcu.tick64()返回值1类型错误: 预期类型：string, 实际类型 %s", type(tick_str)))

    -- 断言2: 第二个返回值类型
    assert(type(tick_per) == "number",
        string.format("mcu.tick64()返回值2类型错误: 预期类型：number, 实际类型 %s", type(tick_per)))

    -- 断言3: 字符串长度（至少8字节表示64位）
    assert(#tick_str >= 8,
        string.format("mcu.tick64()返回值1长度不足: 至少8字节, 实际 %d 字节", #tick_str))

    -- 断言4: tick_per 的有效性（应为非负数）
    assert(tick_per >= 0, string.format("mcu.tick64()每微秒tick数异常: 应为非负数, 实际 %d", tick_per))
    log.info("mcu.tick64()基本功能测试通过")
end

function mcu_tests.test_mcu_tick64_with_false()
    log.info("===== 测试 mcu.tick64(false) =====")

    -- 测试带false参数
    local tick_str, tick_per = mcu.tick64(false)

    -- 断言1: 返回值1类型检查
    assert(type(tick_str) == "string", "mcu.tick64(false)返回值1类型错误: 预期string类型")

    -- 断言2: 返回值2类型检查
    assert(type(tick_per) == "number", "mcu.tick64(false)返回值2类型错误: 预期number类型")

    -- 断言3: tick_per 应为非负数
    assert(tick_per >= 0, string.format("tick_per应为非负数: 实际 %d", tick_per))

end

function mcu_tests.test_mcu_tick64_with_true()
    log.info("===== 测试 mcu.tick64(true) =====")

    -- 测试带true参数（bit64模式）
    local tick_str, tick_per = mcu.tick64(true)

    -- 断言1: 返回值1类型检查
    assert(type(tick_str) == "string", "mcu.tick64(true)返回值1类型错误: 预期string类型")

    -- 断言2: 返回值2类型检查
    assert(type(tick_per) == "number", "mcu.tick64(true)返回值2类型错误: 预期number类型")

    -- 断言3: 检查bit64格式（如果支持，长度为9字节）
    local is_valid_length = (#tick_str == 8 or #tick_str == 9)
    assert(is_valid_length, string.format("bit64格式长度异常: 预期8或9字节, 实际 %d 字节", #tick_str))

    -- 断言4: tick_per 应为非负数
    assert(tick_per >= 0, string.format("tick_per应为非负数: 实际 %d", tick_per))
end

function mcu_tests.test_mcu_dtick64()
    log.info("===== 测试 mcu.dtick64() =====")

    -- 获取两个时间点
    local tick1, _ = mcu.tick64()
    sys.wait(1000) -- 等待1秒
    local tick2, _ = mcu.tick64()

    -- 测试基本功能
    local result, diff_tick = mcu.dtick64(tick2, tick1)
    assert(type(result) == "boolean",
        string.format("mcu.dtick64()返回值1类型错误: 预期类型：boolean, 实际类型 %s", type(result)))
    assert(type(diff_tick) == "number", string.format(
        "mcu.dtick64()返回值2类型错误: 预期类型：number, 实际类型 %s", type(diff_tick)))
    assert(diff_tick > 0, string.format("mcu.dtick64()差值异常: 应为正数, 实际 %d", diff_tick))

    -- 测试带参考值
    local hz = mcu.hz()
    local expected_min_ticks = hz * 0.9 -- 至少900ms
    local result_with_ref, diff_tick_with_ref = mcu.dtick64(tick2, tick1, expected_min_ticks)
    assert(result_with_ref == true, string.format("带参考值测试失败: 差值 %d 应大于等于参考值 %d",
        diff_tick_with_ref, expected_min_ticks))

    log.info("dtick64测试: result=", result, "diff_tick=", diff_tick)
    log.info("带参考值测试: result=", result_with_ref, "diff_tick=", diff_tick_with_ref)
end

function mcu_tests.test_mcu_hardfault()
    log.info("===== 测试 mcu.hardfault() =====")

    -- 测试所有模式
    local valid_modes = {0, 1, 2}
    for _, mode in ipairs(valid_modes) do
        -- 测试函数调用不报错
        local success, err = pcall(mcu.hardfault, mode)
        assert(success, string.format("mcu.hardfault(%d)调用失败: %s", mode, tostring(err)))
        log.info(string.format("hardfault模式 %d 配置成功", mode))
        sys.wait(10) -- 短暂等待
    end

    -- 测试无效参数
    local success_invalid, _ = pcall(mcu.hardfault, "invalid")
    assert(success_invalid ~= true, "mcu.hardfault()应拒绝无效参数")

end

function mcu_tests.test_mcu_dtick64_basic()
    log.info("===== 测试 mcu.dtick64() 基本功能 =====")

    -- 获取两个时间点
    local tick1, _ = mcu.tick64()
    log.info("获取第一个时间点: tick1")

    sys.wait(500) -- 等待500ms
    local tick2, _ = mcu.tick64()
    log.info("获取第二个时间点: tick2")

    -- 测试基本功能
    local result, diff_tick = mcu.dtick64(tick2, tick1)

    -- 断言1: 返回值类型检查
    assert(type(result) == "boolean" and result == true, string.format(
        "返回值1类型错误或返回值错误: 预期类型boolean, 预期值为:true 实际类型为 %s,实际值为%s",
        type(result), result))

    -- 断言2: 差值类型检查
    assert(type(diff_tick) == "number",
        string.format("返回值2类型错误: 预期number, 实际 %s", type(diff_tick)))

    -- 断言3: 差值应为正数（tick2 > tick1）
    assert(diff_tick > 0,
        string.format("差值异常: tick2应在tick1之后, 差值应为正数, 实际 %d", diff_tick))

end

function mcu_tests.test_mcu_dtick64()
    log.info("===== 测试 mcu.dtick64()check_value非0测试 =====")

    -- 获取两个时间点
    local tick1, _ = mcu.tick64()
    log.info("获取第一个时间点: tick1")

    sys.wait(500) -- 等待500ms
    local tick2, _ = mcu.tick64()
    log.info("获取第二个时间点: tick2")

    -- 测试基本功能(diff_tick > check_value)
    local result, diff_tick = mcu.dtick64(tick2, tick1, 200)

    -- 断言1: 返回值类型检查
    assert(type(result) == "boolean" and result == true, string.format(
        "diff_tick > check_value时返回值1类型错误或返回值错误: 预期类型boolean, 预期值为:true 实际类型为 %s,实际值为%s",
        type(result), result))

    -- 断言2: 差值类型检查
    assert(type(diff_tick) == "number",
        string.format("diff_tick > check_value时返回值2类型错误: 预期number, 实际 %s", type(diff_tick)))

    -- 断言3: 差值应为正数（tick2 > tick1） 
    log.info("diff_tick", diff_tick)
    assert(diff_tick > 0,
        string.format("diff_tick > check_value时差值异常: tick2应在tick1之后, 差值应为正数, 实际 %d",
            diff_tick))

    -- 测试基本功能(diff_tick < check_value)  
    local result, diff_tick = mcu.dtick64(tick2, tick1, diff_tick + 20)
    -- 断言1: 返回值类型检查
    assert(type(result) == "boolean" and result == false, string.format(
        "diff_tick < check_value时返回值1类型错误或返回值错误: 预期类型boolean, 预期值为:false 实际类型为 %s,实际值为%s",
        type(result), result))

    -- 断言2: 差值类型检查
    assert(type(diff_tick) == "number",
        string.format("diff_tick < check_value时返回值2类型错误: 预期number, 实际 %s", type(diff_tick)))

    -- 断言3: 差值应为正数（tick2 > tick1）
    assert(diff_tick > 0,
        string.format("diff_tick < check_value时差值异常: tick2应在tick1之后, 差值应为正数, 实际 %d",
            diff_tick))
end
function mcu_tests.test_mcu_ticks2()
    local valid_modes = {0, 1, 2}
    for _, mode in ipairs(valid_modes) do
        local high, low = mcu.ticks2(mode)
        assert(type(high) == "number" and type(low) == "number",
            string.format(
                "mcu_ticks2返回值类型错误: 预期number, 返回值1实际类型%s，返回值2实际类型",
                type(high), type(low)))
        assert(high >= 0, string.format("mcu.ticks2(%d)高部分应为非负数", mode))
        assert(low >= 0, string.format("mcu.ticks2(%d)低部分应为非负数", mode))
    end
    -- 递增性验证
    local h1, l1 = mcu.ticks2(0)
    sys.wait(10)
    local h2, l2 = mcu.ticks2(0)
    local is_increasing = (h2 > h1) or (h2 == h1 and l2 > l1)
    assert(is_increasing, "ticks2()返回值应随时间递增")
end


return mcu_tests
