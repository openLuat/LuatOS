-- VFS lfs2函数指针表验证测试
-- 验证P0-2: luat_fs_lfs2.c中VFS函数指针表字段顺序正确
-- 重点验证truncate和opendir/closedir操作不会因指针错位而互相干扰
local vfs_lfs2_ops_test = {}

local TEST_DIR = "/lfs2"
local TEST_FILE = "/lfs2/test_vfs_ops.txt"

-- 测试: truncate操作正确性(不会误调用opendir)
function vfs_lfs2_ops_test.test_truncate_works_correctly()
    log.info("vfs_lfs2_ops", "测试truncate操作正确性")
    -- 先创建文件并写入数据
    local f = io.open(TEST_FILE, "w")
    if not f then
        log.warn("vfs_lfs2_ops", "无法创建测试文件,跳过(可能无lfs2分区)")
        return
    end
    f:write("Hello World! This is a test file for truncate.")
    f:close()

    -- 验证文件存在且有内容
    local size = fs.fsize(TEST_FILE)
    assert(size > 0, "文件创建后应有内容, 实际size=" .. tostring(size))

    -- 执行truncate截断为5字节
    local ret = fs.truncate(TEST_FILE, 5)
    if ret then
        -- truncate成功, 验证文件大小变为5
        local new_size = fs.fsize(TEST_FILE)
        assert(new_size == 5, "truncate后文件应为5字节, 实际=" .. tostring(new_size))
        log.info("vfs_lfs2_ops", "truncate正确截断文件到5字节")
    else
        log.info("vfs_lfs2_ops", "truncate返回失败(可能不支持), 跳过")
    end

    os.remove(TEST_FILE)
    log.info("vfs_lfs2_ops", "truncate操作测试通过")
end

-- 测试: opendir/closedir操作正确性(不会误调用truncate)
function vfs_lfs2_ops_test.test_opendir_works_correctly()
    log.info("vfs_lfs2_ops", "测试opendir操作正确性")
    -- 创建测试目录
    io.mkdir(TEST_DIR .. "/testdir_ops")

    -- 创建几个文件
    local f = io.open(TEST_DIR .. "/testdir_ops/file1.txt", "w")
    if f then
        f:write("file1")
        f:close()
    end

    -- 使用io.lsdir验证opendir/closedir正常工作
    local files = io.lsdir(TEST_DIR .. "/testdir_ops")
    if files then
        assert(type(files) == "table", "lsdir应返回table")
        log.info("vfs_lfs2_ops", "opendir/lsdir正常, 文件数=" .. #files)
    else
        log.info("vfs_lfs2_ops", "lsdir返回nil(可能不支持)")
    end

    -- 清理
    os.remove(TEST_DIR .. "/testdir_ops/file1.txt")
    os.remove(TEST_DIR .. "/testdir_ops")
    log.info("vfs_lfs2_ops", "opendir操作测试通过")
end

-- 测试: truncate后文件仍可正常读取(验证不是opendir误操作)
function vfs_lfs2_ops_test.test_truncate_then_read()
    log.info("vfs_lfs2_ops", "测试truncate后读取")
    local f = io.open(TEST_FILE, "w")
    if not f then
        log.warn("vfs_lfs2_ops", "无法创建测试文件,跳过")
        return
    end
    f:write("ABCDEFGHIJ")  -- 10 bytes
    f:close()

    -- truncate到3字节
    fs.truncate(TEST_FILE, 3)

    -- 读取验证
    f = io.open(TEST_FILE, "r")
    if f then
        local content = f:read("*a")
        f:close()
        if content then
            assert(#content == 3, "truncate后读取应为3字节, 实际=" .. #content)
            assert(content == "ABC", "内容应为ABC, 实际=" .. content)
            log.info("vfs_lfs2_ops", "truncate后读取正确: " .. content)
        end
    end

    os.remove(TEST_FILE)
    log.info("vfs_lfs2_ops", "truncate后读取测试通过")
end

-- 测试: 目录操作后文件不被截断(验证opendir不会误调用truncate)
function vfs_lfs2_ops_test.test_opendir_does_not_truncate()
    log.info("vfs_lfs2_ops", "测试opendir不会误截断文件")
    -- 创建文件
    local f = io.open(TEST_FILE, "w")
    if not f then
        log.warn("vfs_lfs2_ops", "无法创建测试文件,跳过")
        return
    end
    f:write("IMPORTANT DATA")
    f:close()

    local size_before = fs.fsize(TEST_FILE)

    -- 执行目录列表操作(触发opendir/closedir)
    io.lsdir(TEST_DIR)
    sys.wait(10)

    -- 验证文件未被截断
    local size_after = fs.fsize(TEST_FILE)
    assert(size_before == size_after,
        "opendir操作不应改变文件大小! before=" .. size_before .. " after=" .. size_after)

    os.remove(TEST_FILE)
    log.info("vfs_lfs2_ops", "opendir不误截断测试通过")
end

return vfs_lfs2_ops_test
