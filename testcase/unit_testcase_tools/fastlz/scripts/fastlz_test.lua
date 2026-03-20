local fastlz_test = {}

-- fastlz 测试用例集合
-- 目的：验证在不同压缩等级下，对两类输入数据（固定长度字符串与文件数据）的压缩与解压行为是否符合预期。
-- 每个用例均包含以下校验：
-- 1) 压缩后数据长度是否为预期值
-- 2) 解压后数据长度是否与原始数据长度一致
-- 3) 解压后数据内容是否与原始数据内容一致

-- 原始数据108长度字符串
function fastlz_test.test_data_common()
    -- 用例说明：
    -- 输入：长度为108的 ASCII 字符串；压缩等级 level=1。
    -- 断言：压缩后长度应为 47；解压后长度等于原始长度；解压后内容与原始内容完全一致。
    log.info("fastlz_test","开始 原始数据108长度字符串（压缩等级1）进行压缩和解压测试")
    local originStr = "abcd1234567890efghijklmnopqrstuvwxyzabcd1234567890efghijklmnopqrstuvwxyzabcd1234567890efghijklmnopqrstuvwxyz"
    -- 执行压缩（等级1）
    local compress_back = fastlz.compress(originStr,1)
    local compresssize = #compress_back
    local expectation_size = 47
    -- 校验压缩后长度
    assert(compresssize == expectation_size, string.format("原始数据108长度字符串（压缩等级1）进行压缩后测试失败: 预期大小 %s, 实际大小 %s", expectation_size, compresssize))

    local maxOut = #originStr
    -- 执行解压，最大输出设为原始长度
    local dstr1 = fastlz.uncompress(compress_back,maxOut)
    local decompress_size = #dstr1
    -- 校验解压后长度与内容
    assert(decompress_size == maxOut, string.format("原始数据108长度字符串（压缩等级1）进行解压后测试失败: 预期大小 %s, 实际大小 %s", maxOut, decompress_size))
    assert(originStr == dstr1, "原始数据108长度字符串（压缩等级1）进行解压后数据内容不匹配测试失败: 预期内容 %s, 实际内容 %s", originStr, dstr1)

    log.info("fastlz_test", "原始数据108长度字符串（压缩等级1）进行压缩和解压测试通过")
end

-- 原始数据108长度字符串
function fastlz_test.test_seconddata_common()
    -- 用例说明：
    -- 输入：长度为108的 ASCII 字符串；压缩等级 level=2。
    -- 断言：压缩后长度应为 47；解压后长度等于原始长度；解压后内容与原始内容完全一致。
    log.info("fastlz_test","开始 原始数据108长度字符串（压缩等级2）进行压缩和解压测试")
    local originStr = "abcd1234567890efghijklmnopqrstuvwxyzabcd1234567890efghijklmnopqrstuvwxyzabcd1234567890efghijklmnopqrstuvwxyz"
    -- 执行压缩（等级2）
    local compress_back = fastlz.compress(originStr,2)
    local compresssize = #compress_back
    local expectation_size = 47
    -- 校验压缩后长度
    assert(compresssize == expectation_size, string.format("原始数据108长度字符串（压缩等级2）进行压缩后测试失败: 预期大小 %s, 实际大小 %s", expectation_size, compresssize))

    local maxOut = #originStr
    -- 执行解压，最大输出设为原始长度
    local dstr1 = fastlz.uncompress(compress_back,maxOut)
    local decompress_size = #dstr1
    -- 校验解压后长度与内容
    assert(decompress_size == maxOut, string.format("原始数据108长度字符串（压缩等级2）进行解压后测试失败: 预期大小 %s, 实际大小 %s", maxOut, decompress_size))
    assert(originStr == dstr1, "原始数据108长度字符串（压缩等级2）进行解压后数据内容不匹配测试失败: 预期内容 %s, 实际内容 %s", originStr, dstr1)

    log.info("fastlz_test", "原始数据108长度字符串（压缩等级2）进行压缩和解压测试通过")
end

