fs_context = {}

function fs_context.test_fsstat_default_path()
    log.info("fs_context", "开始 fs.fsstat 默认路径测试")
    local success, total_blocks, used_blocks, block_size, fs_type = fs.fsstat()
    assert(success == true, "默认路径获取文件系统状态应该成功")
    assert(type(total_blocks) == "number", "总块数应为number类型")
    assert(type(used_blocks) == "number", "已用块数应为number类型")
    assert(type(block_size) == "number", "块大小应为number类型")
    assert(type(fs_type) == "string", "文件系统类型应为string类型")
    assert(total_blocks >= 0, "总块数应大于等于0")
    assert(used_blocks >= 0, "已用块数应大于等于0")
    assert(block_size >= 0, "块大小应大于等于0")
    log.info("fs_context", "fs.fsstat 默认路径测试通过",
        "总空间=" .. total_blocks .. "块",
        "已用=" .. used_blocks .. "块",
        "块大小=" .. block_size .. "字节",
        "类型=" .. fs_type)
end

function fs_context.test_fsstat_root_path()
    log.info("fs_context", "开始 fs.fsstat 根目录路径测试")
    local success, total_blocks, used_blocks, block_size, fs_type = fs.fsstat("/")
    assert(success == true, "根目录路径获取文件系统状态应该成功")
    assert(type(total_blocks) == "number", "总块数应为number类型")
    assert(type(used_blocks) == "number", "已用块数应为number类型")
    assert(type(block_size) == "number", "块大小应为number类型")
    assert(type(fs_type) == "string", "文件系统类型应为string类型")
    log.info("fs_context", "fs.fsstat 根目录路径测试通过")
end

function fs_context.test_fsstat_valid_path()
    log.info("fs_context", "开始 fs.fsstat 有效路径测试")
    local success, total_blocks, used_blocks, block_size, fs_type = fs.fsstat("/sd")
    if success then
        assert(type(total_blocks) == "number", "总块数应为number类型")
        assert(type(used_blocks) == "number", "已用块数应为number类型")
        assert(type(block_size) == "number", "块大小应为number类型")
        assert(type(fs_type) == "string", "文件系统类型应为string类型")
        log.info("fs_context", "fs.fsstat /sd 路径测试通过",
            "总空间=" .. total_blocks .. "块",
            "已用=" .. used_blocks .. "块",
            "块大小=" .. block_size .. "字节",
            "类型=" .. fs_type)
    else
        log.info("fs_context", "fs.fsstat /sd 路径失败(SD卡可能不存在)", total_blocks)
    end
end

function fs_context.test_fsstat_nil_path()
    log.info("fs_context", "开始 fs.fsstat nil路径测试")
    local success, total_blocks, used_blocks, block_size, fs_type = pcall(fs.fsstat, nil)
    if success then
        assert(total_blocks ~= nil, "nil路径应该自动调整为可查的文件系统分区根目录")
    else
        log.info("fs_context", "fs.fsstat nil路径抛出类型错误(预期行为)")
    end
    log.info("fs_context", "fs.fsstat nil路径测试通过")
end

function fs_context.test_fsstat_number_path()
    log.info("fs_context", "开始 fs.fsstat 数字路径测试")
    local success, total_blocks, used_blocks, block_size, fs_type = pcall(fs.fsstat, 123)
    if success then
        if total_blocks then
            log.info("fs_context", "fs.fsstat 数字路径返回成功(可能自动转换)", fs_type)
        else
            log.info("fs_context", "fs.fsstat 数字路径返回失败(数字路径被拒绝)")
        end
    else
        log.info("fs_context", "fs.fsstat 数字路径抛出类型错误(预期行为)")
    end
    log.info("fs_context", "fs.fsstat 数字路径测试通过")
end

function fs_context.test_fsstat_empty_string_path()
    log.info("fs_context", "开始 fs.fsstat 空字符串路径测试")
    local success, total_blocks, used_blocks, block_size, fs_type = pcall(fs.fsstat, "")
    if success then
        if total_blocks then
            log.info("fs_context", "fs.fsstat 空字符串路径返回成功(可能自动调整)", fs_type)
        else
            log.info("fs_context", "fs.fsstat 空字符串路径返回失败(返回失败)")
        end
    else
        log.info("fs_context", "fs.fsstat 空字符串路径抛出类型错误(预期行为)")
    end
    log.info("fs_context", "fs.fsstat 空字符串路径测试通过")
end

