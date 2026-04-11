local ramfs_tests = {}

local function cleanup_ram_paths(files, dirs)
    if files then
        for _, file in ipairs(files) do
            os.remove(file)
        end
    end
    if dirs then
        for i = #dirs, 1, -1 do
            io.rmdir(dirs[i])
        end
    end
end


function ramfs_tests.test_ioRamNestedDirectoryOps()
    local baseDir = "/ram/os_nested_dir"
    local childDir = baseDir .. "/inner"
    local filePath = childDir .. "/payload.txt"

    cleanup_ram_paths({filePath}, {childDir, baseDir})

    local success, err = io.mkdir(baseDir)
    assert(success == true and err == 0, string.format("创建 /ram 一级目录失败: %s %s", success, err))

    success, err = io.mkdir(childDir)
    assert(success == true and err == 0, string.format("创建 /ram 二级目录失败: %s %s", success, err))

    assert(io.writeFile(filePath, "ramfs nested file") == true, "在嵌套目录中创建文件失败")

    local ok, entries = io.lsdir(baseDir, 10, 0)
    assert(ok == true and #entries == 1, string.format("一级目录 lsdir 结果异常, 条目数=%s", ok and #entries or -1))
    assert(entries[1].type == 1 and entries[1].name == "inner", "一级目录应只看到子目录 inner")

    ok, entries = io.lsdir(childDir, 10, 0)
    assert(ok == true and #entries == 1, string.format("二级目录 lsdir 结果异常, 条目数=%s", ok and #entries or -1))
    assert(entries[1].type == 0 and entries[1].name == "payload.txt", "二级目录应只看到 payload.txt 文件")

    success, err = io.rmdir(baseDir)
    assert(success ~= true and err ~= 0, "非空目录不应允许直接删除")

    local removed, remove_err = os.remove(filePath)
    assert(removed == true and remove_err == nil, string.format("删除嵌套文件失败: %s %s", removed, remove_err))

    success, err = io.rmdir(childDir)
    assert(success == true and err == 0, string.format("删除二级目录失败: %s %s", success, err))

    success, err = io.rmdir(baseDir)
    assert(success == true and err == 0, string.format("删除一级目录失败: %s %s", success, err))
end

function ramfs_tests.test_ioRamRecursiveMkdirAndDirRename()
    local baseDir = "/ram/os_recursive_dir"
    local nestedDir = baseDir .. "/level1/level2"
    local sourceFile = nestedDir .. "/payload.txt"
    local renamedDir = "/ram/os_recursive_dir_renamed"
    local renamedNestedDir = renamedDir .. "/level1/level2"
    local renamedFile = renamedNestedDir .. "/payload.txt"

    cleanup_ram_paths(
        {sourceFile, renamedFile},
        {nestedDir, baseDir .. "/level1", baseDir, renamedNestedDir, renamedDir .. "/level1", renamedDir}
    )

    local success, err = io.mkdir(nestedDir)
    assert(success == true and err == 0, string.format("递归创建 /ram 目录失败: %s %s", success, err))

    local ok, entries = io.lsdir(baseDir, 10, 0)
    assert(ok == true and #entries == 1, string.format("递归 mkdir 后一级目录 lsdir 异常, 条目数=%s", ok and #entries or -1))
    assert(entries[1].type == 1 and entries[1].name == "level1", "递归 mkdir 后一级目录应只看到 level1")

    assert(io.writeFile(sourceFile, "ramfs rename tree") == true, "在递归创建目录中写文件失败")

    success, err = os.rename(baseDir, renamedDir)
    assert(success == true and err == nil, string.format("重命名 /ram 目录失败: %s %s", success, err))

    assert(io.exists(sourceFile) ~= true, "目录重命名后旧路径文件不应继续存在")
    assert(io.exists(renamedFile) == true, "目录重命名后新路径文件应存在")

    ok, entries = io.lsdir(renamedDir, 10, 0)
    assert(ok == true and #entries == 1, string.format("重命名后目录 lsdir 异常, 条目数=%s", ok and #entries or -1))
    assert(entries[1].type == 1 and entries[1].name == "level1", "重命名后一级目录应只看到 level1")

    local file = io.open(renamedFile, "r")
    assert(file ~= nil, "重命名后的文件应可打开")
    local content = file:read("*a")
    file:close()
    assert(content == "ramfs rename tree", string.format("重命名后的文件内容异常: %s", content))

    cleanup_ram_paths(
        {renamedFile},
        {renamedNestedDir, renamedDir .. "/level1", renamedDir}
    )
end

function ramfs_tests.test_ioRamRenameOverwriteTarget()
    local baseDir = "/ram/os_rename_overwrite"
    local sourceFile = baseDir .. "/from.txt"
    local targetFile = baseDir .. "/to.txt"

    cleanup_ram_paths({sourceFile, targetFile}, {baseDir})

    local success, err = io.mkdir(baseDir)
    assert(success == true and err == 0, string.format("创建 /ram rename 覆盖测试目录失败: %s %s", success, err))

    assert(io.writeFile(sourceFile, "from-data") == true, "创建源文件失败")
    assert(io.writeFile(targetFile, "to-data") == true, "创建目标文件失败")

    success, err = os.rename(sourceFile, targetFile)
    assert(success == true and err == nil, string.format("覆盖目标文件的 rename 失败: %s %s", success, err))

    assert(io.exists(sourceFile) ~= true, "覆盖 rename 后旧文件不应存在")
    assert(io.exists(targetFile) == true, "覆盖 rename 后目标文件应存在")

    local file = io.open(targetFile, "r")
    assert(file ~= nil, "覆盖 rename 后目标文件应可打开")
    local content = file:read("*a")
    file:close()
    assert(content == "from-data", string.format("覆盖 rename 后目标内容异常: %s", content))

    cleanup_ram_paths({targetFile}, {baseDir})
end

function ramfs_tests.test_ioRamRenameDirectoryOverwriteEmptyTarget()
    local sourceDir = "/ram/os_dir_replace_src"
    local sourceNestedDir = sourceDir .. "/inner"
    local sourceFile = sourceNestedDir .. "/payload.txt"
    local targetDir = "/ram/os_dir_replace_dst"
    local targetNestedDir = targetDir .. "/inner"
    local targetFile = targetNestedDir .. "/payload.txt"

    cleanup_ram_paths(
        {sourceFile, targetFile},
        {sourceNestedDir, sourceDir, targetNestedDir, targetDir}
    )

    local success, err = io.mkdir(sourceNestedDir)
    assert(success == true and err == 0, string.format("创建源目录树失败: %s %s", success, err))

    success, err = io.mkdir(targetDir)
    assert(success == true and err == 0, string.format("创建目标空目录失败: %s %s", success, err))

    assert(io.writeFile(sourceFile, "dir-overwrite") == true, "创建目录覆盖测试文件失败")

    success, err = os.rename(sourceDir, targetDir)
    assert(success == true and err == nil, string.format("目录覆盖空目录 rename 失败: %s %s", success, err))

    assert(io.exists(sourceFile) ~= true, "目录覆盖后旧路径文件不应存在")
    assert(io.exists(targetFile) == true, "目录覆盖后目标路径文件应存在")

    local file = io.open(targetFile, "r")
    assert(file ~= nil, "目录覆盖后目标文件应可打开")
    local content = file:read("*a")
    file:close()
    assert(content == "dir-overwrite", string.format("目录覆盖后目标内容异常: %s", content))

    cleanup_ram_paths({targetFile}, {targetNestedDir, targetDir})
end


function ramfs_tests.test_ioRamLsdirFileSize()
    local dir = "/ram/lsdir_size_test"
    local file = dir .. "/hello.txt"
    local content = "size check content"

    cleanup_ram_paths({file}, {dir})

    local ok, err = io.mkdir(dir)
    assert(ok == true and err == 0, "创建测试目录失败")
    assert(io.writeFile(file, content) == true, "写入文件失败")

    local found, entries = io.lsdir(dir, 10, 0)
    assert(found == true and #entries == 1, "lsdir 应返回1个条目")
    assert(entries[1].name == "hello.txt", "文件名错误")
    assert(entries[1].type == 0, "应为文件类型")
    assert(entries[1].size == #content,
        string.format("lsdir d_size 应为 %d, 实际为 %d", #content, entries[1].size))

    cleanup_ram_paths({file}, {dir})
end

function ramfs_tests.test_ioRamRemoveOpenFileFails()
    local dir = "/ram/refcount_test"
    local file = dir .. "/open.txt"

    cleanup_ram_paths({file}, {dir})

    local ok, err = io.mkdir(dir)
    assert(ok == true and err == 0, "创建测试目录失败")
    assert(io.writeFile(file, "open file data") == true, "写入文件失败")

    local fd = io.open(file, "r")
    assert(fd ~= nil, "打开文件失败")

    -- 文件打开时不应允许删除
    local removed, remove_err = os.remove(file)
    assert(removed ~= true, "打开中的文件不应被删除，但删除成功了")

    fd:close()

    -- 关闭后应可正常删除
    removed, remove_err = os.remove(file)
    assert(removed == true and remove_err == nil,
        string.format("关闭后删除文件失败: %s %s", removed, remove_err))

    io.rmdir(dir)
end

function ramfs_tests.test_ioRamRenameOpenFileFails()
    local dir = "/ram/rename_refcount_test"
    local src = dir .. "/src.txt"
    local dst = dir .. "/dst.txt"

    cleanup_ram_paths({src, dst}, {dir})

    local ok, err = io.mkdir(dir)
    assert(ok == true and err == 0, "创建测试目录失败")
    assert(io.writeFile(src, "rename test") == true, "写入文件失败")

    local fd = io.open(src, "r")
    assert(fd ~= nil, "打开文件失败")

    -- 文件打开时不应允许重命名
    local renamed, rename_err = os.rename(src, dst)
    assert(renamed ~= true, "打开中的文件不应被重命名，但重命名成功了")

    fd:close()

    -- 关闭后应可正常重命名
    renamed, rename_err = os.rename(src, dst)
    assert(renamed == true and rename_err == nil,
        string.format("关闭后重命名文件失败: %s %s", renamed, rename_err))

    cleanup_ram_paths({dst}, {dir})
end

function ramfs_tests.test_ioRamLongPath()
    -- 路径名支持127字符, 测试接近上限的路径
    local dir = "/ram/longpath_test"
    -- 构造一个长文件名 (100字符)
    local long_name = string.rep("a", 100) .. ".txt"
    local file = dir .. "/" .. long_name

    cleanup_ram_paths({file}, {dir})

    local ok, err = io.mkdir(dir)
    assert(ok == true and err == 0, "创建测试目录失败")

    assert(io.writeFile(file, "long path content") == true,
        string.format("写入长路径文件失败, 路径长=%d", #file))
    assert(io.exists(file) == true, "长路径文件应存在")

    cleanup_ram_paths({file}, {dir})
end


return ramfs_tests
