local protobuf_tests = {}
--

function protobuf_tests.protobufFile()
    local test_pb_file = "/luadb/person.pb"
    local success, bytesRead = protobuf.load(io.readFile(test_pb_file))
    local test_data = {
        name = "xu",
        id = 123,
        email = "test@example.com"
    }
    return success, bytesRead, test_data
end
-- 测试protobuf.load()接口
-- 测试内容: 加载 Protocol Buffers 二进制定义数据到系统中。
-- 预期结果: 加载成功且长度大于0
-- 注意事项：加载的数据必须是通过 protoc.exe 程序转换得到的二进制数据，否则会加载失败。

function protobuf_tests.test_protobuf_load()
    log.info("test", "测试1: protobuf.load")
    local success, bytesRead, _ = protobuf_tests.protobufFile()
    local pb_data = io.readFile("/luadb/person.pb", "rb")
    assert(success == true, "protobuf.load应该返回成功")
    assert(type(bytesRead) == "number", "bytesRead应该是数字类型")
    assert(bytesRead > 0, "bytesRead应该大于0")
    log.info("test", "✓ protobuf.load测试通过")
end
-- 测试protobuf.encode接口（出错的情况1）
-- 测试内容: 不能编码无效的类型名称否则报错
-- 预期结果: 报错，由pcall()将错误原因抛出。

function protobuf_tests.test_protobuf_encodeInvaidTpname()
    log.info("test", "测试2: protobuf.encode()无效类型名称")
    local _, _, test_data = protobuf_tests.protobufFile()
    local success, err = pcall(function()
        protobuf.encode("InvalidType", test_data) -- 'InvalidType'不是有效的类型名称
    end)
    assert(success == false, "无效类型名称应该返回错误")
    log.info("pack", "类型名称无效返回错误:", err)
    log.info("test", "✓ protobuf.load()InvaidTpname会报错")
end
-- 测试protobuf.encode接口（出错的情况2）
-- 测试内容: 类型名称大小写与 pb 文件的定义的不完全一致报错
-- 预期结果: 报错，由pcall()将错误原因抛出。

function protobuf_tests.test_protobuf_encodeCapitalizationError()
    log.info("test", "测试3: protobuf.encode()类型名称大小写错误")
    local _, _, test_data = protobuf_tests.protobufFile()
    local success, err = pcall(function()
        protobuf.encode("person", test_data) -- tpname的大小写与定义不一致
    end)
    assert(success == false, "类型名称大小写错误应该返回错误")
    log.info("pack", "类型名称大小写错误返回错误:", err)
    log.info("test", "✓ protobuf.load()类型名称大小写不一致会报错")
end

-- 测试protobuf.encode接口（出错的情况3）
-- 测试内容: 待编码数据与 pb 文件中定义的字段不匹配结果异常
-- 预期结果: 返回的string长度异常.