function fs_context.test_fsstat_boolean_path()
    log.info("fs_context", "开始 fs.fsstat 布尔值路径测试")
    local success, total_blocks, used_blocks, block_size, fs_type = pcall(fs.fsstat, true)
    if success then
        if total_blocks == false then
            log.info("fs_context", "fs.fsstat 布尔值路径测试通过(布尔值被拒绝)")
        else
            log.info("fs_context", "fs.fsstat 布尔值路径返回成功")
        end
    else
        log.info("fs_context", "fs.fsstat 布尔值路径抛出类型错误(预期行为)")
    end
    log.info("fs_context", "fs.fsstat 布尔值路径测试通过")
end

function fs_context.test_fsstat_table_path()
    log.info("fs_context", "开始 fs.fsstat table路径测试")
    local success, total_blocks, used_blocks, block_size, fs_type = pcall(fs.fsstat, {})
    if success then
        if total_blocks == false then
            log.info("fs_context", "fs.fsstat table路径测试通过(table被拒绝)")
        else
            log.info("fs_context", "fs.fsstat table路径返回成功")
        end
    else
        log.info("fs_context", "fs.fsstat table路径抛出类型错误(预期行为)")
    end
    log.info("fs_context", "fs.fsstat table路径测试通过")
end

function fs_context.test_fsstat_function_path()
    log.info("fs_context", "开始 fs.fsstat 函数路径测试")
    local success, total_blocks, used_blocks, block_size, fs_type = pcall(fs.fsstat, function() end)
    if success then
        if total_blocks == false then
            log.info("fs_context", "fs.fsstat 函数路径测试通过(函数被拒绝)")
        else
            log.info("fs_context", "fs.fsstat 函数路径返回成功")
        end
    else
        log.info("fs_context", "fs.fsstat 函数路径抛出类型错误(预期行为)")
    end
    log.info("fs_context", "fs.fsstat 函数路径测试通过")
end

function fs_context.test_fsstat_nonexistent_path()
    log.info("fs_context", "开始 fs.fsstat 不存在路径测试")
    local success, total_blocks, used_blocks, block_size, fs_type = pcall(fs.fsstat, "/nonexistent_path_12345")
    if success then
        if total_blocks then
            log.info("fs_context", "fs.fsstat 不存在路径返回成功(自动调整为可查的分区)", fs_type)
        else
            log.info("fs_context", "fs.fsstat 不存在路径测试通过(返回失败)")
        end
    else
        log.info("fs_context", "fs.fsstat 不存在路径抛出类型错误(预期行为)")
    end
    log.info("fs_context", "fs.fsstat 不存在路径测试通过")
end

function fs_context.test_fsize_existing_file()
    log.info("fs_context", "开始 fs.fsize 已存在文件测试")
    local test_file = "/test_fs_fsize.txt"
    local f = io.open(test_file, "w")
    assert(f, "创建测试文件失败")
    f:write("Hello LuatOS!")
    f:close()

    local size = fs.fsize(test_file)
    assert(size and size > 0, "已存在文件应该返回正确大小")
    assert(size == 13, "文件内容'Hello LuatOS!'应为13字节，实际:" .. tostring(size))
    log.info("fs_context", "fs.fsize 已存在文件测试通过", "文件大小=" .. size .. "字节")

    os.remove(test_file)
end

function fs_context.test_fsize_empty_file()
    log.info("fs_context", "开始 fs.fsize 空文件测试")
    local test_file = "/test_fs_empty.txt"
    local f = io.open(test_file, "w")
    assert(f, "创建空测试文件失败")
    f:close()

    local size = fs.fsize(test_file)
    assert(size ~= nil, "空文件应返回非nil值")
    log.info("fs_context", "fs.fsize 空文件测试通过", "文件大小=" .. tostring(size) .. "字节")

    os.remove(test_file)
end

function fs_context.test_fsize_nonexistent_file()
    log.info("fs_context", "开始 fs.fsize 不存在文件测试")
    local size = fs.fsize("/nonexistent_file_12345.txt")
    assert(size == 0, "不存在文件应返回0，实际:" .. tostring(size))
    log.info("fs_context", "fs.fsize 不存在文件测试通过")
end

function fs_context.test_fsize_nil_path()
    log.info("fs_context", "开始 fs.fsize nil路径测试")
    local success, size = pcall(fs.fsize, nil)
    if success then
        assert(size == 0, "nil路径应返回0，实际:" .. tostring(size))
    else
        log.info("fs_context", "fs.fsize nil路径抛出类型错误(预期行为)")
    end
    log.info("fs_context", "fs.fsize nil路径测试通过")
end

