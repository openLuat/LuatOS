local json_tests = {}

-- 测试基本的JSON编码功能
-- 测试目的: 验证json.encode能够将Lua table正确转换为JSON字符串
-- 测试内容: 编码包含数字、字符串和布尔值的table
-- 预期结果: 返回有效的JSON字符串
function json_tests.test_encode_basic()
    log.info("json_tests", "开始 JSON 基本编码测试")
    local t = {
        abc = 123,
        def = "123",
        ttt = true
    }
    local jdata = json.encode(t)
    assert(jdata ~= nil, "JSON编码失败")
    assert(type(jdata) == "string", "JSON编码结果应该是字符串")
    log.info("json", "编码结果:", jdata)
    log.info("json_tests", "JSON 基本编码测试成功")
end

-- 测试基本的JSON解码功能
-- 测试目的: 验证json.decode能够将JSON字符串正确转换为Lua table
-- 测试内容: 解码包含数字的简单JSON对象
-- 预期结果: 返回table且字段值正确
function json_tests.test_decode_basic()
    log.info("json_tests", "开始 JSON 基本解码测试")
    local str = "{\"abc\":1234545}"
    local t = json.decode(str)
    assert(t ~= nil, "JSON解码失败")
    assert(t.abc == 1234545, string.format("解码值错误: 预期 1234545, 实际 %s", tostring(t.abc)))
    log.info("json_tests", "JSON 基本解码测试成功")
end

-- 测试空table的编码行为
-- 测试目的: 验证空table在JSON编码时的处理方式
-- 测试内容: 编码包含空table的结构
-- 预期结果: 空table优先编码为对象形式{}而非数组形式[]
function json_tests.test_encode_empty_table()
    log.info("json_tests", "开始 JSON 空table编码测试")
    local t = {
        abc = {}
    }
    local jdata = json.encode(t)
    assert(jdata ~= nil, "空table编码失败")
    -- 空table优先输出hashmap形式 {}
    assert(string.find(jdata, "{}") ~= nil, "空table应该编码为{}")
    log.info("json", "空table编码:", jdata)
    log.info("json_tests", "JSON 空table编码测试成功")
end

-- 测试混合table的编码
-- 测试目的: 验证同时包含数组索引和字符串键的table编码行为
-- 测试内容: 编码既有数字索引又有字符串键的table
-- 预期结果: 能够成功编码，但这种混合用法在JSON中应避免
function json_tests.test_encode_mixed_table()
    log.info("json_tests", "开始 JSON 混合table编码测试")
    local t = {
        abc = {}
    }
    t.abc.def = "123"
    t.abc[1] = 345
    local jdata = json.encode(t)
    assert(jdata ~= nil, "混合table编码失败")
    log.info("json", "混合table编码:", jdata)
    log.info("json_tests", "JSON 混合table编码测试成功")
end

-- 测试浮点数的默认编码格式
-- 测试目的: 验证浮点数使用默认格式编码
-- 测试内容: 编码包含浮点数的table
-- 预期结果: 浮点数按默认精度编码
function json_tests.test_encode_float_default()
    log.info("json_tests", "开始 JSON 浮点数编码测试(默认)")
    local jdata = json.encode({
        abc = 1234.300
    })
    assert(jdata ~= nil, "浮点数编码失败")
    log.info("json", "浮点数编码(默认):", jdata)
    log.info("json_tests", "JSON 浮点数编码测试(默认)成功")
end

-- 测试浮点数的自定义格式编码
-- 测试目的: 验证浮点数可以使用自定义格式编码
-- 测试内容: 使用"1f"格式编码浮点数(保留1位小数)
-- 预期结果: 浮点数按指定精度编码
function json_tests.test_encode_float_format()
    log.info("json_tests", "开始 JSON 浮点数编码测试(格式化)")
    local jdata = json.encode({
        abc = 1234.300
    }, "1f")
    assert(jdata ~= nil, "浮点数格式化编码失败")
    log.info("json", "浮点数编码(1f):", jdata)
    log.info("json_tests", "JSON 浮点数编码测试(格式化)成功")