function protobuf_tests.test_protobuf_encodeErrorData()
    log.info("test", "测试4: protobuf.encode错误待编码数据")

    local test_pb_file = "/luadb/person.pb"
    local success, bytesRead = protobuf.load(io.readFile(test_pb_file))
    local test_data1 = {
        name = "",
        emails = {"a@example.com", "b@example.com"},
        id = "12"
    }
       local success =  protobuf.encode("Person", test_data1) -- test_data1
    assert(#success ~= 0, "错误待编码数据应该返回错误")
    log.info("test", "✓ protobuf.load()编码数据与定义不一致会报错")
end

-- 测试protobuf.encode接口（正常情况）
-- 测试内容: 数据类型名称和待编码数据必须与 pb 文件中定义严格匹配，否则报错
-- 预期结果: 返回值不为nil,长度大于0

function protobuf_tests.test_protobuf_encode()
    log.info("test", "测试5: protobuf.encode")
    local _, _, test_data = protobuf_tests.protobufFile()
    local expected_protobuf = "0A027875107B1A1074657374406578616D706C652E636F6D"
    local pbdata = protobuf.encode("Person", test_data)
    assert(pbdata ~= nil, "protobuf.encode应该返回非nil值")
    assert(type(pbdata) == "string", "编码结果应该是字符串类型")
    assert(#pbdata > 0 and pbdata:toHex() == expected_protobuf,
        string.format("protobuf.encode()结果应该有内容且与预期相符: 预期 %s, 实际 %s",
            expected_protobuf, pbdata:toHex()))
    log.info("test", "✓ protobuf.encode测试通过，编码长度: " .. #pbdata)
end

-- 测试protobuf.decode接口（正常情况）
-- 测试内容: 数据类型名称和待编码数据必须与 pb 文件中定义严格匹配，否则报错
-- 预期结果: 返回值与待编码数据一致,且为table类型

function protobuf_tests.test_protobuf_decode()
    -- 测试3: protobuf.decode 函数
    log.info("test", "测试6: protobuf.decode")
    local _, _, test_data = protobuf_tests.protobufFile()
    local pbdata = protobuf.encode("Person", test_data)
    local decoded_data = protobuf.decode("Person", pbdata)
    assert(decoded_data ~= nil and type(decoded_data) == "table",
        "protobuf.decode应该返回非nil值且是table类型")
    assert(decoded_data.name == test_data.name, "name字段应该匹配")
    assert(decoded_data.id == test_data.id, "id字段应该匹配")
    assert(decoded_data.email == test_data.email, "email字段应该匹配")
    log.info("test", "✓ protobuf.decode测试通过")
end

-- 测试protobuf.clear接口后再调用protobuf.load
-- 测试内容: 测试重新加载是否成功
-- 预期结果: 返回值与初次加载一致
function protobuf_tests.test_protobufCLear_load()
    -- 测试4: protobuf.clear后重新加载pb文件
    log.info("test", "测试7: protobuf.clear相关操作")
    local success, bytesRead, _ = protobuf_tests.protobufFile()
    assert(success == true and bytesRead > 0, "首次protobuf.load应该返回成功")
    protobuf.clear()
    local test_pb_file = "/luadb/person.pb"
    local success1, bytesRead1 = protobuf.load(io.readFile(test_pb_file))
    assert(success == success1 and bytesRead == bytesRead1,
        "protobuf.clear后重新加载pb文件应该返回成功,且长度应保持一致")
    log.info("test", "✓ protobuf.decode测试通过")
end
-- 测试protobuf.clear接口后再调用protobuf.encode
-- 测试内容: protobuf.clear()后不重新加载pb文件,直接编码
-- 预期结果: 报错,pacll抛出异常
function protobuf_tests.test_protobufCLear_encode()
    -- 测试4: protobuf.clear后encode()pb文件
    log.info("test", "测试8: protobuf.clear相关操作")
    local success, bytesRead, test_data = protobuf_tests.protobufFile()
    protobuf.clear()
    local success, err = pcall(function()
        protobuf.encode("Person", test_data)
    end)
    assert(success == false, "无效类型名称应该返回错误")
    log.info("pack", "无效类型名称正确返回错误:", err)
    log.info("test", "✓ protobuf.clear后不能通过protobuf.encode()对pb文件进行操作")
end
-- 测试protobuf.clear接口后再调用protobuf.decode
-- 测试内容: protobuf.clear()后不重新加载pb文件,直接解码
-- 预期结果: 报错,pacll抛出异常

function protobuf_tests.test_protobufCLear_decode()
    -- 测试4: protobuf.clear后decode()pb文件
    log.info("test", "测试9: protobuf.clear相关操作")
    local success, bytesRead, test_data = protobuf_tests.protobufFile()
    local pbdata = protobuf.encode("Person", test_data)
    protobuf.clear()
    local success, err = pcall(function()
        protobuf.decode("Person", pbdata)
    end)
    assert(success == false, "无效类型名称应该返回错误")
    log.info("pack", "无效类型名称正确返回错误:", err)

    log.info("test", "✓ protobuf.clear后不能通过protobuf.decode()对pb文件进行操作")
end
-- 测试protobuf.clear接口后再调用protobuf.decode
-- 测试内容: protobuf.clear()后重新加载pb文件后再解码
-- 预期结果: 报错,pacll抛出异常

function protobuf_tests.test_protobufRepeatedLoaded()
    -- 测试10: 测试10: protobuf.clear后调用load/encode/deconde
    log.info("test", "测试10: protobuf.clear后调用load/encode/deconde")
    local test_pb_file = "/luadb/person.pb"
    local success, bytesRead = protobuf.load(io.readFile(test_pb_file))
    assert(success == true and bytesRead > 0, "首次protobuf.load应该返回成功")
    protobuf.clear()
    -- 重新加载
    local success1, bytesRead1, test_data = protobuf_tests.protobufFile()
    assert(success == success1 and bytesRead == bytesRead1,
        "protobuf.clear后重新加载pb文件应该返回成功,且长度应保持一致")
    local expected_protobuf = "0A027875107B1A1074657374406578616D706C652E636F6D"
    -- 重新调用encode
    local pbdata = protobuf.encode("Person", test_data)
    assert(pbdata ~= nil and pbdata:toHex() == expected_protobuf,
        string.format(
            "重新加载后，调用protobuf.encode()结果应不为nil且与预期相符: 预期 %s, 实际 %s",
            expected_protobuf, pbdata:toHex()))
    -- 重新调用decode
    local decoded_data = protobuf.decode("Person", pbdata)
    assert(decoded_data ~= nil and type(decoded_data) == "table",
        "protobuf.decode应该返回非nil值且是table类型")
    assert(decoded_data.name == test_data.name, "name字段应该匹配")
    assert(decoded_data.id == test_data.id, "id字段应该匹配")
    assert(decoded_data.email == test_data.email, "email字段应该匹配")
    log.info("test", "✓ protobuf.clear后调用load/encode/deconde测试通过")
end

return protobuf_tests
