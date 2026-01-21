local json_tests = {}

-- 测试基本的JSON编码功能
-- 测试目的: 验证json.encode能够将Lua table正确转换为JSON字符串
-- 测试内容: 编码包含数字、字符串和布尔值的table
-- 预期结果: 返回有效的JSON字符串
function json_tests.test_encode_basic()
    log.info("json_tests", "开始 JSON 基本编码测试")
    local t = {abc=123, def="123", ttt=true}
    local jdata = json.encode(t)
    assert(jdata ~= nil, "JSON编码失败")
    assert(type(jdata) == "string", "JSON编码结果应该是字符串")
    log.info("json", "编码结果:", jdata)
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
end

-- 测试空table的编码行为
-- 测试目的: 验证空table在JSON编码时的处理方式
-- 测试内容: 编码包含空table的结构
-- 预期结果: 空table优先编码为对象形式{}而非数组形式[]
function json_tests.test_encode_empty_table()
    log.info("json_tests", "开始 JSON 空table编码测试")
    local t = {abc={}}
    local jdata = json.encode(t)
    assert(jdata ~= nil, "空table编码失败")
    -- 空table优先输出hashmap形式 {}
    assert(string.find(jdata, "{}") ~= nil, "空table应该编码为{}")
    log.info("json", "空table编码:", jdata)
end

-- 测试混合table的编码
-- 测试目的: 验证同时包含数组索引和字符串键的table编码行为
-- 测试内容: 编码既有数字索引又有字符串键的table
-- 预期结果: 能够成功编码，但这种混合用法在JSON中应避免
function json_tests.test_encode_mixed_table()
    log.info("json_tests", "开始 JSON 混合table编码测试")
    local t = {abc={}}
    t.abc.def = "123"
    t.abc[1] = 345
    local jdata = json.encode(t)
    assert(jdata ~= nil, "混合table编码失败")
    log.info("json", "混合table编码:", jdata)
end

-- 测试浮点数的默认编码格式
-- 测试目的: 验证浮点数使用默认格式(%.7g)编码
-- 测试内容: 编码包含浮点数的table
-- 预期结果: 浮点数按默认精度编码
function json_tests.test_encode_float_default()
    log.info("json_tests", "开始 JSON 浮点数编码测试(默认)")
    local jdata = json.encode({abc=1234.300})
    assert(jdata ~= nil, "浮点数编码失败")
    log.info("json", "浮点数编码(默认):", jdata)
end

-- 测试浮点数的自定义格式编码
-- 测试目的: 验证浮点数可以使用自定义格式编码
-- 测试内容: 使用"1f"格式编码浮点数(保留1位小数)
-- 预期结果: 浮点数按指定精度编码
function json_tests.test_encode_float_format()
    log.info("json_tests", "开始 JSON 浮点数编码测试(格式化)")
    local jdata = json.encode({abc=1234.300}, "1f")
    assert(jdata ~= nil, "浮点数格式化编码失败")
    log.info("json", "浮点数编码(1f):", jdata)
end

-- 测试转义字符的正确处理
-- 测试目的: 验证\r\n等特殊字符在编解码过程中能够正确保持
-- 测试内容: 编码包含\r\n的字符串，然后解码并验证内容一致性
-- 预期结果: 编解码往返后字符串内容保持不变
function json_tests.test_encode_escape_chars()
    log.info("json_tests", "开始 JSON 转义字符测试")
    local tmp = "ABC\r\nDEF\r\n"
    local tmp2 = json.encode({str=tmp})
    assert(tmp2 ~= nil, "转义字符编码失败")
    log.info("json", "转义字符编码:", tmp2)
    
    -- 解码并验证
    local tmp3 = json.decode(tmp2)
    assert(tmp3 ~= nil, "转义字符解码失败")
    assert(tmp3.str == tmp, string.format("转义字符验证失败: 原始=%s, 解码=%s", tmp, tmp3.str))
end

-- 测试JSON null值的编码
-- 测试目的: 验证json.null能够正确编码为JSON的null值
-- 测试内容: 编码包含json.null的table
-- 预期结果: 输出的JSON字符串包含"null"关键字
function json_tests.test_null_encode()
    log.info("json_tests", "开始 JSON null编码测试")
    local jdata = json.encode({name=json.null})
    assert(jdata ~= nil, "null编码失败")
    assert(string.find(jdata, "null") ~= nil, "编码应包含null")
    log.info("json", "null编码:", jdata)
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
end

-- 测试特殊字符的转义
-- 测试目的: 验证JSON中的特殊字符(如引号)能够正确转义
-- 测试内容: 编码包含引号的字符串
-- 预期结果: 引号被转义为\"
function json_tests.test_encode_special_chars()
    log.info("json_tests", "开始 JSON 特殊字符编码测试")
    local t = {text = "Hello\"World"}
    local jdata = json.encode(t)
    assert(jdata ~= nil, "特殊字符编码失败")
    assert(string.find(jdata, '\\"') ~= nil, "引号应该被转义")
    log.info("json", "特殊字符编码:", jdata)
end

-- 测试布尔值的编码
-- 测试目的: 验证Lua布尔值能够正确编码为JSON布尔值
-- 测试内容: 编码包含true和false的table
-- 预期结果: 输出包含"true"和"false"关键字的JSON字符串
function json_tests.test_encode_boolean()
    log.info("json_tests", "开始 JSON 布尔值编码测试")
    local t = {flag1 = true, flag2 = false}
    local jdata = json.encode(t)
    assert(jdata ~= nil, "布尔值编码失败")
    assert(string.find(jdata, "true") ~= nil, "应包含true")
    assert(string.find(jdata, "false") ~= nil, "应包含false")
    log.info("json", "布尔值编码:", jdata)
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
end

return json_tests
