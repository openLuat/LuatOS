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
 
return fastlz_test