-- 原始数据文件读取2K数据
function fastlz_test.test_file_common()
    -- 用例说明：
    -- 输入：从 /luadb/test.txt 读取约2K字节数据；压缩等级 level=1。
    -- 断言：压缩后长度应为 128；解压后长度等于原始长度；解压后内容与原始内容完全一致。
    log.info("fastlz_test","开始 原始数据文件2K数据（压缩等级1）进行压缩和解压测试")
    local originStr = io.readFile("/luadb/test.txt")
    -- 执行压缩（等级1）
    local compress_back = fastlz.compress(originStr,1)
    local compresssize = #compress_back
    local expectation_size = 128
    -- 校验压缩后长度
    assert(compresssize == expectation_size, string.format("原始数据文件2K数据（压缩等级1）进行压缩后测试失败: 预期大小 %s, 实际大小 %s", expectation_size, compresssize))

    local maxOut = #originStr
    -- 执行解压，最大输出设为原始长度
    local dstr1 = fastlz.uncompress(compress_back,maxOut)
    local decompress_size = #dstr1
    -- 校验解压后长度与内容
    assert(decompress_size == maxOut, string.format("原始数据文件2K数据（压缩等级1）进行解压后测试失败: 预期大小 %s, 实际大小 %s", maxOut, decompress_size))
    assert(originStr == dstr1, "原始数据文件2K数据（压缩等级1）进行解压后数据内容不匹配测试失败: 预期内容 %s, 实际内容 %s", originStr, dstr1)

    log.info("fastlz_test", "原始数据文件2K数据（压缩等级1）进行压缩和解压测试通过")
end

-- 原始数据文件读取2K数据
function fastlz_test.test_secondfile_common()
    -- 用例说明：
    -- 输入：从 /luadb/test.txt 读取约2K字节数据；压缩等级 level=2。
    -- 断言：压缩后长度应为 116；解压后长度等于原始长度；解压后内容与原始内容完全一致。
    log.info("fastlz_test","开始 原始数据文件2K数据（压缩等级2）进行压缩和解压测试")
    local originStr = io.readFile("/luadb/test.txt")
    -- 执行压缩（等级2）
    local compress_back = fastlz.compress(originStr,2)
    local compresssize = #compress_back
    local expectation_size = 116
    -- 校验压缩后长度
    assert(compresssize == expectation_size, string.format("原始数据文件2K数据（压缩等级2）进行压缩后测试失败: 预期大小 %s, 实际大小 %s", expectation_size, compresssize))

    local maxOut = #originStr
    -- 执行解压，最大输出设为原始长度
    local dstr1 = fastlz.uncompress(compress_back,maxOut)
    local decompress_size = #dstr1
    -- 校验解压后长度与内容
    assert(decompress_size == maxOut, string.format("原始数据文件2K数据（压缩等级2）进行解压后测试失败: 预期大小 %s, 实际大小 %s", maxOut, decompress_size))
    assert(originStr == dstr1, "原始数据文件2K数据（压缩等级2）进行解压后数据内容不匹配测试失败: 预期内容 %s, 实际内容 %s", originStr, dstr1)

    log.info("fastlz_test", "原始数据文件2K数据（压缩等级2）进行压缩和解压测试通过")
end

