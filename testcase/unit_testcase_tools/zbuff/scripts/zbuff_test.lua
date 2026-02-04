local zbuff_tests = {}

--
function zbuff_tests.test_zbuffInterface_wirtenumber()
    local buff = zbuff.create(1024)
    assert(buff ~= nil, "创建zbuff缓冲区失败")
    local len = buff:write(0x1a, 0x30, 0x31, 0x32, 0x00, 0x01)
    assert(len > 0, string.format("连续写入多个number类型的字节失败:  写入的字节数 %d", len))
    buff:free()
end

function zbuff_tests.test_zbuffInterface_wirteMixedType()
    local buff = zbuff.create(3)
    assert(buff ~= nil, "创建zbuff缓冲区失败")
    local len = buff:write(0x1a, "CD")
    local buff1 = zbuff.create(3)
    assert(buff1 ~= nil, "创建zbuff缓冲区失败")
    local len1 = buff:write("AB", 0x12)
    assert(len < len1,
        "连续写入多个混合类型但应先字符串后数值,先字符串后数值的成功写入的字节长度应该大于先数值后字符串，实际不符")
    buff:clear()
    buff1:clear()
end

function zbuff_tests.test_zbuffInterface_wirteDataOverflow()
    local buff = zbuff.create(3)
    assert(buff ~= nil, "创建zbuff缓冲区失败")
    local len = buff:write(0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC)
    local buff_len = buff:len()
    assert(len == buff_len, string.format(
        "写入数据超过缓冲区会自动截断,实际写入长度不等于缓冲区长度:  实际写入长度 %d,缓冲区长度%d",
        len, buff_len))
    buff:clear()
end

function zbuff_tests.test_zbuffInterface_wirteString()
    -- 多个string类型的写入
    -- 方法一:拼接写入
    local buff = zbuff.create(2)
    buff:write("AB" .. "CD")
    local buff1 = zbuff.create(2)
    -- 方法一:连续多次写入
    buff1:write("AB")
    buff1:write("CD")
    buff:seek(0)
    local str = buff:read(2)
    buff1:seek(0)
    local str1 = buff1:read(2)
    assert(str:toHex() == str1:toHex(), string.format(
        "支持拼接写入多个string类型的字节和分批写入多个string类型的字节但结果不一致:  拼接方式成功写入结果 %s,多次连续方式成功写入结果 %s",
        str:toHex(), str1:toHex()))
end