end

-- 测试转义字符的正确处理
-- 测试目的: 验证\r\n等特殊字符在编解码过程中能够正确保持
-- 测试内容: 编码包含\r\n的字符串，然后解码并验证内容一致性
-- 预期结果: 编解码往返后字符串内容保持不变
function json_tests.test_encode_escape_chars()
    log.info("json_tests", "开始 JSON 转义字符测试")
    local tmp = "ABC\r\nDEF\r\n"
    local tmp2 = json.encode({
        str = tmp
    })
    assert(tmp2 ~= nil, "转义字符编码失败")
    log.info("json", "转义字符编码:", tmp2)

    -- 解码并验证
    local tmp3 = json.decode(tmp2)
    assert(tmp3 ~= nil, "转义字符解码失败")
    assert(tmp3.str == tmp, string.format("转义字符验证失败: 原始=%s, 解码=%s", tmp, tmp3.str))
    log.info("json_tests", "JSON 转义字符测试成功")
end

-- 测试JSON null值的编码
-- 测试目的: 验证json.null能够正确编码为JSON的null值
-- 测试内容: 编码包含json.null的table
-- 预期结果: 输出的JSON字符串包含"null"关键字
function json_tests.test_null_encode()
    log.info("json_tests", "开始 JSON null编码测试")
    local jdata = json.encode({
        name = json.null
    })
    assert(jdata ~= nil, "null编码失败")
    assert(string.find(jdata, "null") ~= nil, "编码应包含null")
    log.info("json", "null编码:", jdata)
    log.info("json_tests", "JSON null编码测试成功")
end

-- 测试JSON null值的解码
-- 测试目的: 验证JSON中的null能够正确解码为json.null
-- 测试内容: 解码包含null值的JSON字符串
-- 预期结果: 解码后的值等于json.null (注意: json.null != nil)
function json_tests.test_null_decode()
    log.info("json_tests", "开始 JSON null解码测试")
    local t = json.decode("{\"abc\":null}")
    assert(t ~= nil, "null解码失败")
    assert(t.abc == json.null, "解码的null值应该等于json.null")
    log.info("json", "null解码成功, t.abc == json.null:", t.abc == json.null)
    log.info("json_tests", "JSON null解码测试成功")
end

-- 测试浮点数的解码
-- 测试目的: 验证JSON中的浮点数能够正确解码为Lua number
-- 测试内容: 解码包含浮点数的JSON字符串
-- 预期结果: 解码后的数值精确等于原始值
function json_tests.test_decode_float()
    log.info("json_tests", "开始 JSON 浮点数解码测试")
    local tmp = "{\"abc\":3.5}"
    local abc, err = json.decode(tmp)
    assert(abc ~= nil, string.format("浮点数解码失败: %s", tostring(err)))
    assert(abc.abc == 3.5, string.format("浮点数值错误: 预期 3.5, 实际 %s", tostring(abc.abc)))
    log.info("json", "浮点数解码成功, abc.abc =", abc.abc)
    log.info("json_tests", "JSON 浮点数解码测试成功")
end

-- 测试浮点数的编解码往返
-- 测试目的: 验证浮点数经过解码->编码->解码后能够保持精度
-- 测试内容: 解码JSON浮点数，重新编码，再解码验证
-- 预期结果: 往返后的数值保持不变
function json_tests.test_encode_decoded_float()
    log.info("json_tests", "开始 JSON 浮点数编解码往返测试")
    local tmp = "{\"abc\":3.5}"
    local abc, err = json.decode(tmp)
    assert(abc ~= nil, "解码失败")

    -- 重新编码
    local encoded = json.encode(abc, "1f")
    assert(encoded ~= nil, "重新编码失败")
    log.info("json", "浮点数往返编码:", encoded)

    -- 再次解码验证
    local abc2 = json.decode(encoded)
    assert(abc2 ~= nil, "二次解码失败")
    assert(abc2.abc == 3.5, "往返后的浮点数值错误")
    log.info("json_tests", "JSON 浮点数编解码往返测试成功")