function fs_context.test_fsize_number_path()
    log.info("fs_context", "开始 fs.fsize 数字路径测试")
    local success, size = pcall(fs.fsize, 123)
    if success then
        assert(size == 0, "数字路径应返回0，实际:" .. tostring(size))
    else
        log.info("fs_context", "fs.fsize 数字路径抛出类型错误(预期行为)")
    end
    log.info("fs_context", "fs.fsize 数字路径测试通过")
end

function fs_context.test_fsize_empty_string_path()
    log.info("fs_context", "开始 fs.fsize 空字符串路径测试")
    local success, size = pcall(fs.fsize, "")
    if success then
        assert(size == 0, "空字符串路径应返回0，实际:" .. tostring(size))
    else
        log.info("fs_context", "fs.fsize 空字符串路径抛出类型错误(预期行为)")
    end
    log.info("fs_context", "fs.fsize 空字符串路径测试通过")
end

function fs_context.test_fsize_boolean_path()
    log.info("fs_context", "开始 fs.fsize 布尔值路径测试")
    local success, size = pcall(fs.fsize, true)
    if success then
        assert(size == 0, "布尔值路径应返回0，实际:" .. tostring(size))
    else
        log.info("fs_context", "fs.fsize 布尔值路径抛出类型错误(预期行为)")
    end
    log.info("fs_context", "fs.fsize 布尔值路径测试通过")
end

function fs_context.test_fsize_table_path()
    log.info("fs_context", "开始 fs.fsize table路径测试")
    local success, size = pcall(fs.fsize, {})
    if success then
        assert(size == 0, "table路径应返回0，实际:" .. tostring(size))
    else
        log.info("fs_context", "fs.fsize table路径抛出类型错误(预期行为)")
    end
    log.info("fs_context", "fs.fsize table路径测试通过")
end

function fs_context.test_fsize_function_path()
    log.info("fs_context", "开始 fs.fsize 函数路径测试")
    local success, size = pcall(fs.fsize, function() end)
    if success then
        assert(size == 0, "函数路径应返回0，实际:" .. tostring(size))
    else
        log.info("fs_context", "fs.fsize 函数路径抛出类型错误(预期行为)")
    end
    log.info("fs_context", "fs.fsize 函数路径测试通过")
end

function fs_context.test_fsize_root_path()
    log.info("fs_context", "开始 fs.fsize 根目录路径测试")
    local size = fs.fsize("/")
    assert(size == 0, "根目录路径应返回0，实际:" .. tostring(size))
    log.info("fs_context", "fs.fsize 根目录路径测试通过")
end

function fs_context.test_fsize_directory_path()
    log.info("fs_context", "开始 fs.fsize 目录路径测试")
    local test_dir = "/test_fs_dir"
    io.mkdir(test_dir)
    local size = fs.fsize(test_dir)
    log.info("fs_context", "fs.fsize 目录路径测试", "返回值=" .. tostring(size))
    os.remove(test_dir)
end

function fs_context.test_combined_fsstat_and_fsize()
    log.info("fs_context", "开始 fs.fsstat 和 fs.fsize 联合测试")
    local test_file = "/test_combined.txt"

    local success, total_blocks, used_blocks, block_size, fs_type = fs.fsstat()
    assert(success == true, "获取文件系统状态失败")

    local f = io.open(test_file, "w")
    assert(f, "创建测试文件失败")
    local test_content = "Combined test content"
    f:write(test_content)
    f:close()

    local file_size = fs.fsize(test_file)
    assert(file_size == #test_content, "文件大小不匹配，预期:" .. #test_content .. " 实际:" .. file_size)

    log.info("fs_context", "fs.fsstat 和 fs.fsize 联合测试通过",
        "文件系统总空间=" .. (total_blocks * block_size) .. "字节",
        "文件大小=" .. file_size .. "字节")

    os.remove(test_file)
end

function fs_context.test_return_value_types()
    log.info("fs_context", "开始 fs 返回值类型测试")
    local success, total_blocks, used_blocks, block_size, fs_type = fs.fsstat("/")
    assert(success ~= nil, "fsstat success不应为nil")
    assert(type(success) == "boolean", "fsstat success应为boolean类型")

    local size = fs.fsize("/test_nonexistent.txt")
    assert(size ~= nil, "fsize返回值不应为nil")
    assert(type(size) == "number", "fsize返回值应为number类型")

    log.info("fs_context", "fs 返回值类型测试通过")
end

function fs_context.cleanup()
    log.info("fs_context", "开始清理测试文件")
    os.remove("/test_fs_fsize.txt")
    os.remove("/test_fs_empty.txt")
    os.remove("/test_combined.txt")
    log.info("fs_context", "清理测试文件完成")
end

return fs_context