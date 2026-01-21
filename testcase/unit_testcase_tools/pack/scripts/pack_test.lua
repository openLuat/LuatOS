local pack_tests = {}

-- 获取固件位数信息，用于判断是否支持64位类型
local luatos_version, luatos_version_num, luatos_version_system = rtos.version(true)
local is_64bit = (luatos_version_system == "64bit")

-- ==================== 基本类型打包解包测试 ====================

-- 测试基本的字符打包和解包功能
-- 测试目的: 验证pack.pack和pack.unpack对char类型的处理
-- 测试内容: 打包一个char值，然后解包验证
-- 预期结果: 解包后的值与原始值相等
function pack_tests.test_pack_unpack_char()
    log.info("pack_tests", "开始 char类型打包解包测试")
    local val = 65  -- 'A'的ASCII码
    local data = pack.pack("c", val)
    assert(data ~= nil, "char打包失败")
    assert(#data == 1, "char应该占1字节")
    
    local pos, result = pack.unpack(data, "c")
    assert(result ~= nil, "char解包失败")
    assert(result == val, string.format("char解包值错误: 预期 %d, 实际 %d", val, result))
    log.info("pack", "char打包解包成功, 值:", result)
end

-- 测试无符号字节打包和解包
-- 测试目的: 验证byte(unsigned char)类型的正确处理
-- 测试内容: 打包一个byte值，然后解包验证
-- 预期结果: 解包后的值与原始值相等
function pack_tests.test_pack_unpack_byte()
    log.info("pack_tests", "开始 byte类型打包解包测试")
    local val = 200
    local data = pack.pack("b", val)
    assert(data ~= nil, "byte打包失败")
    assert(#data == 1, "byte应该占1字节")
    
    local pos, result = pack.unpack(data, "b")
    assert(result ~= nil, "byte解包失败")
    assert(result == val, string.format("byte解包值错误: 预期 %d, 实际 %d", val, result))
    log.info("pack", "byte打包解包成功, 值:", result)
end

-- 测试short类型打包和解包
-- 测试目的: 验证short(2字节有符号整数)的正确处理
-- 测试内容: 打包一个short值，然后解包验证
-- 预期结果: 解包后的值与原始值相等
function pack_tests.test_pack_unpack_short()
    log.info("pack_tests", "开始 short类型打包解包测试")
    local val = -1234
    local data = pack.pack(">h", val)
    assert(data ~= nil, "short打包失败")
    assert(#data == 2, "short应该占2字节")
    
    local pos, result = pack.unpack(data, ">h")
    assert(result ~= nil, "short解包失败")
    assert(result == val, string.format("short解包值错误: 预期 %d, 实际 %d", val, result))
    log.info("pack", "short打包解包成功, 值:", result)
end

-- 测试unsigned short类型打包和解包
-- 测试目的: 验证unsigned short(2字节无符号整数)的正确处理
-- 测试内容: 打包一个unsigned short值，然后解包验证
-- 预期结果: 解包后的值与原始值相等
function pack_tests.test_pack_unpack_ushort()
    log.info("pack_tests", "开始 unsigned short类型打包解包测试")
    local val = 50000
    local data = pack.pack(">H", val)
    assert(data ~= nil, "unsigned short打包失败")
    assert(#data == 2, "unsigned short应该占2字节")
    
    local pos, result = pack.unpack(data, ">H")
    assert(result ~= nil, "unsigned short解包失败")
    assert(result == val, string.format("unsigned short解包值错误: 预期 %d, 实际 %d", val, result))
    log.info("pack", "unsigned short打包解包成功, 值:", result)
end

-- 测试int类型打包和解包
-- 测试目的: 验证int(4字节有符号整数)的正确处理
-- 测试内容: 打包一个int值，然后解包验证
-- 预期结果: 解包后的值与原始值相等
function pack_tests.test_pack_unpack_int()
    log.info("pack_tests", "开始 int类型打包解包测试")
    local val = -123456
    local data = pack.pack(">i", val)
    assert(data ~= nil, "int打包失败")
    assert(#data == 4, "int应该占4字节")
    
    local pos, result = pack.unpack(data, ">i")
    assert(result ~= nil, "int解包失败")
    assert(result == val, string.format("int解包值错误: 预期 %d, 实际 %d", val, result))
    log.info("pack", "int打包解包成功, 值:", result)
end

-- 测试unsigned int类型打包和解包
-- 测试目的: 验证unsigned int(4字节无符号整数)的正确处理
-- 测试内容: 打包一个unsigned int值，然后解包验证
-- 预期结果: 解包后的值与原始值相等
function pack_tests.test_pack_unpack_uint()
    log.info("pack_tests", "开始 unsigned int类型打包解包测试")

    -- 仅64bit固件支持正确的无符号32位范围
    if not is_64bit then
        log.info("pack_tests", string.format("当前固件为%s，跳过unsigned int测试(仅64bit固件)", luatos_version_system))
        return
    end
    local val = 3000000000
    local data = pack.pack(">I", val)
    assert(data ~= nil, "unsigned int打包失败")
    assert(#data == 4, "unsigned int应该占4字节")
    
    local pos, result = pack.unpack(data, ">I")
    assert(result ~= nil, "unsigned int解包失败")
    assert(result == val, string.format("unsigned int解包值错误: 预期 %d, 实际 %d", val, result))
    log.info("pack", "unsigned int打包解包成功, 值:", result)
end

-- 测试long类型打包和解包
-- 测试目的: 验证long(8字节有符号整数)的正确处理
-- 测试内容: 打包一个long值，然后解包验证
-- 预期结果: 解包后的值与原始值相等
-- 注意: 仅在64bit固件上运行，32bit固件无法正确处理64位整数
function pack_tests.test_pack_unpack_long()
    log.info("pack_tests", "开始 long类型打包解包测试")
    
    if not is_64bit then
        log.info("pack_tests", string.format("当前固件为%s，跳过long测试(仅64bit固件支持)", luatos_version_system))
        return
    end
    
    local val = -9876543210
    local data = pack.pack(">l", val)
    assert(data ~= nil, "long打包失败")
    assert(#data == 8, "long应该占8字节")
    
    local pos, result = pack.unpack(data, ">l")
    assert(result ~= nil, "long解包失败")
    assert(result == val, string.format("long解包值错误: 预期 %d, 实际 %d", val, result))
    log.info("pack", "long打包解包成功, 值:", result)
end

-- 测试unsigned long类型打包和解包
-- 测试目的: 验证unsigned long(8字节无符号整数)的正确处理
-- 测试内容: 打包一个unsigned long值，然后解包验证
-- 预期结果: 解包后的值与原始值相等
-- 注意: 仅在64bit固件上运行，32bit固件无法正确处理64位整数
function pack_tests.test_pack_unpack_ulong()
    log.info("pack_tests", "开始 unsigned long类型打包解包测试")
    
    if not is_64bit then
        log.info("pack_tests", string.format("当前固件为%s，跳过unsigned long测试(仅64bit固件支持)", luatos_version_system))
        return
    end
    
    local val = 18446744073709551615  -- 最大的64bit无符号整数
    local data = pack.pack(">L", val)
    assert(data ~= nil, "unsigned long打包失败")
    assert(#data == 8, "unsigned long应该占8字节")
    
    local pos, result = pack.unpack(data, ">L")
    assert(result ~= nil, "unsigned long解包失败")
    assert(result == val, string.format("unsigned long解包值错误: 预期 %d, 实际 %d", val, result))
    log.info("pack", "unsigned long打包解包成功, 值:", result)
end

-- ==================== 字符串打包解包测试 ====================

-- 测试零终止字符串(z)的打包和解包
-- 测试目的: 验证以'\0'结尾的字符串处理
-- 测试内容: 打包一个字符串，自动添加'\0'终止符
-- 预期结果: 解包后的字符串与原始字符串相等
function pack_tests.test_pack_unpack_zstring()
    log.info("pack_tests", "开始 零终止字符串打包解包测试")
    local str = "Hello"
    local data = pack.pack("z", str)
    assert(data ~= nil, "零终止字符串打包失败")
    assert(#data == #str + 1, "零终止字符串应该包含\\0")
    
    local pos, result = pack.unpack(data, "z")
    assert(result ~= nil, "零终止字符串解包失败")
    assert(result == str, string.format("零终止字符串解包错误: 预期 %s, 实际 %s", str, result))
    log.info("pack", "零终止字符串打包解包成功, 值:", result)
end

-- 测试固定长度字符串(A)的打包和解包
-- 测试目的: 验证指定长度字符串的处理
-- 测试内容: 打包一个指定长度的字符串
-- 预期结果: 解包后得到指定长度的字符串
function pack_tests.test_pack_unpack_string_fixed()
    log.info("pack_tests", "开始 固定长度字符串打包解包测试")
    local str = "Hello123"
    local data = pack.pack("A8", str)
    assert(data ~= nil, "固定长度字符串打包失败")
    assert(#data == 8, "固定长度字符串应该占8字节")
    
    local pos, result = pack.unpack(data, "A8")
    assert(result ~= nil, "固定长度字符串解包失败")
    assert(result == str, string.format("固定长度字符串解包错误: 预期 %s, 实际 %s", str, result))
    log.info("pack", "固定长度字符串打包解包成功, 值:", result)
end

-- 测试size_t长度前缀字符串(a)的打包和解包
-- 测试目的: 验证前4字节表示长度的字符串处理
-- 测试内容: 打包一个带长度前缀的字符串
-- 预期结果: 解包后得到原始字符串
function pack_tests.test_pack_unpack_string_sstring()
    log.info("pack_tests", "开始 size_t字符串打包解包测试")
    local str = "LuatOS测试"
    local data = pack.pack(">a", str)
    assert(data ~= nil, "size_t字符串打包失败")
    
    local pos, result = pack.unpack(data, ">a")
    assert(result ~= nil, "size_t字符串解包失败")
    assert(result == str, string.format("size_t字符串解包错误: 预期 %s, 实际 %s", str, result))
    log.info("pack", "size_t字符串打包解包成功, 值:", result)
end

-- ==================== 大小端测试 ====================

-- 测试大端序打包
-- 测试目的: 验证大端序(Big Endian)数据格式处理
-- 测试内容: 使用'>'标记打包short值
-- 预期结果: 高字节在前，低字节在后
function pack_tests.test_pack_big_endian()
    log.info("pack_tests", "开始 大端序打包测试")
    local val = 0x1234
    local data = pack.pack(">H", val)
    assert(data ~= nil, "大端序打包失败")
    
    -- 验证字节序: 大端序应该是 0x12 0x34
    local b1 = string.byte(data, 1)
    local b2 = string.byte(data, 2)
    assert(b1 == 0x12, string.format("大端序高字节错误: 预期 0x12, 实际 0x%02X", b1))
    assert(b2 == 0x34, string.format("大端序低字节错误: 预期 0x34, 实际 0x%02X", b2))
    log.info("pack", "大端序打包成功, 字节:", string.format("0x%02X 0x%02X", b1, b2))
end

-- 测试小端序打包
-- 测试目的: 验证小端序(Little Endian)数据格式处理
-- 测试内容: 使用'<'标记打包short值
-- 预期结果: 低字节在前，高字节在后
function pack_tests.test_pack_little_endian()
    log.info("pack_tests", "开始 小端序打包测试")
    local val = 0x1234
    local data = pack.pack("<H", val)
    assert(data ~= nil, "小端序打包失败")
    
    -- 验证字节序: 小端序应该是 0x34 0x12
    local b1 = string.byte(data, 1)
    local b2 = string.byte(data, 2)
    assert(b1 == 0x34, string.format("小端序低字节错误: 预期 0x34, 实际 0x%02X", b1))
    assert(b2 == 0x12, string.format("小端序高字节错误: 预期 0x12, 实际 0x%02X", b2))
    log.info("pack", "小端序打包成功, 字节:", string.format("0x%02X 0x%02X", b1, b2))
end

-- ==================== 多值打包解包测试 ====================

-- 测试多个值的打包和解包
-- 测试目的: 验证一次打包多个不同类型的值
-- 测试内容: 打包byte, short, int多个值，然后解包
-- 预期结果: 所有值都正确解包
function pack_tests.test_pack_unpack_multiple()
    log.info("pack_tests", "开始 多值打包解包测试")
    local v1, v2, v3 = 100, 30000, 1000000
    local data = pack.pack(">bHi", v1, v2, v3)
    assert(data ~= nil, "多值打包失败")
    assert(#data == 1 + 2 + 4, "多值打包长度错误")
    
    local pos, r1, r2, r3 = pack.unpack(data, ">bHi")
    assert(r1 == v1, string.format("第1个值错误: 预期 %d, 实际 %d", v1, r1))
    assert(r2 == v2, string.format("第2个值错误: 预期 %d, 实际 %d", v2, r2))
    assert(r3 == v3, string.format("第3个值错误: 预期 %d, 实际 %d", v3, r3))
    log.info("pack", "多值打包解包成功:", r1, r2, r3)
end

-- 测试混合类型打包和解包
-- 测试目的: 验证字符串和数值混合打包
-- 测试内容: 打包字符串、整数、字符串的组合
-- 预期结果: 所有值都正确解包
function pack_tests.test_pack_unpack_mixed()
    log.info("pack_tests", "开始 混合类型打包解包测试")
    local str1 = "ABC"
    local num = 12345
    local str2 = "XYZ"
    
    local data = pack.pack("A3>HA3", str1, num, str2)
    assert(data ~= nil, "混合类型打包失败")
    
    local pos, s1, n, s2 = pack.unpack(data, "A3>HA3")
    assert(s1 == str1, string.format("字符串1错误: 预期 %s, 实际 %s", str1, s1))
    assert(n == num, string.format("数值错误: 预期 %d, 实际 %d", num, n))
    assert(s2 == str2, string.format("字符串2错误: 预期 %s, 实际 %s", str2, s2))
    log.info("pack", "混合类型打包解包成功:", s1, n, s2)
end

-- ==================== 浮点数测试 ====================

-- 测试float类型打包和解包
-- 测试目的: 验证32位浮点数的处理
-- 测试内容: 打包一个float值，然后解包验证
-- 预期结果: 解包后的值与原始值接近(浮点数精度)
-- 注意: 仅在支持浮点数的固件上运行(非LUA_NUMBER_INTEGRAL)
function pack_tests.test_pack_unpack_float()
    log.info("pack_tests", "开始 float类型打包解包测试")
    
    -- 检查是否支持浮点数
    local test_float = 3.14159
    if test_float == 3 then
        log.info("pack_tests", "当前固件不支持浮点数(LUA_NUMBER_INTEGRAL)，跳过float测试")
        return
    end
    
    local val = 3.14159
    local data = pack.pack(">f", val)
    assert(data ~= nil, "float打包失败")
    assert(#data == 4, "float应该占4字节")
    
    local pos, result = pack.unpack(data, ">f")
    assert(result ~= nil, "float解包失败")
    -- 浮点数比较允许小误差
    local diff = math.abs(result - val)
    assert(diff < 0.00001, string.format("float解包值误差过大: 预期 %f, 实际 %f", val, result))
    log.info("pack", "float打包解包成功, 值:", result)
end

-- 测试double类型打包和解包
-- 测试目的: 验证64位浮点数的处理
-- 测试内容: 打包一个double值，然后解包验证
-- 预期结果: 解包后的值与原始值接近(浮点数精度)
-- 注意: 仅在支持浮点数的固件上运行(非LUA_NUMBER_INTEGRAL)
function pack_tests.test_pack_unpack_double()
    log.info("pack_tests", "开始 double类型打包解包测试")
    
    -- 检查是否支持浮点数
    local test_float = 3.14159
    if test_float == 3 then
        log.info("pack_tests", "当前固件不支持浮点数(LUA_NUMBER_INTEGRAL)，跳过double测试")
        return
    end
    
    local val = 3.141592653589793
    local data = pack.pack(">d", val)
    assert(data ~= nil, "double打包失败")
    assert(#data == 8, "double应该占8字节")
    
    local pos, result = pack.unpack(data, ">d")
    assert(result ~= nil, "double解包失败")
    -- 浮点数比较允许小误差
    local diff = math.abs(result - val)
    assert(diff < 0.0000000001, string.format("double解包值误差过大: 预期 %.15f, 实际 %.15f", val, result))
    log.info("pack", "double打包解包成功, 值:", result)
end

-- ==================== 边界值测试 ====================

-- 测试byte类型的边界值
-- 测试目的: 验证byte类型能正确处理0-255范围的值
-- 测试内容: 打包最小值0和最大值255
-- 预期结果: 边界值都能正确解包
function pack_tests.test_pack_byte_boundary()
    log.info("pack_tests", "开始 byte边界值测试")
    
    -- 测试最小值
    local data_min = pack.pack("b", 0)
    local pos, val_min = pack.unpack(data_min, "b")
    assert(val_min == 0, "byte最小值(0)解包错误")
    
    -- 测试最大值
    local data_max = pack.pack("b", 255)
    local pos, val_max = pack.unpack(data_max, "b")
    assert(val_max == 255, "byte最大值(255)解包错误")
    
    log.info("pack", "byte边界值测试成功: min=", val_min, "max=", val_max)
end

-- 测试short类型的边界值
-- 测试目的: 验证short类型能正确处理-32768到32767范围的值
-- 测试内容: 打包最小值和最大值
-- 预期结果: 边界值都能正确解包
function pack_tests.test_pack_short_boundary()
    log.info("pack_tests", "开始 short边界值测试")
    
    -- 测试最小值
    local data_min = pack.pack(">h", -32768)
    local pos, val_min = pack.unpack(data_min, ">h")
    assert(val_min == -32768, "short最小值(-32768)解包错误")
    
    -- 测试最大值
    local data_max = pack.pack(">h", 32767)
    local pos, val_max = pack.unpack(data_max, ">h")
    assert(val_max == 32767, "short最大值(32767)解包错误")
    
    log.info("pack", "short边界值测试成功: min=", val_min, "max=", val_max)
end

-- ==================== 负例测试 ====================

-- 测试无效的格式字符
-- 测试目的: 验证pack对无效格式字符的错误处理
-- 测试内容: 使用不存在的格式字符进行打包
-- 预期结果: 函数应该报错，不会崩溃
function pack_tests.test_pack_invalid_format()
    log.info("pack_tests", "开始 无效格式字符测试")
    
    local success, err = pcall(function()
        pack.pack("X", 123)  -- 'X'不是有效的格式字符
    end)
    
    assert(success == false, "无效格式字符应该返回错误")
    log.info("pack", "无效格式字符正确返回错误:", err)
end

-- 测试参数不足
-- 测试目的: 验证pack在参数不足时的错误处理
-- 测试内容: 格式字符串要求2个值，但只提供1个
-- 预期结果: 函数应该报错
function pack_tests.test_pack_insufficient_args()
    log.info("pack_tests", "开始 参数不足测试")
    
    local success, err = pcall(function()
        pack.pack(">HH", 100)  -- 需要2个参数，只提供1个
    end)
    
    assert(success == false, "参数不足应该返回错误")
    log.info("pack", "参数不足正确返回错误:", err)
end

-- 测试数据不足的解包
-- 测试目的: 验证unpack在数据长度不足时的处理
-- 测试内容: 尝试从1字节数据中解包一个short(2字节)
-- 预期结果: 解包失败，返回nil或部分结果
function pack_tests.test_unpack_insufficient_data()
    log.info("pack_tests", "开始 数据不足解包测试")
    
    local data = string.char(0x12)  -- 只有1字节
    local pos, result = pack.unpack(data, ">H")  -- 尝试解包2字节的short
    
    -- 数据不足时，unpack会在done标签处返回，result应该为nil
    assert(result == nil, "数据不足时应该返回nil")
    log.info("pack", "数据不足正确返回nil")
end

-- 测试空字符串解包
-- 测试目的: 验证unpack对空字符串的处理
-- 测试内容: 尝试从空字符串解包
-- 预期结果: 返回初始位置1，没有解包任何值
function pack_tests.test_unpack_empty_string()
    log.info("pack_tests", "开始 空字符串解包测试")
    
    local data = ""
    local pos = pack.unpack(data, ">H")
    
    assert(pos == 1, "空字符串解包应该返回位置1")
    log.info("pack", "空字符串解包正确返回位置:", pos)
end

-- 测试数值类型溢出
-- 测试目的: 验证数值超出类型范围时的处理
-- 测试内容: 将超出byte范围的值打包为byte
-- 预期结果: 值会被截断到类型范围内
function pack_tests.test_pack_overflow()
    log.info("pack_tests", "开始 数值溢出测试")
    
    local val = 256  -- 超出byte范围(0-255)
    local data = pack.pack("b", val)
    local pos, result = pack.unpack(data, "b")
    
    -- 256会被截断为0 (256 % 256 = 0)
    assert(result == 0, string.format("溢出值应该被截断: 预期 0, 实际 %d", result))
    log.info("pack", "数值溢出正确处理, 结果:", result)
end

-- 测试负数作为无符号类型
-- 测试目的: 验证负数打包为无符号类型时的处理
-- 测试内容: 将负数打包为unsigned byte
-- 预期结果: 负数会被转换为对应的无符号值
function pack_tests.test_pack_negative_as_unsigned()
    log.info("pack_tests", "开始 负数作为无符号类型测试")
    
    local val = -1
    local data = pack.pack("b", val)
    local pos, result = pack.unpack(data, "b")
    
    -- -1作为byte应该变成255 (0xFF)
    assert(result == 255, string.format("负数转无符号错误: 预期 255, 实际 %d", result))
    log.info("pack", "负数作为无符号类型正确处理, 结果:", result)
end

-- 测试解包位置参数
-- 测试目的: 验证unpack的init参数能正确指定解包起始位置
-- 测试内容: 从字符串中间位置开始解包
-- 预期结果: 从指定位置正确解包数据
function pack_tests.test_unpack_with_position()
    log.info("pack_tests", "开始 解包位置参数测试")
    
    local data = pack.pack(">HH", 0x1234, 0x5678)
    -- 从第3字节开始解包(跳过第一个short)
    local pos, result = pack.unpack(data, ">H", 3)
    
    assert(result == 0x5678, string.format("从位置3解包错误: 预期 0x5678, 实际 0x%04X", result))
    assert(pos == 5, string.format("解包后位置错误: 预期 5, 实际 %d", pos))
    log.info("pack", "解包位置参数测试成功, 值:", string.format("0x%04X", result))
end

-- ==================== 实际应用场景测试 ====================

-- 测试CRC16打包应用
-- 测试目的: 验证pack在实际CRC校验中的应用
-- 测试内容: 计算字符串的CRC16，然后打包为小端序short
-- 预期结果: 打包和解包后CRC值保持一致
function pack_tests.test_pack_crc16_application()
    log.info("pack_tests", "开始 CRC16应用测试")
    
    local val = "LuatOS"
    local crc = crypto.crc16("MODBUS", val)
    log.info("pack", "CRC16值:", crc)
    
    -- 打包为小端序
    local data = pack.pack('<H', crc)
    assert(#data == 2, "CRC16应该占2字节")
    
    -- 解包验证
    local pos, crc_unpacked = pack.unpack(data, '<H')
    assert(crc_unpacked == crc, string.format("CRC16解包错误: 预期 %d, 实际 %d", crc, crc_unpacked))
    log.info("pack", "CRC16应用测试成功, 原始CRC:", crc, "解包CRC:", crc_unpacked)
end

-- 测试协议数据包打包
-- 测试目的: 验证pack在构造通信协议数据包中的应用
-- 测试内容: 打包一个包含帧头、长度、数据、校验的数据包
-- 预期结果: 能够正确打包和解包整个数据包
function pack_tests.test_pack_protocol_packet()
    log.info("pack_tests", "开始 协议数据包测试")
    
    -- 构造数据包: 帧头(2字节) + 长度(1字节) + 数据(N字节) + 校验(2字节)
    local header = 0xAA55
    local payload = "Hello"
    local length = #payload
    local checksum = 0x1234
    
    local packet = pack.pack(">HbA5H", header, length, payload, checksum)
    assert(packet ~= nil, "数据包打包失败")
    log.info("pack", "数据包长度:", #packet, "内容:", packet:toHex())
    
    -- 解包验证
    local pos, h, len, data, cs = pack.unpack(packet, ">HbA5H")
    assert(h == header, string.format("帧头错误: 预期 0x%04X, 实际 0x%04X", header, h))
    assert(len == length, string.format("长度错误: 预期 %d, 实际 %d", length, len))
    assert(data == payload, string.format("数据错误: 预期 %s, 实际 %s", payload, data))
    assert(cs == checksum, string.format("校验错误: 预期 0x%04X, 实际 0x%04X", checksum, cs))
    log.info("pack", "协议数据包测试成功")
end

-- 测试传感器数据打包
-- 测试目的: 验证pack在处理传感器数据中的应用
-- 测试内容: 打包温度、湿度等浮点数传感器数据
-- 预期结果: 能够正确打包和解包浮点数据
-- 注意: 仅在支持浮点数的固件上运行
function pack_tests.test_pack_sensor_data()
    log.info("pack_tests", "开始 传感器数据打包测试")
    
    -- 检查是否支持浮点数
    local test_float = 25.6
    if test_float == 25 then
        log.info("pack_tests", "当前固件不支持浮点数，跳过传感器数据测试")
        return
    end
    
    local temperature = 25.6
    local humidity = 65.3
    local pressure = 1013.25
    
    local data = pack.pack(">fff", temperature, humidity, pressure)
    assert(data ~= nil, "传感器数据打包失败")
    assert(#data == 12, "3个float应该占12字节")
    
    local pos, temp, humi, pres = pack.unpack(data, ">fff")
    assert(math.abs(temp - temperature) < 0.01, "温度解包错误")
    assert(math.abs(humi - humidity) < 0.01, "湿度解包错误")
    assert(math.abs(pres - pressure) < 0.01, "压力解包错误")
    log.info("pack", string.format("传感器数据: 温度=%.1f℃, 湿度=%.1f%%, 气压=%.2fhPa", temp, humi, pres))
end

return pack_tests
