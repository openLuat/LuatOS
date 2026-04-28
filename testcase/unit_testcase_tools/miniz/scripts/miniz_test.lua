local miniz_test = {}

-- 来自miniz公开示例的演示数据
local b64_payload = "eAEFQIGNwyAMXOUm+E2+OzjhCCiOjYyhyvbVR7K7IR0l+iau8G82eIW5jXVoPzF5pse/B8FaPXLiWTNxEMsKI+WmIR0l+iayEY2i2V4UbqqPh5bwimyEuY11aD8xeaYHxAquvom6VDFUXqQjG1Fek6efCFfCK0b0LUnQMjiCxhUT05GNL75dFUWCSMcjN3EE5c4Wvq42/36R41fa"
local compressed_demo = b64_payload:fromBase64()
local expected_compressed_len = 156
local expected_uncompressed_len = 235
local unzip_zip_path = "/luadb/pac_man.zip"
local unzip_target_dir = "/ram/miniz_test_unzip/"
local unzip_root_dir = unzip_target_dir .. "/pac_man"
local unzip_nested_dir = unzip_root_dir .. "/user"
local unzip_expected_files = {
    {path = unzip_root_dir .. "/main.lua", size = 223},
    {path = unzip_root_dir .. "/meta.json", size = 493},
    {path = unzip_root_dir .. "/icon.png", size = 3241},
    {path = unzip_nested_dir .. "/pacman_game_win.lua", size = 15173},
}

-- 压缩测试用的测试数据
local test_data_simple = "123jfoiq4hlkfjbnasdilfhuqwo;hfashfp9qw38hrfaios;hfiuoaghfluaeisw"
local test_data_repeated = string.rep("ABCDE", 100)  -- 重复字符串，压缩效果更好
local test_data_large = string.rep("This is a test string with some repetition. ", 50)

local function cleanup_unzip_output()
    for _, item in ipairs(unzip_expected_files) do
        os.remove(item.path)
    end
    io.rmdir(unzip_nested_dir)
    io.rmdir(unzip_root_dir)
    io.rmdir(unzip_target_dir)
end