function zbuff_tests.test_zbuff_seek_set()
    log.info("测试", "=== 测试 zbuff.SEEK_SET 模式 ===")

    -- 1. 创建缓冲区并写入数据
    local buff = zbuff.create(30)
    assert(buff ~= nil, "创建zbuff失败")
    -- 写入确定的测试数据
    local test_data = "0123456789ABCDEFGHIJ"
    local write_len = buff:write(test_data)
    assert(write_len == #test_data, "写入数据长度不匹配")

    -- 2. 测试 SEEK_SET 基本功能
    log.info("测试", "--- 测试基础定位 ---")

    -- 2.1 定位到开头
    local pos = buff:seek(0, zbuff.SEEK_SET)
    assert(pos == 0, "断言失败: SEEK_SET 0应该返回0，实际" .. pos)
    local data = buff:read(3)
    assert(data == "012", "断言失败: 位置0应该读取'012'，实际'" .. (data or "nil") .. "'")

    -- 2.2 定位到位置5
    pos = buff:seek(5, zbuff.SEEK_SET)
    assert(pos == 5, "断言失败: SEEK_SET 5应该返回5，实际" .. pos)
    data = buff:read(3)
    assert(data == "567", "断言失败: 位置5应该读取'567'，实际'" .. (data or "nil") .. "'")

    -- 3. 测试 SEEK_SET 边界处理
    log.info("测试", "--- 测试边界处理 ---")
    local buff_len = buff:len()
    log.info("信息", "缓冲区长度: " .. buff_len)
    -- 3.1 测试超出正向边界（应该截断到末尾）
    pos = buff:seek(100, zbuff.SEEK_SET)
    local expected_pos = buff_len
    assert(pos == expected_pos, "断言失败: 超出正向边界应截断到" .. expected_pos .. "，实际" .. pos)
    -- 3.2 测试定位到缓冲区末尾
    pos = buff:seek(buff_len - 1, zbuff.SEEK_SET)
    assert(pos == buff_len - 1, "断言失败: 定位到末尾应该返回" .. (buff_len - 1) .. "，实际" .. pos)
end

function zbuff_tests.test_zbuff_seek_cur()
    log.info("测试", "=== 测试 zbuff.SEEK_CUR 模式 ===")

    -- 1. 准备测试数据
    local buff = zbuff.create(40)
    local test_data = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    buff:write(test_data)
    log.info("数据", "写入: '" .. test_data .. "'")

    -- 2. 测试 SEEK_CUR 正向移动
    log.info("测试", "--- 测试正向移动 ---")

    -- 2.1 从开头向前移动
    buff:seek(0, zbuff.SEEK_SET) -- 先到开头
    local pos = buff:seek(5, zbuff.SEEK_CUR) -- 从位置0向前移动5字节
    assert(pos == 5, "断言失败: 从0向前5字节应该到5，实际" .. pos)
    local data = buff:read(3)
    assert(data == "567", "断言失败: 位置5应该读取'567'，实际'" .. (data or "nil") .. "'")

    -- 3. 测试 SEEK_CUR 向前移动
    log.info("测试", "--- 测试向前移动 ---")

    -- 3.1 先移动到位置15
    buff:seek(15, zbuff.SEEK_SET)
    assert(buff:seek(0, zbuff.SEEK_CUR) == 15, "断言失败: 应该到位置15")
    -- 3.2 向后移动3字节
    pos = buff:seek(-3, zbuff.SEEK_CUR)
    assert(pos == 12, "断言失败: 从15向后3字节应该到12，实际" .. pos)
    data = buff:read(3)
    assert(data == "CDE", "断言失败: 位置12应该读取'CDE'，实际'" .. (data or "nil") .. "'")

    -- 4. 测试 SEEK_CUR 边界处理
    log.info("测试", "--- 测试边界处理 ---")
    -- 4.1 测试向后超出边界
    buff:seek(0, zbuff.SEEK_SET)
    pos = buff:seek(-10, zbuff.SEEK_CUR) -- 尝试向后超出开头
    assert(pos == 0, "断言失败: 向后超出边界应该返回0，实际" .. pos)

    -- 4.2 测试向前超出边界
    buff:seek(0, zbuff.SEEK_SET)
    local buff_len = buff:len()
    -- 先移动到接近末尾
    buff:seek(buff_len - 5, zbuff.SEEK_SET)
    pos = buff:seek(10, zbuff.SEEK_CUR) -- 尝试向前超出末尾
    assert(pos == buff_len, "断言失败: 向前超出边界应截断到" .. (buff_len) .. "，实际" .. pos)

    log.info("测试", "zbuff.SEEK_CUR 模式测试全部通过！")
end

function zbuff_tests.test_zbuff_seek_end()
    log.info("测试", "=== 测试 zbuff.SEEK_END 模式 ===")

    -- 1. 准备测试数据
    local buff = zbuff.create(35)
    local test_data = "0123456789ABCDEFGHIJKLMNOPQRSTUVW"
    buff:write(test_data)
    -- 验证写入的数据
    buff:seek(0, zbuff.SEEK_SET)
    local actual_data = buff:read(50)
    local data_len = #actual_data
    local last_chars = actual_data:sub(-3)

    -- 2. 测试 SEEK_END 基本功能
    log.info("测试", "--- 测试基本功能 ---")

    local buff_len = buff:len()
    log.info("信息", "缓冲区长度: " .. buff_len)

    -- 2.1 从末尾向前移动3字节
    local pos = buff:seek(-3, zbuff.SEEK_END)
    local expected_pos = buff_len - 3
    assert(pos == expected_pos, "断言失败: SEEK_END -3应该返回" .. expected_pos .. "，实际" .. pos)
    local data = buff:read(3)
    assert(data == last_chars,
        "断言失败: 末尾-3应该读取'" .. last_chars .. "'，实际'" .. (data or "nil") .. "'")

    -- 3. 测试 SEEK_END 边界处理
    log.info("测试", "--- 测试边界处理 ---")
    -- 3.1 测试向前超出边界（负值过大）
    pos = buff:seek(-(buff_len + 10), zbuff.SEEK_END)
    assert(pos == 0, "断言失败: SEEK_END向前超出边界应该返回0，实际" .. pos)
    -- 3.2 测试向后移动（正值，应该截断）
    pos = buff:seek(5, zbuff.SEEK_END)
    assert(pos == buff_len, "断言失败: SEEK_END向后移动应截断到末尾" .. buff_len .. "，实际" .. pos)
    -- 3.3 测试从末尾向前移动0字节
    pos = buff:seek(0, zbuff.SEEK_END)
    assert(pos == buff_len, "断言失败: SEEK_END 0应该返回缓冲区长度")

    log.info("zbuff.SEEK_END 模式测试全部通过！")
end

-- 测试固定长度字符串(A)的打包和解包
-- 测试目的: 验证指定长度字符串的处理
-- 测试内容: 打包一个指定长度的字符串
-- 预期结果: 解包后得到指定长度的字符串
function zbuff_tests.test_pack_string()
    log.info("zbuff_tests", "开始 固定长度字符串打包解包测试")
    local buff = zbuff.create(35)
    local str = "Hello123"
    local data = buff:pack("<A", str)
    assert(data == #str, "固定长度字符串打包失败")
    log.info("data", data)
end

-- function zbuff_tests.test_pack_float()
--     log.info("zbuff_tests", "开始 固定长度字符串打包解包测试")
--     local buff = zbuff.create(35)
--     local str = "Hello123"
--     local data = buff:pack("<A", str)
--     assert(data == #str, "固定长度字符串打包失败")
--     log.info("data",data)
-- end

-- function pack_tests.test_pack_byte_boundary()
--     log.info("pack_tests", "开始 byte边界值测试")
--     local buff = zbuff.create(3)
--     -- 测试最小值
--     local data_min = buff:pack("c", 0)
--     local pos, val_min = pack.unpack(data_min, "b")
--     assert(val_min == 0, "byte最小值(0)解包错误")

--     -- 测试最大值
--     local data_max = pack.pack("b", 255)
--     local pos, val_max = pack.unpack(data_max, "b")
--     assert(val_max == 255, "byte最大值(255)解包错误")

--     log.info("pack", "byte边界值测试成功: min=", val_min, "max=", val_max)
-- end

-- 测试short类型的边界值
-- 测试目的: 验证short类型能正确处理-32768到32767范围的值
-- 测试内容: 打包最小值和最大值
-- 预期结果: 边界值都能正确解包
-- function pack_tests.test_pack_short_boundary()
--     log.info("pack_tests", "开始 short边界值测试")
--     local buff = zbuff.create(3)
--     -- 测试最小值
--     local data_min = buff:pack(">h", -32768)
--     local pos, val_min = pack.unpack(data_min, ">h")
--     assert(val_min == -32768, "short最小值(-32768)解包错误")

--     -- 测试最大值
--     local data_max = pack.pack(">h", 32767)
--     local pos, val_max = pack.unpack(data_max, ">h")
--     assert(val_max == 32767, "short最大值(32767)解包错误")

--     log.info("pack", "short边界值测试成功: min=", val_min, "max=", val_max)
-- end

-- 1. 测试有符号8位整数
function zbuff_tests.test_wirteReadI8()
    local buff = zbuff.create(16) -- 分配更大空间
    -- 测试最小值（位置0）
    local len = buff:writeI8(0x80) -- 写入 -128 (0x80的二进制补码)；
    assert(len == 1, "使用writeI8成功写入最小值此时的字节数应为1实际是" .. len)
    buff:seek(0)
    local val_min = buff:readI8()
    assert(val_min == -128, "ReadI8最小值(-128)解包错误")

    -- 测试最大值（位置1，避免覆盖）
    local len1 = buff:writeI8(0x7F)
    assert(len1 == 1, "使用writeI8成功写入最大值此时的字节数应为1实际是" .. len1)
    buff:seek(1) -- 回到位置1
    local val_max = buff:readI8()
    assert(val_max == 127, "ReadI8最大值(127)解包错误")
    log.info("test_wirteReadI8", "测试通过")
end

-- 2. 测试无符号8位整数
function zbuff_tests.test_writeReadU8()
    local buff = zbuff.create(16)
    -- 测试最小值 0
    local len_min = buff:writeU8(0)
    assert(len_min == 1, "writeU8最小值写入字节数错误: " .. len_min)
    buff:seek(0)
    local val_min = buff:readU8()
    assert(val_min == 0, "U8最小值(0)读取错误: " .. val_min)

    -- 测试最大值 255
    local len_max = buff:writeU8(255)
    assert(len_max == 1, "writeU8最大值写入字节数错误: " .. len_max)
    buff:seek(1)
    local val_max = buff:readU8()
    assert(val_max == 255, "U8最大值(255)读取错误: " .. val_max)

    log.info("test_writeReadU8", "测试通过")
end

-- 3. 测试有符号16位整数
function zbuff_tests.test_writeReadI16()
    local buff = zbuff.create(16)

    -- 测试最小值 -32768
    local len_min = buff:writeI16(-32768)
    assert(len_min == 2, "writeI16最小值写入字节数错误: " .. len_min)
    buff:seek(0)
    local val_min = buff:readI16()
    assert(val_min == -32768, "I16最小值(-32768)读取错误: " .. val_min)

    -- 测试最大值 32767
    local len_max = buff:writeI16(32767)
    assert(len_max == 2, "writeI16最大值写入字节数错误: " .. len_max)
    buff:seek(2)
    local val_max = buff:readI16()
    assert(val_max == 32767, "I16最大值(32767)读取错误: " .. val_max)

    log.info("test_writeReadI16", "测试通过")
end

-- 4. 测试无符号16位整数
function zbuff_tests.test_writeReadU16()
    local buff = zbuff.create(16)

    -- 测试最小值 0
    local len_min = buff:writeU16(0)
    assert(len_min == 2, "writeU16最小值写入字节数错误: " .. len_min)
    buff:seek(0)
    local val_min = buff:readU16()
    assert(val_min == 0, "U16最小值(0)读取错误: " .. val_min)

    -- 测试最大值 65535
    local len_max = buff:writeU16(65535)
    assert(len_max == 2, "writeU16最大值写入字节数错误: " .. len_max)
    buff:seek(2)
    local val_max = buff:readU16()
    assert(val_max == 65535, "U16最大值(65535)读取错误: " .. val_max)

    log.info("test_writeReadU16", "测试通过")
end

-- 5. 测试有符号32位整数
function zbuff_tests.test_writeReadI32()
    local buff = zbuff.create(16)

    -- 测试最小值 -2147483648 (-2^31)
    local len_min = buff:writeI32(-2147483648)
    assert(len_min == 4, "writeI32最小值写入字节数错误: " .. len_min)
    buff:seek(0)
    local val_min = buff:readI32()
    assert(val_min == -2147483648, "I32最小值(-2^31)读取错误: " .. val_min)

    -- 测试最大值 2147483647 (2^31-1)
    local len_max = buff:writeI32(2147483647)
    assert(len_max == 4, "writeI32最大值写入字节数错误: " .. len_max)
    buff:seek(4)
    local val_max = buff:readI32()
    assert(val_max == 2147483647, "I32最大值(2^31-1)读取错误: " .. val_max)

    log.info("test_writeReadI32", "测试通过")
end

-- 6. 测试无符号32位整数
function zbuff_tests.test_writeReadU32()
    local buff = zbuff.create(16)

    -- 测试最小值 0
    local len_min = buff:writeU32(0)
    assert(len_min == 4, "writeU32最小值写入字节数错误: " .. len_min)
    buff:seek(0)
    local val_min = buff:readU32()
    assert(val_min == 0, "U32最小值(0)读取错误: " .. val_min)

    -- 测试最大值 4294967295 (2^32-1)
    local len_max = buff:writeU32(0xFFFFFFFF) -- 使用十六进制
    assert(len_max == 4, "writeU32最大值写入字节数错误: " .. len_max)
    buff:seek(4)
    local val_max = buff:readU32()
    assert(val_max == 0xFFFFFFFF, "U32最大值(2^32-1)读取错误: " .. val_max)

    log.info("test_writeReadU32", "测试通过")
end

-- 7. 测试有符号64位整数
function zbuff_tests.test_writeReadI64()
    local buff = zbuff.create(16)

    -- 注意：Lua可能不支持完整的64位整数，测试时使用合理范围
    -- 测试负值
    local len_neg = buff:writeI64(-1000000000)
    assert(len_neg == 8, "writeI64负值写入字节数错误: " .. len_neg)
    buff:seek(0)
    local val_neg = buff:readI64()
    assert(val_neg == -1000000000, "I64负值读取错误: " .. val_neg)

    -- 测试正值
    local len_pos = buff:writeI64(1000000000)
    assert(len_pos == 8, "writeI64正值写入字节数错误: " .. len_pos)
    buff:seek(8)
    local val_pos = buff:readI64()
    assert(val_pos == 1000000000, "I64正值读取错误: " .. val_pos)

    log.info("test_writeReadI64", "测试通过")
end

-- 8. 测试无符号64位整数
function zbuff_tests.test_writeReadU64()
    local buff = zbuff.create(16)

    -- 测试最小值 0
    local len_min = buff:writeU64(0)
    assert(len_min == 8, "writeU64最小值写入字节数错误: " .. len_min)
    buff:seek(0)
    local val_min = buff:readU64()
    assert(val_min == 0, "U64最小值(0)读取错误: " .. val_min)

    local len_val = buff:writeU64(0xFFFFFFFFFFFFFFFF)
    assert(len_val == 8, "writeU64大数值写入字节数错误: " .. len_val)
    buff:seek(8)
    local val = buff:readU64()
    assert(val == 0xFFFFFFFFFFFFFFFF, "U64大数值读取错误: " .. val)

    log.info("test_writeReadU64", "测试通过")
end

-- 9. 测试单精度浮点数
function zbuff_tests.test_writeReadF32()
    local buff = zbuff.create(16)

    -- 测试正浮点数
    local len_pos = buff:writeF32(3.14159)
    assert(len_pos == 4, "writeF32正值写入字节数错误: " .. len_pos)
    buff:seek(0)
    local val_pos = buff:readF32()
    -- 浮点数比较允许误差
    assert(math.abs(val_pos - 3.14159) < 0.0001, "F32正值读取错误: " .. val_pos)

    -- 测试负浮点数
    local len_neg = buff:writeF32(-123.456)
    assert(len_neg == 4, "writeF32负值写入字节数错误: " .. len_neg)
    buff:seek(4)
    local val_neg = buff:readF32()
    assert(math.abs(val_neg - (-123.456)) < 0.001, "F32负值读取错误: " .. val_neg)

    log.info("test_writeReadF32", "测试通过")
end

-- 10. 测试双精度浮点数
function zbuff_tests.test_writeReadF64()
    local buff = zbuff.create(16)

    -- 测试正浮点数
    local len_pos = buff:writeF64(3.141592653589793)
    assert(len_pos == 8, "writeF64正值写入字节数错误: " .. len_pos)
    buff:seek(0)
    local val_pos = buff:readF64()
    -- 双精度浮点数比较允许误差
    assert(math.abs(val_pos - 3.141592653589793) < 0.0000000001, "F64正值读取错误: " .. val_pos)

    -- 测试负浮点数
    local len_neg = buff:writeF64(-987654321.123456)
    assert(len_neg == 8, "writeF64负值写入字节数错误: " .. len_neg)
    buff:seek(8)
    local val_neg = buff:readF64()
    assert(math.abs(val_neg - (-987654321.123456)) < 0.0001, "F64负值读取错误: " .. val_neg)

    log.info("test_writeReadF64", "测试通过")
end

-- buff:toStr测试

function zbuff_tests.test_buffToStr()
    -- 若通过 buff:seek() 移动指针，会影响 used() 的返回值；
    local buff = zbuff.create(10)
    local data = "HelloWorld"
    -- 写入10字节字符串；
    buff:write(data)
    local expected_str = "Hello"
    -- 移动指针到中间位置（不影响toStr）；
    buff:seek(5)
    -- 1.读取开头的5字节；
    local s1 = buff:toStr(0, 5)
    assert(s1 == expected_str, string.format("从头取出5个字节不成功 :  预期 %s,实际 %s", expected_str, s1))
    -- 输出: "Hello"；

    -- 2. 读取整个缓冲区；
    local s2 = buff:toStr()
    -- 输出: "HelloWorld"；
    assert(s2 == data, string.format("读取整个缓冲区不成功 :  预期 %s,实际 %s", data, s2))

    -- 3.读取已使用部分；
    local s3 = buff:toStr(0, buff:used())
    assert(s3 == s1, string.format("从头取出5个字节不成功 :  预期 %s,实际 %s", s1, s3))
    -- 输出: "Hello" (同s1)；
    log.info("test_buffToStr", "测试通过")
end

-- buff[]_read
function zbuff_tests.test_buff_arrayRead()
    local buff = zbuff.create(8)
    -- 1.写入数据
    local len = buff:write(0x1a, 0x30, 0x31, 0x32, 0x00, 0x01)
    assert(len == 6, "写入字节数错误: " .. len)

    -- 2.使用数组索引读取单个字节（返回数字）
    local byte_value = buff[0] -- 返回数字 0x1A (26)

    -- 3.使用 read(1) 读取单个字节（返回zbuff对象）
    buff:seek(0) -- 重置读取指针
    local read_obj = buff:read(1) -- 读取1个字节      
    -- 将数组索引读取的值也转换为十六进制字符串
    local array_hex = string.format("%02X", byte_value)
    local read_hex = read_obj:toHex() -- 转换为十六进制字符串

    -- 比较两个十六进制字符串
    assert(read_hex == array_hex,
        string.format("buff[0] 和 read(1) 不一致: buff[0]=%s, read(1)=%s", array_hex, read_hex))

    log.info("test_buff_array", "单个字节比较通过")
end

-- buff[]_write
function zbuff_tests.test_buff_arrayWrite()
    local buff = zbuff.create(8)
    local expected_data = "1A3031"
    -- 1.写入数据
    buff[0] = 0x1A
    buff[1] = 0x30
    buff[2] = 0x31

    -- 3.使用 read() 读取多个字节（返回zbuff对象）
    buff:seek(0) -- 重置读取指针
    local read_obj = buff:read(3) -- 读取1个字节      
    local read_hex = read_obj:toHex() -- 转换为十六进制字符串
    log.info("read_hex", read_hex)

    -- 比较两个十六进制字符串
    assert(read_hex == expected_data,
        string.format("使用buff[]连续写入不成功：预期%s,实际%s", expected_data, read_hex))

    log.info("test_buff_array", "单个字节比较通过")
end

-- buff_Resize()扩容
function zbuff_tests.test_buffResize_expansion()
    local buff = zbuff.create(8)
    buff:write("ABCD")
    local used = buff:used()
    local old_len = buff:len()
    buff:resize(20)
    local new_len = buff:len()
    local used1 = buff:used()
    assert(new_len == 20 and used1 == used, string.format(
        "使用buff:resize()进行扩容失败或对buff:used()造成影响,扩容后的空间大小%s,扩容前的已用空间大小%d ,扩容后的已用空间大小%d",
        new_len, used, used1))
    log.info("test_buff_buffResize", "扩容成功")

end

-- buff_Resize()缩容及数据截断
function zbuff_tests.test_buffResizeReduce()
    local buff = zbuff.create(10)
    -- 写入9字节，used=9；
    buff:write("123456789")
    local used = buff:used()
    local old_len = buff:len() -- 10
    buff:resize(5)
    local new_len = buff:len() -- 5
    local used1 = buff:used() -- 原数据长度大于缩容后的空间容量，所以被截断
    assert(new_len == 5, string.format("使用buff:resize()进行缩容失败,缩容后的空间大小%d", new_len))
    assert(used1 ~= used and used1 == new_len, string.format(
        "使用buff:resize()进行缩，容原数据长度大于缩容后的空间容量，数据却没有被截断,缩容前的已用空间大小%d ,缩容后的已用空间大小%d",
        used, used1))
    log.info("test_buff_buffResize", "缩容成功")
end

-- 动态写入string
function zbuff_tests.test_buffCopyString()
    local buff = zbuff.create(8)
    local len = buff:copy(nil, "stst")
    assert(len ~= 0, string.format("使用buff:copy动态写入string失败,成功写入的字节数%d", len))
    log.info("test_buffCopyString", "动态写入string成功")
end

-- 动态复制zbuff
function zbuff_tests.test_buffCopyZbuff()
    local buff = zbuff.create(8)
    local buff1 = zbuff.create(8)
    local write_len = buff1:write(0x1a, 0x30, 0x31, 0x32, 0x00, 0x01)
    local len = buff:copy(nil, buff1)
    assert(len == write_len, string.format("使用buff:copy动态复制zbuff失败,成功写入的字节数%d", len))
    log.info("test_buffCopyZbuff", "动态复制zbuff成功")
end

-- 动态写入number
function zbuff_tests.test_buffCopyNumber()
    local buff = zbuff.create(8)
    local len = buff:copy(nil, 0x1a, 0x30, 0x31, 0x32, 0x00, 0x01)
    assert(len ~= 0, string.format("使用buff:copy动态写入number失败,成功写入的字节数%d", len))
    log.info("test_buffCopyNumber", "动态复制number成功")
end

-- buff:used()
function zbuff_tests.test_buffused()
    -- 若通过 buff:seek() 移动指针，会影响 used() 的返回值；
    local buff = zbuff.create(10)
    local data = "HelloWorld"
    -- 写入10字节字符串；
    buff:write(data)
    local expected_str = "Hello"
    local s1 = buff:toStr(0, buff:used())
    buff:seek(5)
    -- 1.读取开头的5字节；
    local s2 = buff:toStr(0, buff:used())
    -- 2.读取整个缓冲区；
    -- 指针移动到开头
    assert(s2 == expected_str and s1 == data, string.format(
        "buff:used()结果异常，指针位置不同结果应该不同 :  buff:seek(5)时的有效数据长度 %s, buff:seek(0)时的有效数据长度%s",
        s1, s2))
    log.info("test_buffToStr", "测试通过")
end

function zbuff_tests.test_buffDel()
    -- 删除zbuff 0~used范围内的一段数据 
    local buff = zbuff.create(10)
    -- 写入 9 字节，used=9；  
    buff:write("123456789")
    -- 删除位置 1 开始的 4 字节，即删除 "2345"；  
    buff:del(1, 4)
    -- 输出: 5 (9-4)； 
    local used = buff:used()
    log.info("删除后 used", buff:used())
    assert(used ~= 9, string.format("buff:del()删除0~used范围内的一段数据失败，:  实际大小%s", used))
end

return zbuff_tests
