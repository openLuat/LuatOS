-- string 标准库与 LuatOS 扩展函数混合测试
-- 覆盖正例与反例，确保基础行为与扩展保持一致

local string_tests = {}

-- 正例：基础 find/sub/gsub 组合
-- 目的：验证原生 string 模式匹配与替换的常见路径
function string_tests.test_native_pattern_ops()
    log.info("string_tests", "开始 原生模式匹配测试")
    local text = "hello-lua-world"
    local s, e = string.find(text, "lua")
    assert(s == 7 and e == 9, "string.find 位置不符")

    local middle = string.sub(text, s, e)
    assert(middle == "lua", "string.sub 截取结果错误")

    local replaced, cnt = string.gsub(text, "-", "_")
    assert(replaced == "hello_lua_world", "string.gsub 替换结果错误")
    assert(cnt == 2, "string.gsub 替换次数错误")
end

-- 反例：错误参数应触发异常
-- 目的：传入非字符串模式时应抛出错误，不应静默处理
function string_tests.test_native_find_invalid_pattern()
    log.info("string_tests", "开始 非法模式参数测试")
    local ok, err = pcall(function()
        return string.find("abc", {})
    end)
    assert(ok == false, "非法模式应触发异常")
    assert(err and err:match("string expected"), "错误信息应包含 string expected")
end

-- 正例：扩展 toHex/fromHex 往返
-- 目的：验证 LuatOS 扩展的十六进制转换，可与原生 upper/lower 配合
function string_tests.test_extend_hex_roundtrip()
    log.info("string_tests", "开始 toHex/fromHex 往返测试")
    local toHex = string.toHex or ("").toHex
    local fromHex = string.fromHex or ("").fromHex

    assert(type(toHex) == "function", "string.toHex 未提供")
    assert(type(fromHex) == "function", "string.fromHex 未提供")

    local raw = "\x01\xABLua"
    local hex = toHex(raw)
    assert(type(hex) == "string" and #hex == #raw * 2, "toHex 返回内容异常")

    -- 转回原文并允许大小写差异
    local decoded = fromHex(hex)
    assert(decoded == raw, "fromHex 未能还原原始数据")

    local decoded_lower = fromHex(string.lower(hex))
    assert(decoded_lower == raw, "fromHex 应支持小写输入")
end

-- 正例：toHex 支持分隔符且返回长度
-- 目的：验证扩展的可选分隔符与返回值数量
function string_tests.test_extend_hex_with_separator()
    log.info("string_tests", "开始 toHex 分隔符测试")
    local toHex = string.toHex or ("").toHex
    assert(type(toHex) == "function", "string.toHex 未提供")

    local raw = "AB"
    local hex, hex_len = toHex(raw, " ")
    assert(hex == "41 42 ", "带分隔符的 toHex 结果不符")
    assert(hex_len == 4, "toHex 返回的长度应为原字节数*2")
end

-- 反例：toHex / fromHex 输入非法字符会被忽略
-- 目的：验证扩展函数对异常数据的宽容处理，而非抛错
function string_tests.test_extend_hex_invalid_inputs()
    log.info("string_tests", "开始 toHex/fromHex 异常输入测试")
    local toHex = string.toHex or ("").toHex
    local fromHex = string.fromHex or ("").fromHex

    assert(type(toHex) == "function", "string.toHex 未提供")
    assert(type(fromHex) == "function", "string.fromHex 未提供")

    local ok_tohex = pcall(toHex, nil)
    assert(ok_tohex == false, "toHex 传入非字符串应报错")

    -- fromHex 对非法字符会直接跳过，不会抛错
    local ok_badchars, res_badchars = pcall(fromHex, "GG11ZZ22")
    assert(ok_badchars == true, "fromHex 不应因非法字符崩溃")
    assert(res_badchars == "\x11\x22", "非法字符应被忽略，仅保留有效字节")

    -- 奇数长度时末尾半字节会被丢弃
    local ok_oddlen, res_oddlen = pcall(fromHex, "ABC")
    assert(ok_oddlen == true, "fromHex 奇数长度不应抛错")
    assert(res_oddlen == "\xAB", "奇数长度应丢弃最后半字节")
end

-- 正例：Base64 编解码往返
-- 目的：验证 toBase64/fromBase64 对称性
function string_tests.test_extend_base64_roundtrip()
    log.info("string_tests", "开始 Base64 往返测试")
    local toBase64 = string.toBase64 or ("").toBase64
    local fromBase64 = string.fromBase64 or ("").fromBase64

    assert(type(toBase64) == "function", "string.toBase64 未提供")
    assert(type(fromBase64) == "function", "string.fromBase64 未提供")

    local raw = "hello"
    local encoded = toBase64(raw)
    assert(encoded == "aGVsbG8=", "Base64 编码结果不符")

    local decoded = fromBase64(encoded)
    assert(decoded == raw, "Base64 解码结果不符")
end

-- 反例：Base64 输入非法时返回空串
-- 目的：确认解码失败不会崩溃且结果为空
function string_tests.test_extend_base64_invalid()
    log.info("string_tests", "开始 Base64 异常输入测试")
    local toBase64 = string.toBase64 or ("").toBase64
    local fromBase64 = string.fromBase64 or ("").fromBase64

    assert(type(toBase64) == "function", "string.toBase64 未提供")
    assert(type(fromBase64) == "function", "string.fromBase64 未提供")

    local ok_tob64 = pcall(toBase64, nil)
    assert(ok_tob64 == false, "toBase64 传入非字符串应报错")

    local ok_bad, decoded = pcall(fromBase64, "$$##")
    assert(ok_bad == true, "fromBase64 不应因非法输入崩溃")
    assert(decoded == "", "非法 Base64 应返回空字符串")
end

-- 正例：urlEncode 多种模式
-- 目的：验证默认、RFC3986 以及自定义模式
function string_tests.test_extend_urlencode_modes()
    log.info("string_tests", "开始 urlEncode 模式测试")
    assert(string.urlEncode, "string.urlEncode 未提供")

    local default = string.urlEncode("123 abc+/")
    assert(default == "123+abc%2B%2F", "默认模式编码不符")

    local rfc3986 = string.urlEncode("123 abc+/", 1)
    assert(rfc3986 == "123%20abc%2B%2F", "RFC3986 模式编码不符")

    local custom = string.urlEncode("123 abc+/", -1, 1, "/")
    assert(custom == "123%20abc%2B/", "自定义模式编码不符")
end

-- 反例：urlEncode 非字符串参数
-- 目的：传入 nil 时应抛错
function string_tests.test_extend_urlencode_invalid()
    log.info("string_tests", "开始 urlEncode 异常输入测试")
    local ok, _ = pcall(string.urlEncode, nil)
    assert(ok == false, "urlEncode 传入非字符串应报错")
end

return string_tests
