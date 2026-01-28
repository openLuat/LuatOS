local iconv_tests = {}

function iconv_tests.test_ucs2ToGb2312()
    local data_len = false
    local ic = iconv.open("gb2312", "ucs2")
    assert(ic ~= nil, "打开ucs2到gb2312的转换句柄失败")
    local ucs2_data = string.char(0x11, 0x62) -- 小端序: 0x11 0x62
    local result = ic:iconv(ucs2_data)
    if result and #result > 0 then
        data_len = true
    end
    assert(data_len == true, string.format(
        "我字由ucs2编码到gb2312编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local gb2312_data = string.format("%02X%02X", result:byte(1), result:byte(2))
    local expected_data = "CED2"
    assert(gb2312_data == expected_data, string.format(
        "我字由ucs2编码到gb2312编码格式转换失败: 预期 %s, 实际 %s", expected_data, gb2312_data))
    log.info("由ucs2编码格式到gb2312编码格式的转换成功！")
    -- iconv.close(ic)
end

function iconv_tests.test_gb2312toUcs2()
    local data_len = false
    local ic = iconv.open("ucs2", "gb2312")
    assert(ic ~= nil, "打开gb2312到ucs2的转换句柄失败")
    local gb2312_data = string.char(0xCE, 0xD2)
    local result = ic:iconv(gb2312_data)
    if result and #result > 0 then
        data_len = true
    end
    assert(data_len == true,
        string.format(
            "我字由gb2312编码格式到ucs2编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local ucs2_data = string.format("%02X%02X", result:byte(1), result:byte(2))
    local expected_data = "1162"
    assert(ucs2_data == expected_data,
        string.format("我字由gb2312编码格式到ucs2编码格式转换失败: 预期 %s, 实际 %s", expected_data,
            ucs2_data))
    log.info("由gb2312编码格式到ucs2编码格式的转换成功！")
    -- iconv.close(ic)
end

function iconv_tests.test_ucs2ToUtf8()
    local data_len = false
    local ic = iconv.open("utf8", "ucs2")
    assert(ic ~= nil, "打开ucs2到utf8的转换句柄失败")
    local ucs2_data = string.char(0x11, 0x62) -- 小端序: 0x11 0x62
    local result = ic:iconv(ucs2_data)
    if result and #result > 0 then
        data_len = true
    end
    assert(data_len == true, string.format(
        "我字由ucs2编码到utf8编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local utf8_data = string.format("%02X%02X%02X", result:byte(1), result:byte(2), result:byte(3))
    local expected_data = "E68891"
    assert(utf8_data == expected_data, string.format(
        "我字由ucs2编码到utf8编码格式转换失败: 预期 %s, 实际 %s", expected_data, utf8_data))
    log.info("由ucs2编码格式到utf8编码格式的转换成功！")
    -- iconv.close(ic)
end

function iconv_tests.test_utf8ToUcs2()
    local data_len = false
    local ic = iconv.open("ucs2", "utf8")
    assert(ic ~= nil, "打开utf8到ucs2的转换句柄失败")
    local utf8_data = string.char(0xE6, 0x88, 0X91) -- "E68891"是"我"字的utf8编码
    local result = ic:iconv(utf8_data)
    if result and #result > 0 then
        data_len = true
    end
    assert(data_len == true, string.format(
        "我字由utf8编码到ucs2编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local ucs2_data = string.format("%02X%02X", result:byte(1), result:byte(2))
    local expected_data = "1162"
    assert(ucs2_data == expected_data, string.format(
        "我字由utf8编码到ucs2编码格式转换失败: 预期 %s, 实际 %s", expected_data, ucs2_data))
    log.info("由utf8编码格式到ucs2编码格式的转换成功！")
end

function iconv_tests.test_gb2312toUcs2be()
    local data_len = false
    local ic = iconv.open("ucs2be", "gb2312")
    assert(ic ~= nil, "打开gb2312到ucs2be的转换句柄失败")
    local gb2312_data = string.char(0xCE, 0xD2)
    local result = ic:iconv(gb2312_data)
    if result and #result > 0 then
        data_len = true
    end
    assert(data_len == true,
        string.format(
            "我字由gb2312编码格式到ucs2be编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local ucs2be_data = string.format("%02X%02X", result:byte(1), result:byte(2))
    local expected_data = "6211"
    assert(ucs2be_data == expected_data,
        string.format("我字由gb2312编码格式到ucs2be编码格式转换失败: 预期 %s, 实际 %s",
            expected_data, ucs2be_data))
    log.info("由gb2312编码格式到ucs2be编码格式的转换成功！")
    -- iconv.close(ic)
end

function iconv_tests.test_ucs2beToGb2312()
    local data_len = false
    local ic = iconv.open("gb2312", "ucs2be")
    assert(ic ~= nil, "打开ucs2be到gb2312的转换句柄失败")
    local ucs2be_data = string.char(0x62, 0x11) -- 小端序: 0x11 0x62
    local result = ic:iconv(ucs2be_data)
    if result and #result > 0 then
        data_len = true
    end
    assert(data_len == true, string.format(
        "我字由ucs2be编码到gb2312编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local gb2312_data = string.format("%02X%02X", result:byte(1), result:byte(2))
    local expected_data = "CED2"
    assert(gb2312_data == expected_data,
        string.format("我字由ucs2be编码到gb2312编码格式转换失败: 预期 %s, 实际 %s", expected_data,
            gb2312_data))
    log.info("由ucs2be编码格式到gb2312编码格式的转换成功！")
    -- iconv.close(ic)
end

function iconv_tests.test_utf8ToUcs2be()
    local data_len = false
    local ic = iconv.open("ucs2be", "utf8")
    assert(ic ~= nil, "打开utf8到ucs2be的转换句柄失败")
    local utf8_data = string.char(0xE6, 0x88, 0X91) -- "E68891"是"我"字的utf8编码
    local result = ic:iconv(utf8_data)
    if result and #result > 0 then
        data_len = true
    end
    assert(data_len == true, string.format(
        "我字由utf8编码到ucs2be编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local ucs2be_data = string.format("%02X%02X", result:byte(1), result:byte(2))
    local expected_data = "6211"
    assert(ucs2be_data == expected_data, string.format(
        "我字由utf8编码到ucs2be编码格式转换失败: 预期 %s, 实际 %s", expected_data, ucs2be_data))
    log.info("由utf8编码格式到ucs2be编码格式的转换成功！")
end

function iconv_tests.test_ucs2beToUtf8()
    local data_len = false
    local ic = iconv.open("utf8", "ucs2be")
    assert(ic ~= nil, "打开ucs2be到utf8的转换句柄失败")
    local ucs2be_data = string.char(0x62, 0x11)
    local result = ic:iconv(ucs2be_data)
    if result and #result > 0 then
        data_len = true
    end
    assert(data_len == true, string.format(
        "我字由ucs2be编码到utf8编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local utf8_data = string.format("%02X%02X%02X", result:byte(1), result:byte(2), result:byte(3))
    local expected_data = "E68891"
    assert(utf8_data == expected_data, string.format(
        "我字由ucs2be编码到utf8编码格式转换失败: 预期 %s, 实际 %s", expected_data, utf8_data))
    log.info("由ucs2be编码格式到utf8编码格式的转换成功！")
    -- iconv.close(ic)
end

function iconv_tests.test_ucs2beToUtf8()
    local data_len = false
    local ic = iconv.open("utf8", "ucs2be")
    assert(ic ~= nil, "打开ucs2be到utf8的转换句柄失败")
    local ucs2be_data = string.char(0x62, 0x11)
    local result = ic:iconv(ucs2be_data)
    if result and #result > 0 then
        data_len = true
    end
    assert(data_len == true, string.format(
        "我字由ucs2be编码到utf8编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local utf8_data = string.format("%02X%02X%02X", result:byte(1), result:byte(2), result:byte(3))
    local expected_data = "E68891"
    assert(utf8_data == expected_data, string.format(
        "我字由ucs2be编码到utf8编码格式转换失败: 预期 %s, 实际 %s", expected_data, utf8_data))
    log.info("由ucs2be编码格式到utf8编码格式的转换成功！")
    -- iconv.close(ic)
end

function iconv_tests.test_gb2312ToUtf8()
    local expected_utf8 = "E68891"
    local ic = iconv.open("ucs2be", "gb2312")
    assert(ic ~= nil, "打开gb2312到ucs2be的转换句柄失败")
    local gb2312_data = string.char(0xCE, 0xD2)
    local ucs2be_data = ic:iconv(gb2312_data)
    ic = iconv.open("utf8", "ucs2be")
    assert(ic ~= nil, "打开ucs2be到utf8的转换句柄失败")
    local utf8_data = ic:iconv(ucs2be_data)
    local utf8_hex = string.format("%02X%02X%02X", utf8_data:byte(1), utf8_data:byte(2), utf8_data:byte(3))
    assert(utf8_hex == expected_utf8, string.format(
        "我字由gb2312编码到utf8编码格式转换失败: 预期 %s, 实际 %s", expected_utf8, utf8_hex))
    log.info("由gb2312编码格式到utf8编码格式的转换成功！")
end

function iconv_tests.test_utf8ToGb2312()
    local cd = iconv.open("ucs2", "utf8")
    assert(cd ~= nil, "打开utf8到ucs2的转换句柄失败")
    local utf8_data = string.char(0xE6, 0x88, 0X91) -- "E68891"是"我"字的utf8编码
    local ucs2_data = cd:iconv(utf8_data)
    local expected_gb2312 = "CED2"
    cd = iconv.open("gb2312", "ucs2")
    assert(cd ~= nil, "打开ucs2到gb2312的转换句柄失败")
    local gb2312_data = cd:iconv(ucs2_data)
    local gb2312_hex = string.format("%02X%02X", gb2312_data:byte(1), gb2312_data:byte(2))
    assert(gb2312_hex == expected_gb2312,
        string.format("我字由ucs2编码到gb2312编编码格式转换失败: 预期 %s, 实际 %s", expected_gb2312,
            gb2312_hex))
    log.info("由utf8编码格式到gb2312编码格式的转换成功！")
end


--英文/
-- 单个字母：UTF8与GB2312一致，与UCS2和UCS2be存在字节方面的差异

return iconv_tests