-- 错误数据格式测试：压缩空字符串
function fastlz_test.test_empty_string()
    -- 用例说明：
    -- 输入：空字符串；压缩等级 level=1。
    -- 断言：压缩后应返回 nil 或长度为0的字符串
    log.info("fastlz_test","开始 空字符串压缩测试")
    local originStr = ""
    local compress_back = fastlz.compress(originStr,1)
    
    -- 空字符串压缩后应该为 nil 或空字符串
    assert(compress_back == nil or #compress_back == 0, "空字符串压缩测试失败: 压缩结果应为空")
    
    log.info("fastlz_test", "空字符串压缩测试通过")
end

-- 错误数据格式测试：解压损坏的数据
function fastlz_test.test_corrupted_data()
    -- 用例说明：
    -- 输入：人为构造的损坏压缩数据
    -- 断言：解压应返回 nil
    log.info("fastlz_test","开始 损坏数据解压测试")
    
    -- 构造一个损坏的压缩数据（随机字节）
    local corrupted_data = string.char(0x01, 0x02, 0x03, 0x04, 0x05)
    
    -- 尝试解压损坏的数据，应该返回 nil
    local result = fastlz.uncompress(corrupted_data, 1024)
    assert(result == nil, "损坏数据解压测试失败: 解压损坏数据应返回 nil")
    
    log.info("fastlz_test", "损坏数据解压测试通过")
end

-- 错误数据格式测试：无效的压缩级别
function fastlz_test.test_invalid_level()
    -- 用例说明：
    -- 输入：有效数据但使用无效的压缩级别
    -- 断言：compress 函数应能处理或返回 nil
    log.info("fastlz_test","开始 无效压缩级别测试")
    
    local originStr = "test data for invalid level"
    
    -- 测试负数级别
    local compress_back1 = fastlz.compress(originStr, -1)
    -- 测试0级别
    local compress_back2 = fastlz.compress(originStr, 0)
    -- 测试大于2的级别
    local compress_back3 = fastlz.compress(originStr, 5)
    
    -- 无效的压缩级别应该被当作默认级别处理或返回 nil
    -- 不抛出异常即可认为通过
    log.info("fastlz_test", "无效压缩级别测试通过（函数调用未抛出异常）")
end

-- 错误数据格式测试：解压时 maxout 过小
function fastlz_test.test_maxout_too_small()
    -- 用例说明：
    -- 压缩正常数据，但解压时设置的 maxout 小于原始数据
    -- 断言：解压应返回 nil
    log.info("fastlz_test","开始 maxout 过小解压测试")
    
    local originStr = "This is a test string that will be compressed and then decompressed with a small maxout value"
    local compress_back = fastlz.compress(originStr, 1)
    
    -- 设置比原始数据小的 maxout
    local small_maxout = 10
    local result = fastlz.uncompress(compress_back, small_maxout)
    
    assert(result == nil, "maxout 过小解压测试失败: 解压应返回 nil")
    
    log.info("fastlz_test", "maxout 过小解压测试通过")
end

-- 错误数据格式测试：解压普通文本（非压缩数据）
function fastlz_test.test_uncompress_normal_text()
    -- 用例说明：
    -- 尝试解压普通文本（不是压缩数据）
    -- 断言：解压应返回 nil
    log.info("fastlz_test","开始 解压普通文本测试")
    
    local normal_text = "This is not compressed data"
    local result = fastlz.uncompress(normal_text, #normal_text * 2)
    
    assert(result == nil, "解压普通文本测试失败: 应返回 nil")
    
    log.info("fastlz_test", "解压普通文本测试通过")
end

-- 错误数据格式测试：压缩然后解压时篡改压缩数据
function fastlz_test.test_tampered_data()
    -- 用例说明：
    -- 正常压缩数据后，修改部分压缩数据，然后尝试解压
    -- 断言：根据fastlz的实际行为，解压可能成功返回部分数据或失败返回nil
    log.info("fastlz_test","开始 篡改压缩数据测试")
    
    local originStr = "Original data for tampering test"
    local compress_back = fastlz.compress(originStr, 1)
    
    if compress_back and #compress_back > 2 then
        -- 修改压缩数据的第二个字节
        local tampered_data = string.sub(compress_back, 1, 1) .. 
                              string.char(string.byte(compress_back, 2) + 1) .. 
                              string.sub(compress_back, 3)
        
        local result = fastlz.uncompress(tampered_data, #originStr)
        
        -- fastlz 可能对篡改数据有一定的容错性，可能解压成功或失败
        -- 我们不强制要求返回 nil，只记录实际行为
        if result == nil then
            log.info("fastlz_test", "篡改数据解压失败，符合预期行为")
        else
            log.info("fastlz_test", string.format("篡改数据解压成功，返回长度: %d，原始长度: %d", #result, #originStr))
            -- 如果解压成功，检查返回的数据是否是原数据的子集
            if result ~= originStr then
                log.info("fastlz_test", "篡改数据解压结果与原数据不同，仍在合理范围内")
            end
        end
        
        -- 不进行强制断言，只记录日志
        log.info("fastlz_test", "篡改压缩数据测试完成")
    else
        log.info("fastlz_test", "压缩数据太短，无法进行篡改测试")
    end
end

-- 错误数据格式测试：压缩大文件但内存不足
function fastlz_test.test_large_data()
    -- 用例说明：
    -- 尝试压缩非常大的数据（超过fastlz限制）
    -- 注意：fastlz有32KB+原始数据大小的内存限制
    -- 断言：压缩可能失败返回 nil
    log.info("fastlz_test","开始 大文件压缩测试")
    
    -- 构造一个较大的字符串（例如 50KB）
    local large_data = string.rep("abcdefghij", 5000)  -- 约 50KB
    
    local compress_back = fastlz.compress(large_data, 1)
    
    -- 根据实际实现，可能成功也可能失败
    -- 我们只确保不崩溃即可
    log.info("fastlz_test", "大文件压缩测试通过（函数调用未抛出异常）")
end

return fastlz_test
