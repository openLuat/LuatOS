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

function string_tests.test_native_find_invalid_pattern()
    log.info("string_tests", "开始 非法模式参数测试")
    local ok, err = pcall(function()
        return string.find("abc", {})
    end)
    assert(ok == false, "非法模式应触发异常")
    assert(err and err:match("string expected"), "错误信息应包含 string expected")
end

-- ====================== split 函数测试 ======================
function string_tests.test_split_normal()
    log.info("string_tests", "开始 split 正常情况测试")

    -- 基本分割
    local parts1 = string.split("123,456,789", ",")
    assert(#parts1 == 3, "分割数量错误")
    assert(parts1[1] == "123" and parts1[2] == "456" and parts1[3] == "789", "分割结果错误")

    -- 使用点号作为分隔符（直接使用点号，不转义）
    local parts2 = string.split("192.168.1.1", ".")
    assert(#parts2 == 4, "IP分割数量错误")
    assert(parts2[1] == "192" and parts2[2] == "168" and parts2[3] == "1" and parts2[4] == "1", "IP分割结果错误")

    -- 多字符分隔符
    local parts3 = string.split("a||b||c", "||")
    assert(#parts3 == 3, "多字符分隔符分割数量错误")
    assert(parts3[1] == "a" and parts3[2] == "b" and parts3[3] == "c", "多字符分隔符结果错误")

    -- 不保留空片段（默认行为）
    local parts4 = string.split("/tmp//def/1234/", "/", false)
    assert(#parts4 == 3, "不保留空片段数量错误")
    assert(parts4[1] == "tmp" and parts4[2] == "def" and parts4[3] == "1234", "不保留空片段结果错误")

    -- 保留空片段
    local parts5 = string.split("/tmp//def/1234/", "/", true)
    assert(#parts5 == 6, "保留空片段数量错误")
    assert(
        parts5[1] == "" and parts5[2] == "tmp" and parts5[3] == "" and parts5[4] == "def" and parts5[5] == "1234" and
            parts5[6] == "", "保留空片段结果错误")

    -- 空字符串分割
    local parts6 = string.split("", ",")
    log.info("string_tests", "空字符串分割结果:", #parts6, json.encode(parts6))
    -- 不崩溃就算通过
    assert(type(parts6) == "table", "空字符串分割应返回table")

    -- 分隔符为空字符串
    local parts7 = string.split("abc", "")
    assert(#parts7 == 1 and parts7[1] == "abc", "空分隔符应返回原字符串")

    -- 分隔符不存在
    local parts8 = string.split("hello world", "|")
    assert(#parts8 == 1 and parts8[1] == "hello world", "不存在的分隔符应返回原字符串")

    -- 方法调用形式
    local parts9 = ("a,b,c"):split(",")
    assert(#parts9 == 3, "方法调用形式分割数量错误")
    assert(parts9[1] == "a" and parts9[2] == "b" and parts9[3] == "c", "方法调用形式结果错误")
end

function string_tests.test_split_invalid()
    log.info("string_tests", "开始 split 异常参数测试")

    -- 传入 nil 作为字符串
    local test_split_nil = pcall(string.split, nil, ",")
    assert(test_split_nil == false, "split 传入 nil 应报错")

    -- 传入数字作为字符串
    local test_split_number = string.split(12345, ",")
    assert(type(test_split_number) == "table", "split 数字应返回table")

end

-- ====================== toValue 函数测试 ======================
function string_tests.test_tovalue_normal()
    log.info("string_tests", "开始 toValue 正常情况测试")
    -- 每个字符转换规则：
    --   数字 '0'-'9' -> 0-9
    --   字母 a-z/A-Z -> 先转为位置（a=1, b=2, ..., z=26），然后加上 9，再取低4位（模16）
    -- 公式：value = (char_value + 9) % 16，其中 char_value 是字符的数值（数字为本身，字母为位置）

    -- 数字字符串转换：数字字符转为对应的数值（0-9）
    local bin1, count1 = string.toValue("123456")
    assert(count1 == 6, "toValue 转换数量错误")
    local hex1 = string.toHex(bin1)
    log.info("string_tests", "数字字符串 toHex 结果:", hex1)
    assert(hex1 == "010203040506", "数字转换结果错误，期望 010203040506")

    -- 字母字符串转换：'a'=1, 1+9=10 (0x0A), 'b'=2, 2+9=11 (0x0B), 'c'=3, 3+9=12 (0x0C)
    local bin2, count2 = string.toValue("abc")
    assert(count2 == 3, "字母字符串转换数量错误")
    local hex2 = string.toHex(bin2)
    log.info("string_tests", "字母字符串 toHex 结果:", hex2)
    assert(hex2 == "0A0B0C", "字母转换结果错误，期望 0A0B0C")

    -- 大写字母转换：大小写不敏感，结果相同
    local bin3, count3 = string.toValue("ABC")
    assert(count3 == 3, "大写字母字符串转换数量错误")
    local hex3 = string.toHex(bin3)
    log.info("string_tests", "大写字母字符串 toHex 结果:", hex3)
    assert(hex3 == "0A0B0C", "大写字母转换结果错误，期望 0A0B0C")

    -- 混合字符串：数字和字母混合
    local bin4, count4 = string.toValue("1a2b")
    assert(count4 == 4, "混合字符串转换数量错误")
    local hex4 = string.toHex(bin4)
    log.info("string_tests", "混合字符串 toHex 结果:", hex4)
    assert(hex4 == "010A020B", "混合字符串转换结果错误，期望 010A020B")

    -- 空字符串转换
    local bin5, count5 = string.toValue("")
    assert(count5 == 0, "空字符串转换数量应为0")
    assert(bin5 == "", "空字符串转换结果应为空")

    -- 单字符转换，数字 '1' 转为 1
    local bin6, count6 = string.toValue("1")
    assert(count6 == 1, "单字符数字转换数量错误")
    local hex6 = string.toHex(bin6)
    log.info("string_tests", "单字符 '1' toHex 结果:", hex6)
    assert(hex6 == "01", "单字符 '1' 转换结果错误，期望 01")

    -- 单字符转换，字母 'a' 转为 10 (0x0A)
    local bin7, count7 = string.toValue("a")
    assert(count7 == 1, "单字符字母转换数量错误")
    local hex7 = string.toHex(bin7)
    log.info("string_tests", "单字符 'a' toHex 结果:", hex7)
    assert(hex7 == "0A", "单字符 'a' 转换结果错误，期望 0A")

    -- 单字符转换，字母 'p' 位置16，16+9=25，25%16=9 (0x09)
    local bin8, count8 = string.toValue("p")
    assert(count8 == 1, "单字符 'p' 转换数量错误")
    local hex8 = string.toHex(bin8)
    log.info("string_tests", "单字符 'p' toHex 结果:", hex8)
    assert(hex8 == "09", "单字符 'p' 转换结果错误，期望 09")

    -- 单字符转换， 字母 'z' 位置26，26+9=35，35%16=3 (0x03)
    local bin9, count9 = string.toValue("z")
    assert(count9 == 1, "单字符 'z' 转换数量错误")
    local hex9 = string.toHex(bin9)
    log.info("string_tests", "单字符 'z' toHex 结果:", hex9)
    assert(hex9 == "03", "单字符 'z' 转换结果错误，期望 03")

    -- 单字符转换， 数字 '0' 转为 0
    local bin10, count10 = string.toValue("0")
    assert(count10 == 1, "单字符 '0' 转换数量错误")
    local hex10 = string.toHex(bin10)
    log.info("string_tests", "单字符 '0' toHex 结果:", hex10)
    assert(hex10 == "00", "单字符 '0' 转换结果错误，期望 00")

    -- 特殊字符转换
    local bin11, count11 = string.toValue("\x00\x01\x02")
    assert(count11 == 3, "特殊字符转换数量错误")
    local hex11 = string.toHex(bin11)
    log.info("string_tests", "特殊字符 toHex 结果:", hex11)
    assert(hex11 == "000102", "特殊字符转换结果错误，期望 000102")

    -- 复杂混合测试：'0aZ' 中：
    -- '0' -> 0
    -- 'a' -> 1+9=10 (0x0A)
    -- 'Z' -> 26+9=35, 35%16=3 (0x03)
    local bin12, count12 = string.toValue("0aZ")
    assert(count12 == 3, "复杂混合转换数量错误")
    local hex12 = string.toHex(bin12)
    log.info("string_tests", "复杂混合 toHex 结果:", hex12)
    assert(hex12 == "000A03", "复杂混合转换结果错误，期望 000A03")

    -- 边界测试：字母 'h' 位置8，8+9=17，17%16=1 (0x01)
    local bin13, count13 = string.toValue("h")
    assert(count13 == 1, "单字符 'h' 转换数量错误")
    local hex13 = string.toHex(bin13)
    log.info("string_tests", "单字符 'h' toHex 结果:", hex13)
    assert(hex13 == "01", "单字符 'h' 转换结果错误，期望 01")

    -- 边界测试：字母 'q' 位置17，17+9=26，26%16=10 (0x0A)
    local bin14, count14 = string.toValue("q")
    assert(count14 == 1, "单字符 'q' 转换数量错误")
    local hex14 = string.toHex(bin14)
    log.info("string_tests", "单字符 'q' toHex 结果:", hex14)
    assert(hex14 == "0A", "单字符 'q' 转换结果错误，期望 0A")
end

function string_tests.test_tovalue_invalid()
    log.info("string_tests", "开始 toValue 异常参数测试")

    -- 传入 nil
    local test_tovalue_nil = pcall(string.toValue, nil)
    assert(test_tovalue_nil == false, "toValue 传入 nil 应报错")

    -- 传入数字
    local test_tovalue_number, tovalue_number_count = string.toValue(12345)
    assert(test_tovalue_number ~= nil and type(test_tovalue_number) == "string", "toValue 传入数字应返回结果")
    assert(tovalue_number_count == 5, "toValue 数字参数转换数量应为5")

    log.info("string_tests", "toValue 异常参数测试通过")

end

-- ====================== toBase32/fromBase32 函数测试 ======================
function string_tests.test_base32_roundtrip()
    log.info("string_tests", "开始 Base32 往返测试")

    -- 基本往返
    local raw1 = "Hello"
    local encoded1 = string.toBase32(raw1)
    log.info("string_tests", "Base32 编码结果:", encoded1)
    local decoded1 = string.fromBase32(encoded1)
    assert(decoded1 == raw1, "Base32 解码结果不符")

    -- 空字符串
    local raw3 = ""
    local encoded3 = string.toBase32(raw3)
    assert(encoded3 == "", "空字符串 Base32 编码应为空")
    local decoded3 = string.fromBase32(encoded3)
    assert(decoded3 == "", "空字符串 Base32 解码应为空")

    -- 二进制数据
    local raw4 = "\x00\x01\x02\x03"
    local encoded4 = string.toBase32(raw4)
    local decoded4 = string.fromBase32(encoded4)
    assert(decoded4 == raw4, "二进制数据 Base32 往返失败")
end

function string_tests.test_base32_invalid()
    log.info("string_tests", "开始 Base32 异常参数测试")

    -- toBase32 传入 nil
    local test_tobase32_nil = pcall(string.toBase32, nil)
    assert(test_tobase32_nil == false, "toBase32 传入 nil 应报错")

    -- toBase32 传入数字
    local test_tobase32_number = string.toBase32(12345)
    assert(test_tobase32_number ~= nil and type(test_tobase32_number) == "string",
        "toBase32 传入数字应返回结果")

    -- fromBase32 非法字符
    local ok6, decoded = pcall(string.fromBase32, "!!@@##")
    assert(ok6 == true, "fromBase32 非法字符不应崩溃")
    assert(decoded == "", "非法 Base32 应返回空字符串")
end

-- ====================== startsWith/endsWith 函数测试 ======================
function string_tests.test_startswith_normal()
    log.info("string_tests", "开始 startsWith 正常情况测试")

    -- 基本匹配
    assert(string.startsWith("hello world", "hello") == true, "startsWith 前缀匹配失败")
    assert(string.startsWith("hello world", "world") == false, "startsWith 不应匹配非前缀")

    -- 完全匹配
    assert(string.startsWith("abc", "abc") == true, "startsWith 完全匹配失败")

    -- 大小写敏感
    assert(string.startsWith("Hello", "hello") == false, "startsWith 应大小写敏感")

    -- 空前缀
    local result = string.startsWith("hello world", "")
    log.info("string_tests", "startsWith 空前缀结果:", result)
    -- 不强制断言，只记录日志

    -- 空字符串边界情况
    assert(string.startsWith("", "") == true, "startsWith 两个空字符串应返回 true")
    assert(string.startsWith("", "abc") == false, "startsWith 空字符串检查非空前缀应返回 false")

    -- 方法调用形式
    local str = "hello world"
    assert(str:startsWith("hello") == true, "方法调用形式 startsWith 失败")
end

function string_tests.test_startswith_invalid()
    log.info("string_tests", "开始 startsWith 异常参数测试")

    -- 传入 nil 作为字符串
    local test_startsWith_nil = pcall(string.startsWith, nil, "abc")
    assert(test_startsWith_nil == false, "startsWith 传入 nil 应报错")

    -- -- 传入数字作为字符串
    local test_startsWith_number = string.startsWith(12345, "abc")
    assert(test_startsWith_number == false, "startsWith 传入数字应返回 false")
end

function string_tests.test_endswith_normal()
    log.info("string_tests", "开始 endsWith 正常情况测试")

    -- 基本匹配
    assert(string.endsWith("hello world", "world") == true, "endsWith 后缀匹配失败")
    assert(string.endsWith("hello world", "hello") == false, "endsWith 不应匹配非后缀")

    -- 完全匹配
    assert(string.endsWith("abc", "abc") == true, "endsWith 完全匹配失败")

    -- 大小写敏感
    assert(string.endsWith("Hello", "hello") == false, "endsWith 应大小写敏感")

    -- 空后缀
    local result = string.endsWith("hello world", "")
    log.info("string_tests", "endsWith 空后缀结果:", result)
    -- 不强制断言，只记录日志

    -- 空字符串边界情况
    assert(string.endsWith("", "") == true, "endsWith 两个空字符串应返回 true")
    assert(string.endsWith("", "abc") == false, "endsWith 空字符串检查非空后缀应返回 false")

    -- 文件扩展名检查
    assert(string.endsWith("document.pdf", ".pdf") == true, "endsWith 文件扩展名匹配失败")
    assert(string.endsWith("document.pdf", ".txt") == false, "endsWith 文件扩展名不应匹配")

    -- 方法调用形式
    local str = "hello world"
    assert(str:endsWith("world") == true, "方法调用形式 endsWith 失败")
end

function string_tests.test_endswith_invalid()
    log.info("string_tests", "开始 endsWith 异常参数测试")

    -- 传入 nil 作为字符串
    local test_endsWith_nil = pcall(string.endsWith, nil, "abc")
    assert(test_endsWith_nil == false, "endsWith 传入 nil 应报错")

    -- -- 传入数字作为字符串
    local test_endsWith_number = string.endsWith(12345, "abc")
    assert(test_endsWith_number == false, "endsWith 传入数字应返回 false")

end

-- ====================== trim 函数测试 ======================
function string_tests.test_trim_normal()
    log.info("string_tests", "开始 trim 正常情况测试")

    -- 默认裁剪（前后都裁剪）
    local str1 = "  \r\n  hello world  \t\n  "
    local trimmed1 = string.trim(str1)
    assert(trimmed1 == "hello world", "trim 默认裁剪结果错误")

    -- 仅裁剪前缀
    local trimmed2 = string.trim(str1, true, false)
    assert(trimmed2:match("^[^%s]") == "h", "trim 仅裁剪前缀后开头应为非空白")

    -- 仅裁剪后缀
    local trimmed3 = string.trim(str1, false, true)
    assert(trimmed3:match("[^%s]$") == "d", "trim 仅裁剪后缀后结尾应为非空白")

    -- 无空白字符的字符串
    local str2 = "hello"
    local trimmed4 = string.trim(str2)
    assert(trimmed4 == "hello", "trim 无空白字符串应不变")

    -- 只有空白字符的字符串
    local str3 = "  \t\n  "
    local trimmed5 = string.trim(str3)
    assert(trimmed5 == "", "trim 全空白字符串应返回空")

    -- 空字符串
    local trimmed6 = string.trim("")
    assert(trimmed6 == "", "trim 空字符串应返回空")

    -- 方法调用形式
    local str4 = "  test  "
    local trimmed7 = str4:trim()
    assert(trimmed7 == "test", "方法调用形式 trim 失败")
end

function string_tests.test_trim_invalid()
    log.info("string_tests", "开始 trim 异常参数测试")

    -- 传入 nil
    local test_trim_nil = pcall(string.trim, nil)
    assert(test_trim_nil == false, "trim 传入 nil 应报错")

    -- 传入数字
    local test_trim_number = string.trim(12345)
    assert(test_trim_number == "12345" and type(test_trim_number) == "string", "trim 传入数字应返回字符串")

    -- 传入 boolean 作为 ltrim 参数
    local ok4, result4 = pcall(string.trim, "  test  ", false, true)
    assert(ok4 == true, "trim 传入布尔参数应正常")
end

-- ====================== urlEncode 函数测试 ======================
function string_tests.test_urlencode_normal()
    log.info("string_tests", "开始 urlEncode 正常情况测试")

    -- 默认模式（空格编码为 +）
    local default = string.urlEncode("123 abc+/")
    log.info("string_tests", "urlEncode 默认模式:", default)
    -- 空字符串
    local empty = string.urlEncode("")
    assert(empty == "", "空字符串 urlEncode 应为空")

    -- 方法调用形式
    local method_result = ("test url"):urlEncode()
    log.info("string_tests", "urlEncode 方法调用:", method_result)
    -- 只验证不为空
    assert(method_result ~= nil, "方法调用形式 urlEncode 应返回结果")
end

function string_tests.test_urlencode_invalid()
    log.info("string_tests", "开始 urlEncode 异常参数测试")

    -- 传入 nil
    local test_urlencode_nil = pcall(string.urlEncode, nil)
    assert(test_urlencode_nil == false, "urlEncode 传入 nil 应报错")

    -- 传入数字
    local test_urlencode_number = string.urlEncode(12345)
    assert(test_urlencode_number == "12345", "urlEncode 传入数字应返回字符串")
end

-- ====================== fromBase64 函数测试 ======================
function string_tests.test_frombase64_invalid_extended()
    log.info("string_tests", "开始 fromBase64 增强异常参数测试")

    -- 传入 nil
    local test_frombase64_nil = pcall(string.fromBase64, nil)
    assert(test_frombase64_nil == false, "fromBase64 传入 nil 应报错")

    -- 传入数字
    local test_frombase64_number = string.fromBase64(12345)
    assert(type(test_frombase64_number) == "string", "fromBase64 传入数字应返回空字符串")

    -- 非法字符
    local test_frombase64_badchars = string.fromBase64("$$##")
    assert(test_frombase64_badchars == "", "fromBase64 非法字符应返回空字符串")

    -- 包含换行符的 Base64
    local ok6, decoded6 = pcall(string.fromBase64, "SGVs\nbG8=\n")
    assert(ok6 == true, "fromBase64 包含换行符不应崩溃")
    assert(decoded6 == "Hello", "包含换行符的 Base64 解码结果错误")
end

-- ====================== 十六进制函数测试（原有）======================
function string_tests.test_extend_hex_roundtrip()
    log.info("string_tests", "开始 toHex/fromHex 往返测试")
    local toHex = string.toHex
    local fromHex = string.fromHex

    assert(type(toHex) == "function", "string.toHex 未提供")
    assert(type(fromHex) == "function", "string.fromHex 未提供")

    local raw = "\x01\xABLua"
    local hex = toHex(raw)
    assert(type(hex) == "string" and #hex == #raw * 2, "toHex 返回内容异常")

    local decoded = fromHex(hex)
    assert(decoded == raw, "fromHex 未能还原原始数据")

    local decoded_lower = fromHex(string.lower(hex))
    assert(decoded_lower == raw, "fromHex 应支持小写输入")
end

function string_tests.test_extend_hex_with_separator()
    log.info("string_tests", "开始 toHex 分隔符测试")
    local toHex = string.toHex
    assert(type(toHex) == "function", "string.toHex 未提供")

    local raw = "AB"
    local hex, hex_len = toHex(raw, " ")
    assert(hex == "41 42 ", "带分隔符的 toHex 结果不符")
    assert(hex_len == 4, "toHex 返回的长度应为原字节数*2")
end

function string_tests.test_extend_hex_invalid_inputs()
    log.info("string_tests", "开始 toHex/fromHex 异常输入测试")
    local toHex = string.toHex
    local fromHex = string.fromHex

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

-- ====================== Base64 函数测试（原有）======================
function string_tests.test_extend_base64_roundtrip()
    log.info("string_tests", "开始 Base64 往返测试")
    local toBase64 = string.toBase64
    local fromBase64 = string.fromBase64

    assert(type(toBase64) == "function", "string.toBase64 未提供")
    assert(type(fromBase64) == "function", "string.fromBase64 未提供")

    local raw = "hello"
    local encoded = toBase64(raw)
    assert(encoded == "aGVsbG8=", "Base64 编码结果不符")

    local decoded = fromBase64(encoded)
    assert(decoded == raw, "Base64 解码结果不符")
end

function string_tests.test_extend_base64_invalid()
    log.info("string_tests", "开始 Base64 异常输入测试")
    local toBase64 = string.toBase64
    local fromBase64 = string.fromBase64

    assert(type(toBase64) == "function", "string.toBase64 未提供")
    assert(type(fromBase64) == "function", "string.fromBase64 未提供")

    local ok_tob64 = pcall(toBase64, nil)
    assert(ok_tob64 == false, "toBase64 传入非字符串应报错")

    local ok_bad, decoded = pcall(fromBase64, "$$##")
    assert(ok_bad == true, "fromBase64 不应因非法输入崩溃")
    assert(decoded == "", "非法 Base64 应返回空字符串")
end

return string_tests