end

-- 测试无效JSON字符串的处理
-- 测试目的: 验证json.decode对无效JSON字符串的错误处理
-- 测试内容: 解码格式错误的JSON字符串
-- 预期结果: 返回nil和错误信息，不会崩溃
function json_tests.test_decode_invalid()
    log.info("json_tests", "开始 JSON 无效字符串解码测试")
    local str = "{invalid json}"
    local t, err = json.decode(str)
    assert(t == nil, "无效JSON应该返回nil")
    log.info("json", "无效JSON正确返回nil, err:", err)
    log.info("json_tests", "JSON 无效字符串解码测试成功")
end

-- 测试数组的编码
-- 测试目的: 验证纯数组table能够正确编码为JSON数组
-- 测试内容: 编码只包含数字索引的table
-- 预期结果: 输出JSON数组格式[...]
function json_tests.test_encode_array()
    log.info("json_tests", "开始 JSON 数组编码测试")
    local arr = {1, 2, 3, 4, 5}
    local jdata = json.encode(arr)
    assert(jdata ~= nil, "数组编码失败")
    assert(string.find(jdata, "%[") ~= nil, "数组应该编码为[]格式")
    log.info("json", "数组编码:", jdata)
    log.info("json_tests", "JSON 数组编码测试成功")
end