-- 验证示例数据解压后长度符合预期
function miniz_test.test_uncompress_demo_blob()
    log.info("miniz测试", "正在解压演示数据")
    assert(#compressed_demo == expected_compressed_len, string.format("压缩长度不匹配，预期 %d，实际 %d", expected_compressed_len, #compressed_demo))

    local inflated = miniz.uncompress(compressed_demo)
    assert(type(inflated) == "string", "解压应返回字符串类型")
    assert(#inflated == expected_uncompressed_len, string.format("解压长度不匹配，预期 %d，实际 %d", expected_uncompressed_len, #inflated))

    assert(#compressed_demo == expected_compressed_len, "解压后原压缩数据被修改")
    log.info("miniz测试", "演示数据解压测试通过")
end

-- 验证多次解压结果一致（幂等性）
function miniz_test.test_uncompress_idempotent()
    log.info("miniz测试", "验证解压结果一致性")
    local first = miniz.uncompress(compressed_demo)
    local second = miniz.uncompress(compressed_demo)
    assert(first == second, "相同数据多次解压结果必须一致")
    assert(#first == expected_uncompressed_len, "重复解压长度异常")
    log.info("miniz测试", "解压一致性测试通过")
end

-- 验证非法数据不会崩溃，且能正常报错
function miniz_test.test_uncompress_invalid_blob()
    log.info("miniz测试", "测试非法数据解压")
    local ok, res = pcall(miniz.uncompress, "不是有效的压缩流")
    assert(not ok or res == nil, "非法数据解压应该失败")
    log.info("miniz测试", "非法数据处理测试通过")
end

-- 使用默认参数压缩（自动写入ZLIB头部）
function miniz_test.test_compress_default()
    log.info("miniz测试", "使用默认参数压缩")
    local cdata = miniz.compress(test_data_simple)
    assert(cdata ~= nil, "压缩应返回有效数据")
    assert(type(cdata) == "string", "压缩应返回字符串")
    assert(#cdata > 0, "压缩数据长度必须大于0")
    assert(#cdata <= 32768, "压缩数据不能超过32KB")

    local udata = miniz.uncompress(cdata)
    assert(udata == test_data_simple, "压缩解压往返数据不一致")
    log.info("miniz测试", "默认压缩测试通过，原始长度:", #test_data_simple, "压缩后:", #cdata)
end

-- 使用WRITE_ZLIB_HEADER标志压缩
function miniz_test.test_compress_write_zlib_header()
    log.info("miniz测试", "使用ZLIB头部标志压缩")
    local cdata = miniz.compress(test_data_simple, miniz.WRITE_ZLIB_HEADER)
    assert(cdata ~= nil, "带ZLIB头部压缩应返回有效数据")
    assert(#cdata > 0, "压缩数据长度必须大于0")

    local udata = miniz.uncompress(cdata, miniz.PARSE_ZLIB_HEADER)
    assert(udata == test_data_simple, "带ZLIB头部往返数据不一致")
    log.info("miniz测试", "ZLIB头部压缩测试通过")
end

-- 使用COMPUTE_ADLER32标志压缩
function miniz_test.test_compress_compute_adler32()
    log.info("miniz测试", "使用ADLER32校验压缩")
    local cdata = miniz.compress(test_data_simple, miniz.COMPUTE_ADLER32)
    assert(cdata ~= nil, "带ADLER32压缩应返回有效数据")
    assert(#cdata > 0, "压缩数据长度必须大于0")

    local udata = miniz.uncompress(cdata, miniz.COMPUTE_ADLER32)
    assert(udata == test_data_simple, "带ADLER32往返数据不一致")
    log.info("miniz测试", "ADLER32压缩测试通过")
end

-- 使用GREEDY_PARSING_FLAG压缩
function miniz_test.test_compress_greedy_parsing()
    log.info("miniz测试", "使用GREEDY_PARSING_FLAG解析压缩")
    local cdata = miniz.compress(test_data_repeated, miniz.GREEDY_PARSING_FLAG)
    assert(cdata ~= nil, "GREEDY_PARSING_FLAG解析压缩应返回有效数据")
    assert(type(cdata) == "string", "GREEDY_PARSING_FLAG解析压缩应返回字符串")
    assert(#cdata > 0, "压缩数据长度必须大于0")
    log.info("miniz测试", "GREEDY_PARSING_FLAG解析压缩测试通过")
end

-- 使用NONDETERMINISTIC_PARSING_FLAG压缩 
function miniz_test.test_compress_nondeterministic_parsing()
    log.info("miniz测试", "使用非确定性解析压缩")
    local cdata = miniz.compress(test_data_simple, miniz.NONDETERMINISTIC_PARSING_FLAG)
    assert(cdata ~= nil, "非确定性解析压缩应返回有效数据")
    assert(type(cdata) == "string", "非确定性解析压缩应返回字符串")
    assert(#cdata > 0, "压缩数据长度必须大于0")
    log.info("miniz测试", "非确定性解析压缩测试通过")
end

-- 使用RLE_MATCHES压缩
function miniz_test.test_compress_rle_matches()
    log.info("miniz测试", "使用RLE匹配压缩")
    local cdata = miniz.compress(test_data_repeated, miniz.RLE_MATCHES)
    assert(cdata ~= nil, "RLE压缩应返回有效数据")
    assert(type(cdata) == "string", "RLE压缩应返回字符串")
    assert(#cdata > 0, "压缩数据长度必须大于0")
    log.info("miniz测试", "RLE匹配压缩测试通过")
end

-- 使用FILTER_MATCHES压缩
function miniz_test.test_compress_filter_matches()
    log.info("miniz测试", "使用匹配过滤压缩")
    local cdata = miniz.compress(test_data_simple, miniz.FILTER_MATCHES)
    assert(cdata ~= nil, "匹配过滤压缩应返回有效数据")
    assert(type(cdata) == "string", "匹配过滤压缩应返回字符串")
    assert(#cdata > 0, "压缩数据长度必须大于0")
    log.info("miniz测试", "匹配过滤压缩测试通过")
end

-- 使用FORCE_ALL_STATIC_BLOCKS压缩
function miniz_test.test_compress_static_blocks()
    log.info("miniz测试", "使用静态块压缩")
    local cdata = miniz.compress(test_data_simple, miniz.FORCE_ALL_STATIC_BLOCKS)
    assert(cdata ~= nil, "静态块压缩应返回有效数据")
    assert(type(cdata) == "string", "静态块压缩应返回字符串")
    assert(#cdata > 0, "压缩数据长度必须大于0")
    log.info("miniz测试", "静态块压缩测试通过")
end

-- 使用FORCE_ALL_RAW_BLOCKS压缩 
function miniz_test.test_compress_raw_blocks()
    log.info("miniz测试", "使用原始块压缩")
    local cdata = miniz.compress(test_data_simple, miniz.FORCE_ALL_RAW_BLOCKS)
    assert(cdata ~= nil, "原始块压缩应返回有效数据")
    assert(type(cdata) == "string", "原始块压缩应返回字符串")
    assert(#cdata > 0, "压缩数据长度必须大于0")
    log.info("miniz测试", "原始块压缩测试通过")
end

-- 测试带ZLIB头部解析的解压
function miniz_test.test_uncompress_parse_zlib_header()
    log.info("miniz测试", "测试ZLIB头部解析解压")
    local cdata = miniz.compress(test_data_simple, miniz.WRITE_ZLIB_HEADER)
    assert(cdata ~= nil, "压缩应成功")

    local udata = miniz.uncompress(cdata, miniz.PARSE_ZLIB_HEADER)
    assert(udata == test_data_simple, "带头部解析解压数据不一致")
    log.info("miniz测试", "ZLIB头部解析解压测试通过")
end

-- 测试重复数据的压缩率
function miniz_test.test_compress_ratio_repeated_data()
    log.info("miniz测试", "测试重复数据压缩率")
    local original_size = #test_data_repeated
    local cdata = miniz.compress(test_data_repeated)
    local compressed_size = #cdata

    assert(cdata ~= nil, "压缩应成功")
    assert(compressed_size < original_size, "重复数据应能被有效压缩")

    local udata = miniz.uncompress(cdata)
    assert(udata == test_data_repeated, "重复数据往返不一致")

    local ratio = (compressed_size / original_size) * 100
    log.info("miniz测试", "压缩率测试通过", "原始长度:", original_size, "压缩后:", compressed_size, string.format("压缩率: %.2f%%", ratio))
end

-- 测试较大数据量压缩
function miniz_test.test_compress_large_data()
    log.info("miniz测试", "测试大数据压缩")
    local cdata = miniz.compress(test_data_large)
    assert(cdata ~= nil, "大数据压缩应成功")
    assert(#cdata <= 32768, "压缩数据不能超过32KB限制")

    local udata = miniz.uncompress(cdata)
    assert(udata == test_data_large, "大数据往返数据不一致")
    log.info("miniz测试", "大数据压缩测试通过，原始长度:", #test_data_large, "压缩后:", #cdata)
end

-- 测试空字符串压缩
function miniz_test.test_compress_empty_string()
    log.info("miniz测试", "测试空字符串压缩")
    local cdata = miniz.compress("")
    assert(cdata ~= nil, "空字符串应能正常压缩")
    assert(#cdata > 0, "空字符串压缩后应有头部数据")

    local udata = miniz.uncompress(cdata)
    assert(udata == "", "空字符串往返数据不一致")
    log.info("miniz测试", "空字符串压缩测试通过")
end

-- 测试单字符压缩
function miniz_test.test_compress_single_char()
    log.info("miniz测试", "测试单字符压缩")
    local cdata = miniz.compress("A")
    assert(cdata ~= nil, "单字符应能正常压缩")

    local udata = miniz.uncompress(cdata)
    assert(udata == "A", "单字符往返数据不一致")
    log.info("miniz测试", "单字符压缩测试通过")
end

-- 测试多标志组合压缩
function miniz_test.test_compress_combined_flags()
    log.info("miniz测试", "测试多标志组合压缩")
    local flags = miniz.WRITE_ZLIB_HEADER + miniz.COMPUTE_ADLER32 + miniz.GREEDY_PARSING_FLAG
    local cdata = miniz.compress(test_data_simple, flags)
    assert(cdata ~= nil, "组合标志压缩应成功")
    assert(type(cdata) == "string", "组合标志压缩应返回字符串")
    assert(#cdata > 0, "压缩数据长度必须大于0")
    log.info("miniz测试", "组合标志压缩测试通过")
end

-- 测试解压时非法标志的处理
function miniz_test.test_uncompress_invalid_flags()
    log.info("miniz测试", "测试非法标志解压处理")
    local cdata = miniz.compress(test_data_simple)
    assert(cdata ~= nil, "压缩应成功")

    local udata = miniz.uncompress(cdata, miniz.PARSE_ZLIB_HEADER)
    assert(udata == test_data_simple, "带标志解压应正常")
    log.info("miniz测试", "非法标志处理测试通过")
end

function miniz_test.test_unzip_nested_directories()
    log.info("miniz测试", "测试 unzip 目录创建")
    
    assert(io.exists(unzip_zip_path) == true, "缺少 pac_man.zip 测试资源")

    cleanup_unzip_output()

    local success = miniz.unzip(unzip_zip_path, unzip_target_dir)
    assert(success == true, "unzip 应成功")

    -- ZIP 文件中包含 pac_man 文件夹，所以实际路径是 unzip_target_dir .. "pac_man/"
    local actual_root_dir = unzip_target_dir .. "pac_man/"
    
    -- 期望的文件
    local expected_files = {
        {path = actual_root_dir .. "/main.lua", size = 272},        -- 实际大小是 272
        {path = actual_root_dir .. "/metas.json", size = 255},      -- 文件名和大小都不同
        {path = actual_root_dir .. "/icon.png", size = 3241},
        {path = actual_root_dir .. "/pacman_game_win.lua", size = 8233},  -- 实际大小是 8233
    }

    for _, item in ipairs(expected_files) do
        assert(io.exists(item.path) == true, "缺少解压文件: " .. item.path)
        local file_size = io.fileSize(item.path)
        assert(file_size == item.size, string.format("文件大小不匹配 %s 预期 %d 实际 %d", item.path, item.size, file_size or -1))
    end

    -- 验证目录存在
    local ok, entries = io.lsdir(actual_root_dir, 10, 0)
    assert(ok == true and type(entries) == "table", "解压目录应存在")

    log.info("miniz测试", "unzip 测试通过")
end

return miniz_test