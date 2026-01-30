local iconv_tests = {}
-- 中文：我为例
function iconv_tests.test_ucs2ToGb2312()
    local data_len = false
    local ic = iconv.open("gb2312", "ucs2")
    assert(ic ~= nil, "打开ucs2到gb2312的转换句柄失败")
    local ucs2_data = string.char(0x11, 0x62) -- 小端序: 0x11 0x62
    local result = ic:iconv(ucs2_data)
    if result and #result == 2 then
        data_len = true
    end
    assert(data_len == true, string.format(
        "我字由ucs2编码到gb2312编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local gb2312_data = string.format("%02X%02X", result:byte(1), result:byte(2))
    local expected_data = "CED2"
    assert(gb2312_data == expected_data, string.format(
        "我字由ucs2编码到gb2312编码格式转换失败: 预期 %s, 实际 %s", expected_data, gb2312_data))
    log.info("✓ 测试通过: 我字由 UCS2(0X11 0X62) →  GB2312(0xCE 0XD2)")
end

function iconv_tests.test_gb2312toUcs2()
    local data_len = false
    local ic = iconv.open("ucs2", "gb2312")
    assert(ic ~= nil, "打开gb2312到ucs2的转换句柄失败")
    local gb2312_data = string.char(0xCE, 0xD2)
    local result = ic:iconv(gb2312_data)
    if result and #result == 2 then
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
    log.info("✓ 测试通过: 我字由GB2312(0xCE 0XD2) → UCS2(0X11 0X62)")
end

function iconv_tests.test_ucs2ToUtf8()
    local data_len = false
    local ic = iconv.open("utf8", "ucs2")
    assert(ic ~= nil, "打开ucs2到utf8的转换句柄失败")
    local ucs2_data = string.char(0x11, 0x62) -- 小端序: 0x11 0x62
    local result = ic:iconv(ucs2_data)
    if result and #result == 3 then
        data_len = true
    end
    assert(data_len == true, string.format(
        "我字由ucs2编码到utf8编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local utf8_data = string.format("%02X%02X%02X", result:byte(1), result:byte(2), result:byte(3))
    local expected_data = "E68891"
    assert(utf8_data == expected_data, string.format(
        "我字由ucs2编码到utf8编码格式转换失败: 预期 %s, 实际 %s", expected_data, utf8_data))
    log.info("✓ 测试通过: 我字由 UCS2(0X11 0X62) →  UTF8(0xE6 0X88 0X91)")
end

function iconv_tests.test_utf8ToUcs2()
    local data_len = false
    local ic = iconv.open("ucs2", "utf8")
    assert(ic ~= nil, "打开utf8到ucs2的转换句柄失败")
    local utf8_data = string.char(0xE6, 0x88, 0X91) -- "E68891"是"我"字的utf8编码
    local result = ic:iconv(utf8_data)
    if result and #result == 2 then
        data_len = true
    end
    assert(data_len == true, string.format(
        "我字由utf8编码到ucs2编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local ucs2_data = string.format("%02X%02X", result:byte(1), result:byte(2))
    local expected_data = "1162"
    assert(ucs2_data == expected_data, string.format(
        "我字由utf8编码到ucs2编码格式转换失败: 预期 %s, 实际 %s", expected_data, ucs2_data))
    log.info("✓ 测试通过: 我字由UTF8(0xE6 0X88 0X91) → UCS2(0X11 0X62)")
end

function iconv_tests.test_gb2312toUcs2be()
    local data_len = false
    local ic = iconv.open("ucs2be", "gb2312")
    assert(ic ~= nil, "打开gb2312到ucs2be的转换句柄失败")
    local gb2312_data = string.char(0xCE, 0xD2)
    local result = ic:iconv(gb2312_data)
    if result and #result == 2 then
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
    log.info("✓ 测试通过: 我字由GB2312(0xCE 0XD2) → UCS-2BE(0x62 0X11)")
end

function iconv_tests.test_ucs2beToGb2312()
    local data_len = false
    local ic = iconv.open("gb2312", "ucs2be")
    assert(ic ~= nil, "打开ucs2be到gb2312的转换句柄失败")
    local ucs2be_data = string.char(0x62, 0x11) -- 小端序: 0x11 0x62
    local result = ic:iconv(ucs2be_data)
    if result and #result == 2 then
        data_len = true
    end
    assert(data_len == true, string.format(
        "我字由ucs2be编码到gb2312编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local gb2312_data = string.format("%02X%02X", result:byte(1), result:byte(2))
    local expected_data = "CED2"
    assert(gb2312_data == expected_data,
        string.format("我字由ucs2be编码到gb2312编码格式转换失败: 预期 %s, 实际 %s", expected_data,
            gb2312_data))
    log.info("✓ 测试通过: 我字由UCS-2BE(0x62 0X11) → GB2312(0xCE 0XD2)")
end

function iconv_tests.test_utf8ToUcs2be()
    local data_len = false
    local ic = iconv.open("ucs2be", "utf8")
    assert(ic ~= nil, "打开utf8到ucs2be的转换句柄失败")
    local utf8_data = string.char(0xE6, 0x88, 0X91) -- "E68891"是"我"字的utf8编码
    local result = ic:iconv(utf8_data)
    if result and #result == 2 then
        data_len = true
    end
    assert(data_len == true, string.format(
        "我字由utf8编码到ucs2be编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local ucs2be_data = string.format("%02X%02X", result:byte(1), result:byte(2))
    local expected_data = "6211"
    assert(ucs2be_data == expected_data, string.format(
        "我字由utf8编码到ucs2be编码格式转换失败: 预期 %s, 实际 %s", expected_data, ucs2be_data))
    log.info("✓ 测试通过: 我字由UTF8(0xE6 0X88 0X91) → UCS-2BE(0x62 0X11)")
end

function iconv_tests.test_ucs2beToUtf8()
    local data_len = false
    local ic = iconv.open("utf8", "ucs2be")
    assert(ic ~= nil, "打开ucs2be到utf8的转换句柄失败")
    local ucs2be_data = string.char(0x62, 0x11)
    local result = ic:iconv(ucs2be_data)
    if result and #result == 3 then
        data_len = true
    end
    assert(data_len == true, string.format(
        "我字由ucs2be编码到utf8编码格式转换失败或为空字符: 实际转换结果 %s", result))
    local utf8_data = string.format("%02X%02X%02X", result:byte(1), result:byte(2), result:byte(3))
    local expected_data = "E68891"
    assert(utf8_data == expected_data, string.format(
        "我字由ucs2be编码到utf8编码格式转换失败: 预期 %s, 实际 %s", expected_data, utf8_data))
    log.info("✓ 测试通过: 我字由UCS-2BE(0x62 0X11) → UTF8(0xE6 0X88 0X91)")
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
    log.info("✓ 测试通过: 我字由GB2312(0xCE 0XD2) → UTF8(0xE6 0X88 0X91)")
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
    assert(gb2312_hex == expected_gb2312, string.format(
        "我字由ucs2编码到gb2312编码格式转换失败: 预期 %s, 实际 %s", expected_gb2312, gb2312_hex))
    log.info("✓ 测试通过: 我字由UTF8(0xE6 0X88 0X91) → GB2312(0xCE 0XD2)")

end

-- 英文/单个字母/ASCII符号：UTF8与GB2312一致，与UCS2和UCS2be存在字节方面的差异
function iconv_tests.test_gb2312toUcs2be_A()
    local ic = iconv.open("ucs2be", "gb2312")
    assert(ic ~= nil, "打开gb2312到ucs2be的转换句柄失败")
    local gb2312_data = string.char(0x41)
    local result = ic:iconv(gb2312_data)
    assert(#result == 2, string.format("结果长度应为2字节，实际是%d字节", #result))
    local ucs2be_data = string.format("%02X%02X", result:byte(1), result:byte(2))
    local expeected_ucs2be = "0041"
    assert(ucs2be_data == expeected_ucs2be, string.format(
        "A由gb2312编码到ucs2be编码格式转换失败: 预期 %s, 实际 %s", expeected_ucs2be, ucs2be_data))
    log.info("✓ 测试通过: A由GB2312(0x41) → UCS-2BE(0x00 0x41)")
end

function iconv_tests.test_ucs2betoGb2312_A()
    local ic = iconv.open("gb2312", "ucs2be")
    assert(ic ~= nil, "打开ucs2be到gb2312的转换句柄失败")
    local ucs2be_data = string.char(0x00, 0x41)
    local result = ic:iconv(ucs2be_data)
    assert(#result == 1, string.format("结果长度应为1字节，实际是%d字节", #result))
    local gb2312_byte = result:byte(1)
    local gb2312_data = string.format("%02X", gb2312_byte)
    local expected_gb2312 = "41"
    assert(gb2312_data == expected_gb2312,
        string.format("A由ucs2be编码到gb2312编码到格式转换失败: 预期 %s, 实际 %s", expected_gb2312,
            gb2312_data))
    log.info("✓ 测试通过: A由UCS-2BE(0x00 0x41) → GB2312(0x41)")
end

function iconv_tests.test_utf8toUcs2_A()
    local ic = iconv.open("ucs2", "utf8")
    assert(ic ~= nil, "打开utf8到ucs2的转换句柄失败")
    local utf8_data = string.char(0x41)
    local result = ic:iconv(utf8_data)
    assert(#result == 2, string.format("结果长度应为2字节，实际是%d字节", #result))
    local ucs2_data = string.format("%02X%02X", result:byte(1), result:byte(2))
    local expeected_ucs2 = "4100"
    assert(ucs2_data == expeected_ucs2, string.format(
        "A由utf8编码到ucs2编码格式转换失败: 预期 %s, 实际 %s", expeected_ucs2, ucs2_data))
    log.info("✓ 测试通过: A由UTF8(0x41) → UCS2(0x41 0X00)")
end

function iconv_tests.test_ucs2toUtf8_A()
    local ic = iconv.open("utf8", "ucs2")
    assert(ic ~= nil, "打开ucs2到utf8的转换句柄失败")
    local ucs2_data = string.char(0x41, 0x00)
    local result = ic:iconv(ucs2_data)
    assert(#result == 1, string.format("结果长度应为1字节，实际是%d字节", #result))
    local utf8_byte = result:byte(1)
    local utf8_data = string.format("%02X", utf8_byte)
    local expected_utf8 = "41"
    assert(utf8_data == expected_utf8, string.format(
        "A由ucs2编码到utf8编码格式转换失败: 预期 %s, 实际 %s", expected_utf8, utf8_data))
    log.info("✓ 测试通过: A由UCS2(0x41 0X00) → UTF8(0x41)")

end

-- 全角符号：【。为例
function iconv_tests.test_gb2312toUcs2be_symbol()
    local ic = iconv.open("ucs2be", "gb2312")
    assert(ic ~= nil, "打开gb2312到ucs2be的转换句柄失败")
    local gb2312_data = string.char(0xA1, 0XBE, 0XA1, 0XA3)
    local result = ic:iconv(gb2312_data)
    assert(#result == 4, string.format("结果长度应为4字节，实际是%d字节", #result))
    local ucs2be_data =
        string.format("%02X%02X%02X%02X", result:byte(1), result:byte(2), result:byte(3), result:byte(4))
    local expected_ucs2be = "30103002"
    assert(ucs2be_data == expected_ucs2be,
        string.format("【。由gb2312编码到ucs2be编码格式转换失败: 预期 %s, 实际 %s", expected_ucs2be,
            ucs2be_data))
    log.info("✓ 测试通过: 【。由GB2312(0xA1,0XBE,0XA1,0XA3) → UCS-2BE(0x30 0x10 0x30 0x02)")
end

function iconv_tests.test_ucs2betoGb2312_symbol()
    local ic = iconv.open("gb2312", "ucs2be")
    assert(ic ~= nil, "打开ucs2be到gb2312的转换句柄失败")
    local ucs2be_data = string.char(0x30, 0x10, 0x30, 0x02)
    local result = ic:iconv(ucs2be_data)
    assert(#result == 4, string.format("结果长度应为4字节，实际是%d字节", #result))
    local gb2312_data =
        string.format("%02X%02X%02X%02X", result:byte(1), result:byte(2), result:byte(3), result:byte(4))
    local expected_gb2312 = "A1BEA1A3"
    assert(gb2312_data == expected_gb2312,
        string.format("【。由ucs2be编码到gb2312编码到格式转换失败: 预期 %s, 实际 %s",
            expected_gb2312, gb2312_data))
    log.info("✓ 测试通过: 【。由UCS-2BE(0x30 0x10 0x30 0x02) → GB2312(0xA1,0XBE,0XA1,0XA3)")
end

function iconv_tests.test_ucs2ToGb2312_symbol()
    local ic = iconv.open("gb2312", "ucs2")
    assert(ic ~= nil, "打开ucs2到gb2312的转换句柄失败")
    local ucs2_data = string.char(0x10, 0x30, 0x02, 0x30)
    local result = ic:iconv(ucs2_data)
    assert(#result == 4, string.format("结果长度应为4字节，实际是%d字节", #result))
    local gb2312_data =
        string.format("%02X%02X%02X%02X", result:byte(1), result:byte(2), result:byte(3), result:byte(4))
    local expected_gb2312 = "A1BEA1A3"
    assert(gb2312_data == expected_gb2312,
        string.format("【。由ucs2编码到gb2312编码格式转换失败: 预期 %s, 实际 %s", expected_gb2312,
            gb2312_data))
    log.info("✓ 测试通过: 【。由 UCS2(0X10 0x30 0x02 0x30) →  GB2312(0xA1,0XBE,0XA1,0XA3)")
end

function iconv_tests.test_gb2312toUcs2_symbol()
    local ic = iconv.open("ucs2", "gb2312")
    assert(ic ~= nil, "打开gb2312到ucs2的转换句柄失败")
    local gb2312_data = string.char(0xA1, 0XBE, 0XA1, 0XA3)
    local result = ic:iconv(gb2312_data)

    local ucs2_data = string.format("%02X%02X%02X%02X", result:byte(1), result:byte(2), result:byte(3), result:byte(4))
    local expected_data = "10300230"
    assert(ucs2_data == expected_data,
        string.format("【。由gb2312编码格式到ucs2编码格式转换失败: 预期 %s, 实际 %s", expected_data,
            ucs2_data))
    log.info("✓ 测试通过: 【。由GB2312(0xA1,0XBE,0XA1,0XA3) → UCS2(0X10 0x30 0x02 0x30)")
end

function iconv_tests.test_gb2312ToUtf8_symbol()
    local expected_utf8 = "E38090E38082"
    local ic = iconv.open("ucs2be", "gb2312")
    assert(ic ~= nil, "打开gb2312到ucs2be的转换句柄失败")
    local gb2312_data = string.char(0xA1, 0XBE, 0XA1, 0XA3)
    local ucs2be_data = ic:iconv(gb2312_data)
    ic = iconv.open("utf8", "ucs2be")
    assert(ic ~= nil, "打开ucs2be到utf8的转换句柄失败")
    local utf8_data = ic:iconv(ucs2be_data)
    assert(#utf8_data == 6, string.format("结果长度应为6字节，实际是%d字节", #utf8_data))
    local utf8_hex = string.format("%02X%02X%02X%02X%02X%02X", utf8_data:byte(1), utf8_data:byte(2), utf8_data:byte(3),
        utf8_data:byte(4), utf8_data:byte(5), utf8_data:byte(6))
    assert(utf8_hex == expected_utf8, string.format(
        "【。由gb2312编码到utf8编码格式转换失败: 预期 %s, 实际 %s", expected_utf8, utf8_hex))
    log.info("✓ 测试通过: 【。由GB2312(0xA1,0XBE,0XA1,0XA3) → UTF8(0xE3 0X80 0X90 0xE3 0X80 0X82)")
end

function iconv_tests.test_utf8ToGb2312_symbol()
    local cd = iconv.open("ucs2", "utf8")
    assert(cd ~= nil, "打开utf8到ucs2的转换句柄失败")
    local utf8_data = string.char(0xE3, 0X80, 0X90, 0xE3, 0X80, 0X82)
    local ucs2_data = cd:iconv(utf8_data)
    local expected_gb2312 = "A1BEA1A3"
    cd = iconv.open("gb2312", "ucs2")
    assert(cd ~= nil, "打开ucs2到gb2312的转换句柄失败")
    local gb2312_data = cd:iconv(ucs2_data)
    assert(#gb2312_data == 4, string.format("结果长度应为4字节，实际是%d字节", #gb2312_data))
    local gb2312_hex = string.format("%02X%02X%02X%02X", gb2312_data:byte(1), gb2312_data:byte(2), gb2312_data:byte(3),
        gb2312_data:byte(4))
    assert(gb2312_hex == expected_gb2312, string.format(
        "【。由ucs2编码到gb2312编码格式转换失败: 预期 %s, 实际 %s", expected_gb2312, gb2312_hex))
    log.info("✓ 测试通过: 【。由UTF8(0xE3 0X80 0X90 0xE3 0X80 0X82) → GB2312(0xA1,0XBE,0XA1,0XA3)")
end

function iconv_tests.test_ucs2ToUtf8_symbol()
    local ic = iconv.open("utf8", "ucs2")
    assert(ic ~= nil, "打开ucs2到utf8的转换句柄失败")
    local ucs2_data = string.char(0x10, 0x30, 0x02, 0x30)
    local result = ic:iconv(ucs2_data)
    assert(#result == 6, string.format("结果长度应为6字节，实际是%d字节", #result))
    local utf8_data = string.format("%02X%02X%02X%02X%02X%02X", result:byte(1), result:byte(2), result:byte(3),
        result:byte(4), result:byte(5), result:byte(6))
    local expected_utf8 = "E38090E38082"
    assert(utf8_data == expected_utf8, string.format(
        "【。由ucs2编码到utf8编码格式转换失败: 预期 %s, 实际 %s", expected_utf8, utf8_data))
    log.info("✓ 测试通过: 【。由UCS2(0X10 0x30 0x02 0x30) →  UTF8(0xE3 0X80 0X90 0xE3 0X80 0X82)")
end

function iconv_tests.test_utf8ToUcs2_symbol()
    local ic = iconv.open("ucs2", "utf8")
    assert(ic ~= nil, "打开utf8到ucs2的转换句柄失败")
    local utf8_data = string.char(0xE3, 0X80, 0X90, 0xE3, 0X80, 0X82)
    local result = ic:iconv(utf8_data)
    assert(#result == 4, string.format("结果长度应为4字节，实际是%d字节", #result))
    local ucs2_data = string.format("%02X%02X%02X%02X", result:byte(1), result:byte(2), result:byte(3), result:byte(4))
    local expected_ucs2 = "10300230"
    assert(ucs2_data == expected_ucs2, string.format(
        "【。由utf8编码到ucs2编码格式转换失败: 预期 %s, 实际 %s", expected_ucs2, ucs2_data))
    log.info("✓ 测试通过: 【。UTF8(0xE3 0X80 0X90 0xE3 0X80 0X82) → UCS2(0X10 0x30 0x02 0x30)")
end

function iconv_tests.test_utf8ToUcs2be_symbol()
    local ic = iconv.open("ucs2be", "utf8")
    assert(ic ~= nil, "打开utf8到ucs2be的转换句柄失败")
    local utf8_data = string.char(0xE3, 0X80, 0X90, 0xE3, 0X80, 0X82)
    local result = ic:iconv(utf8_data)
    assert(#result == 4, string.format("结果长度应为4字节，实际是%d字节", #result))
    local ucs2be_data =
        string.format("%02X%02X%02X%02X", result:byte(1), result:byte(2), result:byte(3), result:byte(4))
    local expected_data = "30103002"
    assert(ucs2be_data == expected_data, string.format(
        "【。由utf8编码到ucs2be编码格式转换失败: 预期 %s, 实际 %s", expected_data, ucs2be_data))
    log.info("✓ 测试通过: 【。由UTF8(0xE3 0X80 0X90 0xE3 0X80 0X82) → UCS-2BE(0x30 0x10 0x30 0x02)")
end

function iconv_tests.test_ucs2beToUtf8_symbol()
    local ic = iconv.open("utf8", "ucs2be")
    assert(ic ~= nil, "打开ucs2be到utf8的转换句柄失败")
    local ucs2be_data = string.char(0x30, 0x10, 0x30, 0x02)
    local result = ic:iconv(ucs2be_data)
    assert(#result == 6, string.format("结果长度应为4字节，实际是%d字节", #result))
    local utf8_data = string.format("%02X%02X%02X%02X%02X%02X", result:byte(1), result:byte(2), result:byte(3),
        result:byte(4), result:byte(5), result:byte(6))
    local expected_data = "E38090E38082"
    assert(utf8_data == expected_data, string.format(
        "我字由ucs2be编码到utf8编码格式转换失败: 预期 %s, 实际 %s", expected_data, utf8_data))
    log.info("✓ 测试通过: 【。由UCS-2BE(0x30 0x10 0x30 0x02) → UTF8(0xE3 0X80 0X90 0xE3 0X80 0X82)")
end

return iconv_tests