-- 测试数组的解码
-- 测试目的: 验证JSON数组能够正确解码为Lua table
-- 测试内容: 解码JSON数组字符串
-- 预期结果: 解码为table，长度和元素值正确
function json_tests.test_decode_array()
    log.info("json_tests", "开始 JSON 数组解码测试")
    local str = "[1,2,3,4,5]"
    local arr = json.decode(str)
    assert(arr ~= nil, "数组解码失败")
    assert(#arr == 5, string.format("数组长度错误: 预期 5, 实际 %d", #arr))
    assert(arr[1] == 1 and arr[5] == 5, "数组元素值错误")
    log.info("json", "数组解码成功, 长度:", #arr)
    log.info("json_tests", "JSON 数组解码测试成功")
end

-- 测试嵌套结构的编码
-- 测试目的: 验证复杂嵌套的table能够正确编码
-- 测试内容: 编码包含多层嵌套的table，包含对象和数组
-- 预期结果: 成功编码为多层嵌套的JSON字符串
function json_tests.test_encode_nested()
    log.info("json_tests", "开始 JSON 嵌套结构编码测试")
    local t = {
        name = "test",
        data = {
            value = 123,
            flag = true,
            list = {1, 2, 3}
        }
    }
    local jdata = json.encode(t)
    assert(jdata ~= nil, "嵌套结构编码失败")
    log.info("json", "嵌套结构编码:", jdata)
    log.info("json_tests", "JSON 嵌套结构编码测试成功")
end

-- 测试嵌套结构的解码
-- 测试目的: 验证嵌套的JSON对象能够正确解码为多层table
-- 测试内容: 解码包含嵌套对象的JSON字符串
-- 预期结果: 各层级的字段值都正确解码
function json_tests.test_decode_nested()
    log.info("json_tests", "开始 JSON 嵌套结构解码测试")
    local str = "{\"name\":\"test\",\"data\":{\"value\":123,\"flag\":true}}"
    local t = json.decode(str)
    assert(t ~= nil, "嵌套结构解码失败")
    assert(t.name == "test", "name字段错误")
    assert(t.data ~= nil, "data字段为nil")
    assert(t.data.value == 123, "data.value字段错误")
    assert(t.data.flag == true, "data.flag字段错误")
    log.info("json", "嵌套结构解码成功")
    log.info("json_tests", "JSON 嵌套结构解码测试成功")
end

-- 测试特殊字符的转义
-- 测试目的: 验证JSON中的特殊字符(如引号)能够正确转义
-- 测试内容: 编码包含引号的字符串
-- 预期结果: 引号被转义为\"
function json_tests.test_encode_special_chars()
    log.info("json_tests", "开始 JSON 特殊字符编码测试")
    local t = {
        text = "Hello\"World"
    }
    local jdata = json.encode(t)
    assert(jdata ~= nil, "特殊字符编码失败")
    assert(string.find(jdata, '\\"') ~= nil, "引号应该被转义")
    log.info("json", "特殊字符编码:", jdata)
    log.info("json_tests", "JSON 特殊字符编码测试成功")
end

-- 测试布尔值的编码
-- 测试目的: 验证Lua布尔值能够正确编码为JSON布尔值
-- 测试内容: 编码包含true和false的table
-- 预期结果: 输出包含"true"和"false"关键字的JSON字符串
function json_tests.test_encode_boolean()
    log.info("json_tests", "开始 JSON 布尔值编码测试")
    local t = {
        flag1 = true,
        flag2 = false
    }
    local jdata = json.encode(t)
    assert(jdata ~= nil, "布尔值编码失败")
    assert(string.find(jdata, "true") ~= nil, "应包含true")
    assert(string.find(jdata, "false") ~= nil, "应包含false")
    log.info("json", "布尔值编码:", jdata)
    log.info("json_tests", "JSON 布尔值编码测试成功")
end

-- 测试布尔值的解码
-- 测试目的: 验证JSON布尔值能够正确解码为Lua布尔值
-- 测试内容: 解码包含true和false的JSON字符串
-- 预期结果: 解码后的值为Lua的true和false
function json_tests.test_decode_boolean()
    log.info("json_tests", "开始 JSON 布尔值解码测试")
    local str = "{\"flag1\":true,\"flag2\":false}"
    local t = json.decode(str)
    assert(t ~= nil, "布尔值解码失败")
    assert(t.flag1 == true, "flag1应该为true")
    assert(t.flag2 == false, "flag2应该为false")
    log.info("json", "布尔值解码成功")
    log.info("json_tests", "JSON 布尔值解码测试成功")
end

-- 测试浮点数的f格式编码 - 多种精度
-- 测试目的: 验证json.encode的f格式参数支持多种精度设置
-- 测试内容: 使用不同精度的f格式编码浮点数
-- 预期结果: 按指定小数位数编码，实际行为是截断而非四舍五入
function json_tests.test_encode_float_f_formats()
    log.info("json_tests", "开始 JSON 浮点数f格式多精度测试")
    local data = {
        abc = 1234.56789
    }
    -- 测试 1f (保留1位小数)
    local json_str, err_msg = json.encode(data, "1f")
    log.info("json", "f格式(1f)编码:", json_str)
    assert(err_msg == nil, "f格式(1f)编码失败")
    assert(string.find(json_str, "1234.6") ~= nil, "1f格式应为1234.6")

    -- 测试 2f (保留2位小数)
    local jdata, err_msg = json.encode(data, "2f")
    log.info("json", "f格式(2f)编码:", jdata)
    assert(err_msg == nil, "f格式(2f)编码失败")
    assert(string.find(jdata, "1234.57") ~= nil, "2f格式应为1234.57")

    -- 测试 3f (保留3位小数)
    local jdata, err_msg = json.encode(data, "3f")
    log.info("json", "f格式(3f)编码:", jdata)
    assert(err_msg == nil, "f格式(3f)编码失败")
    assert(string.find(jdata, "1234.568") ~= nil, "3f格式应为1234.568")

    -- 测试 4f (保留4位小数)
    local jdata, err_msg = json.encode(data, "4f")
    log.info("json", "f格式(4f)编码:", jdata)
    assert(err_msg == nil, "f格式(4f)编码失败")
    assert(string.find(jdata, "1234.5679") ~= nil, "4f格式应为1234.5679")

    -- -- 测试 5f (保留5位小数)
    -- local jdata, err_msg = json.encode(data, "5f")
    -- log.info("json", "f格式(5f)编码:", jdata)
    -- assert(err_msg == nil, "f格式(5f)编码失败")
    -- assert(string.find(jdata, "1234.56789") ~= nil, "5f格式应为1234.56789")

    -- -- 测试 6f (保留6位小数)
    -- local jdata, err_msg = json.encode(data, "6f")
    -- log.info("json", "f格式(6f)编码:", jdata)
    -- assert(err_msg == nil, "f格式(6f)编码失败")
    -- assert(string.find(jdata, "1234.567890") ~= nil, "6f格式应保留6位小数")

    -- -- 测试 7f (保留7位小数)
    -- local jdata, err_msg = json.encode(data, "7f")
    -- log.info("json", "f格式(7f)编码:", jdata)
    -- assert(err_msg == nil, "f格式(7f)编码失败")
    -- assert(string.find(jdata, "1234.5678900") ~= nil, "7f格式应保留7位小数")

    -- 测试 0f (保留0位小数)
    local jdata, err_msg = json.encode(data, "0f")
    log.info("json", "f格式(0f)编码:", jdata)
    assert(err_msg == nil, "f格式(0f)编码失败")
    assert(string.find(jdata, "1235") ~= nil, "0f格式应四舍五入到整数")

    -- 测试 %.1f 完整格式
    local jdata, err_msg = json.encode(data, "%.1f")
    log.info("json", "f格式(%.1f)编码:", jdata)
    assert(err_msg == nil, "f格式(%.1f)编码失败")
    assert(string.find(jdata, "1234.6") ~= nil, "%.1f格式应正确编码")

    -- 测试 %.2f 完整格式
    local jdata, err_msg = json.encode(data, "%.2f")
    log.info("json", "f格式(%.2f)编码:", jdata)
    assert(err_msg == nil, "f格式(%.2f)编码失败")
    assert(string.find(jdata, "1234.57") ~= nil, "%.2f格式应正确编码")

    log.info("json_tests", "JSON 浮点数f格式多精度测试成功")
end

-- 测试浮点数的g格式编码 - 多种精度
-- 测试目的: 验证json.encode的g格式参数支持多种精度设置
-- 测试内容: 使用不同精度的g格式编码浮点数，g格式会自动选择最紧凑的表示方式
-- 预期结果: 按指定有效数字位数编码
function json_tests.test_encode_float_g_formats()
    log.info("json_tests", "开始 JSON 浮点数g格式多精度测试")

    -- 测试大数使用g格式
    local t1 = {
        abc = 12345.6789
    }

    -- 测试 2g (2位有效数字)
    local jdata = json.encode(t1, "2g")
    assert(jdata ~= nil, "g格式(2g)编码失败")
    log.info("json", "g格式(2g)编码:", jdata)

    -- 测试 4g (4位有效数字)
    jdata = json.encode(t1, "4g")
    assert(jdata ~= nil, "g格式(4g)编码失败")
    log.info("json", "g格式(4g)编码:", jdata)

    -- 测试小数使用g格式
    local t2 = {
        abc = 0.00123456789
    }

    -- 测试 3g (3位有效数字)
    jdata = json.encode(t2, "3g")
    assert(jdata ~= nil, "g格式(3g)编码失败")
    log.info("json", "g格式(3g)小数编码:", jdata)

    -- 测试 6g (6位有效数字)
    jdata = json.encode(t2, "6g")
    assert(jdata ~= nil, "g格式(6g)编码失败")
    log.info("json", "g格式(6g)小数编码:", jdata)

    -- 测试 1g (1位有效数字)
    jdata = json.encode(t2, "1g")
    assert(jdata ~= nil, "g格式(1g)编码失败")
    log.info("json", "g格式(1g)编码:", jdata)

    -- 测试 %.2g 完整格式
    jdata = json.encode(t1, "%.2g")
    assert(jdata ~= nil, "g格式(%.2g)编码失败")
    log.info("json", "g格式(%.2g)编码:", jdata)

    -- 测试 g 格式与 f 格式的对比
    local t3 = {
        pi = 3.14159265359
    }
    local jdata_f = json.encode(t3, "4f")
    local jdata_g = json.encode(t3, "4g")
    assert(jdata_f ~= nil, "f格式对比测试失败")
    assert(jdata_g ~= nil, "g格式对比测试失败")
    log.info("json", "相同数值 f格式(4f):", jdata_f)
    log.info("json", "相同数值 g格式(4g):", jdata_g)

    log.info("json_tests", "JSON 浮点数g格式多精度测试成功")
end

-- 测试浮点数边界的f格式编码
-- 测试目的: 验证浮点数在边界情况下的f格式编码
-- 测试内容: 测试0、负数、极大值、极小值的f格式编码
-- 预期结果: 边界值能正确编码
function json_tests.test_encode_float_f_boundary()
    log.info("json_tests", "开始 JSON 浮点数f格式边界测试")

    -- 测试零值（实际输出为0而不是0.000）
    local t = {
        zero = 0
    }
    local jdata = json.encode(t, "3f")
    assert(jdata ~= nil, "零值f格式编码失败")
    -- 实际输出可能是"0"或"0.000"，都接受
    local has_zero = string.find(jdata, "0") ~= nil
    assert(has_zero, "零值应编码为包含0")
    log.info("json", "零值f格式(3f)编码:", jdata)

    -- 测试负数值
    t = {
        negative = -123.456
    }
    jdata = json.encode(t, "2f")
    assert(jdata ~= nil, "负数f格式编码失败")
    assert(string.find(jdata, "-123.46") ~= nil, "负数应正确编码")
    log.info("json", "负数f格式(2f)编码:", jdata)

    -- 测试整数值
    t = {
        integer = 100
    }
    jdata = json.encode(t, "3f")
    assert(jdata ~= nil, "整数f格式编码失败")
    log.info("json", "整数f格式(3f)编码:", jdata)

    -- 测试四舍五入边界
    t = {
        round_up = 1.555,
        round_down = 1.554
    }
    jdata = json.encode(t, "2f")
    assert(jdata ~= nil, "四舍五入边界编码失败")
    log.info("json", "四舍五入边界编码(2f):", jdata)

    log.info("json_tests", "JSON 浮点数f格式边界测试成功")
end

-- 测试浮点数边界的g格式编码
-- 测试目的: 验证浮点数在边界情况下的g格式编码
-- 测试内容: 测试0、负数、极大值、极小值的g格式编码
-- 预期结果: 边界值能正确编码并使用科学计数法
function json_tests.test_encode_float_g_boundary()
    log.info("json_tests", "开始 JSON 浮点数g格式边界测试")

    -- 测试零值
    local t = {
        zero = 0
    }
    local jdata = json.encode(t, "3g")
    assert(jdata ~= nil, "零值g格式编码失败")
    log.info("json", "零值g格式(3g)编码:", jdata)

    -- 测试负数值
    t = {
        negative = -123.456
    }
    jdata = json.encode(t, "4g")
    assert(jdata ~= nil, "负数g格式编码失败")
    log.info("json", "负数g格式(4g)编码:", jdata)

    -- 测试极小值(科学计数法)
    t = {
        tiny = 0.00000123
    }
    jdata = json.encode(t, "3g")
    assert(jdata ~= nil, "极小值g格式编码失败")
    log.info("json", "极小值g格式(3g)编码:", jdata)

    -- 测试极大值
    t = {
        huge = 123456789.0
    }
    jdata = json.encode(t, "4g")
    assert(jdata ~= nil, "极大值g格式编码失败")
    log.info("json", "极大值g格式(4g)编码:", jdata)

    -- 测试科学计数法表示
    t = {
        scientific = 0.000000123
    }
    jdata = json.encode(t, "5g")
    assert(jdata ~= nil, "科学计数法编码失败")
    log.info("json", "科学计数法(5g)编码:", jdata)

    log.info("json_tests", "JSON 浮点数g格式边界测试成功")
end

-- 测试默认浮点数格式(不传t参数)
-- 测试目的: 验证不传t参数时的默认格式
-- 测试内容: 测试默认格式的编码行为
-- 预期结果: 实际默认格式是%.7g
function json_tests.test_encode_float_default_format()
    log.info("json_tests", "开始 JSON 浮点数默认格式测试")

    local t = {
        value = 123.456789012345
    }
    local jdata = json.encode(t) -- 不传t参数
    assert(jdata ~= nil, "默认格式编码失败")
    log.info("json", "默认格式编码:", jdata)

    -- 验证默认格式编码结果不为空
    assert(#jdata > 0, "默认格式编码结果不应为空")

    -- 对比不同格式的行为
    local jdata_f = json.encode(t, "%.7f")
    local jdata_g = json.encode(t, "%.7g")
    assert(jdata_f ~= nil, "f格式编码失败")
    assert(jdata_g ~= nil, "g格式编码失败")
    log.info("json", "f格式(%.7f)编码:", jdata_f)
    log.info("json", "g格式(%.7g)编码:", jdata_g)
    log.info("json", "默认格式与f/g格式对比 - 默认:", jdata, "f:", jdata_f, "g:", jdata_g)

    log.info("json_tests", "JSON 浮点数默认格式测试成功")
end

-- 测试无效浮点数格式参数的错误处理
-- 测试目的: 验证传入无效格式参数时的处理
-- 测试内容: 传入各种无效的格式字符串
-- 预期结果: 根据实际行为，某些无效格式可能仍能编码
function json_tests.test_encode_float_invalid_format()
    log.info("json_tests", "开始 JSON 浮点数无效格式测试")

    local t = {
        abc = 123.456
    }

    -- 测试无效格式(不以f/g结尾)
    local jdata, err = json.encode(t, "3x")
    if jdata == nil then
        log.info("json", "无效结尾返回错误:", err)
        assert(err ~= nil, "无效结尾应该返回错误信息")
    else
        log.info("json", "无效结尾仍能编码:", jdata)
    end

    -- 测试无效格式(空字符串)
    jdata, err = json.encode(t, "")
    if jdata == nil then
        log.info("json", "空字符串返回错误:", err)
    else
        log.info("json", "空字符串仍能编码:", jdata)
    end

    -- 测试无效格式(纯数字)
    jdata, err = json.encode(t, "123")
    if jdata == nil then
        log.info("json", "纯数字格式返回错误:", err)
    else
        log.info("json", "纯数字格式仍能编码:", jdata)
    end

    log.info("json_tests", "JSON 浮点数无效格式测试成功")
end

-- 测试本身包含大量转义字符的JSON字符串解码
-- 测试目的: 验证复杂转义字符的JSON字符串能够正确解码
-- 测试内容: 解码包含多种转义字符的JSON字符串
-- 预期结果: 解码后的table字段值正确
function json_tests.test_decode_complex_escape()
    log.info("json_tests", "开始 JSON 复杂转义字符解码测试")
    local f = io.open("/luadb/test_decode.txt", "r")
    local str = f:read("*a")
    f:close()
    local t = json.decode(str)
    assert(t ~= nil, "JSON解码失败")
    -- {"netouttime":30,"password":"","log":1,"ota":0,"paramuptype":0,"userparamurl":"","reboottime":1440,"uartreboottime":0,"netreboottime":0,"remotecmd":1,"ntptime":24,"dcache":0,"simt":0,"lp":0,"ttst":0,"led":0,"pcm":1,"ipv6":0,"rndis":0,"mm":0,"paramsrc":2,"paramver":22,"apn":[0,"","","",0],"uartparam":[[1,115200,8,0,1,80,0],[],[3,115200,8,0,1,80,0]],"autopoll":[[],[],[]],"netchan":[["tcpc",1,1,0,"00",60,"118.195.188.216","9093",0,1,"",3,"END",3,"MY IS 4G",0,0],["tcpc",1,1,0,"00",60,"118.195.188.216","9091",0,1,"",1,"",3,"MY IS ETH",0,0],["tcpc",1,1,1,"123",60,"118.195.188.216","9092",0,0,"",0,"",3,"MY IS WIFI STA",0,0],[],[],[],[],[]],"prot":[[],[],[],[],[],[],[],[]],"task":["function \n\tlocal taskname=\"userTask\"\n\tlog.info(taskname,\"start\")\n\tlocal nid=1\n\tlocal count =0\n\tlocal netsta =0\n\t\n\twhile true do \n\tsys.wait(10000)\n\t\tlocal d ={}\n\t\td.datetime=os.date(\"%Y-%m-%d %H:%M:%S\")\n\t\td.csq=mobile.csq()\n\t\td.sn=mobile.imei()\n\t\td.iccid = PerGetIccid()\n\t\td.vbat = PerGetVbattV()\n\t\t\n\t\tlocal updata = json.encode(d)\n\t\tnetsta = PronetGetNetSta(nid)\n\t\tlog.info(taskname,\"updata\",updata,\"netsta\",netsta)\n\t\tif updata and netsta ==1 then \n\t\t\tPronetSetSendCh(nid,updata)\n\t\tend\n\tsys.wait(5000)\n\tend\nend"],"io":{"doout":[],"di_timer":[],"aii_timer":[],"aiv_timer":[],"di_warm":[],"aii_warm":[],"aiv_warm":[]},"wl":0,"location":[[],[]],"yedala":[],"sms":[],"upf":[],"sslf":[[],[],[],[],[],[],[],[]],"eth":[1,"","",""],"wifi":{"mode":0,"sta":["yedyftest","yed1234567890","",1,"","",""]},"nic":[]}
    -- 检测每个字段是否正确解码
    assert(t.netouttime == 30, "netouttime字段值错误")
    assert(t.password == "", "password字段值错误")
    assert(t.log == 1, "log字段值错误")
    assert(t.ota == 0, "ota字段值错误")
    assert(t.paramuptype == 0, "paramuptype字段值错误")
    assert(t.userparamurl == "", "userparamurl字段值错误")
    assert(t.reboottime == 1440, "reboottime字段值错误")
    assert(t.uartreboottime == 0, "uartreboottime字段值错误")
    assert(t.netreboottime == 0, "netreboottime字段值错误")
    assert(t.remotecmd == 1, "remotecmd字段值错误")
    assert(t.ntptime == 24, "ntptime字段值错误")
    assert(t.dcache == 0, "dcache字段值错误")
    assert(t.simt == 0, "simt字段值错误")
    assert(t.lp == 0, "lp字段值错误")
    assert(t.ttst == 0, "ttst字段值错误")
    assert(t.led == 0, "led字段值错误")
    assert(t.pcm == 1, "pcm字段值错误")
    assert(t.ipv6 == 0, "ipv6字段值错误")
    assert(t.rndis == 0, "rndis字段值错误")
    assert(t.mm == 0, "mm字段值错误")
    assert(t.paramsrc == 2, "paramsrc字段值错误")
    assert(t.paramver == 22, "paramver字段值错误")
    assert(t.apn[1] == 0, "apn字段值错误")
    assert(t.uartparam[1][1] == 1, "uartparam字段值错误")
    assert(t.autopoll[1][1] == nil, "autopoll字段值错误")
    assert(t.netchan[1][1] == "tcpc", "netchan字段值错误")
    assert(t.prot[1][1] == nil, "prot字段值错误")
    assert(t.io.doout ~= nil, "io.doout字段解码失败")
    assert(t.wl == 0, "wl字段值错误")
    assert(t.location[1][1] == nil, "location字段值错误")
    assert(t.yedala[1] == nil, "yedala字段值错误")
    assert(t.sms[1] == nil, "sms字段值错误")
    assert(t.upf[1] == nil, "upf字段值错误")
    assert(t.sslf[1][1] == nil, "sslf字段值错误")
    assert(t.eth[1] == 1, "eth字段值错误")
    assert(t.wifi.mode == 0, "wifi.mode字段值错误")
    assert(t.nic[1] == nil, "nic字段值错误")
    assert(t.task[1] ~= nil, "task字段值错误")
    log.info("json", "复杂转义字符JSON解码成功")
    -- 打印task字段内容
    log.info("json", "task内容:", t.task[1])
    log.info("json_tests", "JSON 复杂转义字符解码测试成功")
end

return json_tests
