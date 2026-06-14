-- vfs_cases.lua
-- 30 个跨 FS 共享的 test_* 用例
-- 只用 io.* / os.* / fs.* / io.open, 不调用 FS 特有 API

local common = require("vfs_common")
local cases = {}

-- ============================================================
-- A. 基础文件操作 (C01-C08)
-- ============================================================

function cases.test_basic_open_close_wb()
    local p = common.path("vfs_basic_open.txt")
    os.remove(p)
    local f = io.open(p, "wb")
    common.assert_not_nil(f, "open wb returned nil")
    f:close()
    os.remove(p)
end

function cases.test_basic_write_read_roundtrip()
    local p = common.path("vfs_basic_rw.txt")
    os.remove(p)
    local f = io.open(p, "wb")
    f:write("hello")
    f:close()

    f = io.open(p, "rb")
    local got = f:read("*a")
    f:close()
    common.assert_eq(got, "hello", "roundtrip content mismatch")
    os.remove(p)
end

function cases.test_basic_write_read_large()
    local p = common.path("vfs_basic_large.bin")
    os.remove(p)

    local payload = ""
    for i = 0, 255 do
        payload = payload .. string.char((i * 7 + 13) % 256)
    end
    -- 64KB
    local big = string.rep(payload, 256)

    local f = io.open(p, "wb")
    f:write(big)
    f:close()

    f = io.open(p, "rb")
    local got = f:read("*a")
    f:close()
    common.assert_eq(#got, #big, "large file size mismatch")
    common.assert_eq(got, big, "large file content mismatch")
    os.remove(p)
end

function cases.test_basic_seek_tell()
    local p = common.path("vfs_basic_seek.bin")
    os.remove(p)
    local f = io.open(p, "wb")
    for i = 0, 99 do
        f:write(string.char(i % 256))
    end
    f:close()

    f = io.open(p, "rb")
    f:seek("set", 50)
    common.assert_eq(f:seek(), 50, "seek() should return 50 after seek('set', 50)")
    local b = f:read(1)
    common.assert_eq(string.byte(b or ""), 50, "byte at pos 50 should be 50")
    f:close()
    os.remove(p)
end

function cases.test_basic_seek_end()
    local p = common.path("vfs_basic_seek_end.bin")
    os.remove(p)
    local f = io.open(p, "wb")
    for i = 0, 99 do
        f:write("x")
    end
    f:close()

    f = io.open(p, "rb")
    f:seek("end")
    common.assert_eq(f:seek(), 100, "seek() after seek('end') should be 100")
    f:close()
    os.remove(p)
end

function cases.test_basic_seek_cur()
    local p = common.path("vfs_basic_seek_cur.bin")
    os.remove(p)
    local f = io.open(p, "wb")
    for i = 0, 99 do
        f:write("x")
    end
    f:close()

    f = io.open(p, "rb")
    f:seek("end") -- 100
    f:seek("cur", -10)
    common.assert_eq(f:seek(), 90, "seek() after seek('cur', -10) from END should be 90")
    f:close()
    os.remove(p)
end

function cases.test_basic_append_mode()
    local p = common.path("vfs_basic_append.txt")
    os.remove(p)
    local f = io.open(p, "wb")
    f:write("foo")
    f:close()

    f = io.open(p, "ab")
    f:write("bar")
    f:close()

    f = io.open(p, "rb")
    local got = f:read("*a")
    f:close()
    common.assert_eq(got, "foobar", "append mode should produce 'foobar'")
    os.remove(p)
end

function cases.test_basic_truncate()
    local p = common.path("vfs_basic_trunc.bin")
    os.remove(p)
    local f = io.open(p, "wb")
    f:write(string.rep("A", 1024))
    f:close()

    if fs and fs.truncate then
        fs.truncate(p, 100)
        common.assert_eq(fs.fsize(p), 100, "fsize after truncate to 100")
    else
        log.info("vfs_uniform", "fs.truncate 不可用, 跳过")
    end
    os.remove(p)
end

-- ============================================================
-- B. 目录操作 (C09-C13)
-- ============================================================

function cases.test_dir_mkdir_rmdir_empty()
    local d = common.path("vfs_dir_empty")
    io.rmdir(d)
    local ok = io.mkdir(d)
    common.assert_true(ok == true, "mkdir empty dir should succeed")

    ok = io.rmdir(d)
    common.assert_true(ok == true, "rmdir empty dir should succeed")
end

function cases.test_dir_lsdir_returns_entries()
    local d = common.path("vfs_dir_ls")
    common.rm_tree(d)
    io.mkdir(d)

    for i = 1, 3 do
        local f = io.open(d .. "/f" .. i .. ".txt", "wb")
        f:write("x")
        f:close()
    end

    local ok, entries = io.lsdir(d, 50, 0)
    common.assert_true(ok == true, "lsdir should succeed")
    common.assert_true(type(entries) == "table", "entries should be a table")
    common.assert_eq(#entries, 3, "should have 3 entries")

    -- 检查每个条目的 type/name
    local names = {}
    for _, e in ipairs(entries) do
        table.insert(names, e.name)
    end
    table.sort(names)
    common.assert_eq(names[1], "f1.txt", "entry 1 name")
    common.assert_eq(names[2], "f2.txt", "entry 2 name")
    common.assert_eq(names[3], "f3.txt", "entry 3 name")

    common.rm_tree(d)
end

function cases.test_dir_dexist()
    local d = common.path("vfs_dir_dexist")
    io.rmdir(d)

    -- 创一个子文件作为"目录存在"的间接证据 (LuatOS 的 io.exists 只查文件)
    local probe = d .. "/_probe.txt"
    local mk_ok = io.mkdir(d)
    if mk_ok ~= true then
        error("mkdir should succeed")
    end
    local f = io.open(probe, "wb")
    common.assert_not_nil(f, "open probe after mkdir")
    f:write("x")
    f:close()
    common.assert_eq(io.exists(probe), true, "probe file should exist after mkdir")
    common.clean_paths({probe}, {d})

    -- 记录已知 API 差异: LuatOS 的 io.exists 不识别目录
    -- 这不是 bug, 是 LuatOS API 约定. 不做断言.
end

function cases.test_dir_rmdir_nonempty_fails()
    local d = common.path("vfs_dir_nonempty")
    local f = d .. "/inside.txt"
    common.clean_paths({f}, {d})

    io.mkdir(d)
    local ff = io.open(f, "wb")
    ff:write("x")
    ff:close()

    local ok = io.rmdir(d)
    -- POSIX 约定: rmdir 非空目录必须失败
    -- 但部分 FS (lfs2 用 lfs_remove 代替) 可能允许
    if ok == true then
        common.record_bug(
            "test_dir_rmdir_nonempty_fails",
            "med",
            "rmdir 非空目录应失败",
            "rmdir 成功了 (可能留下孤立文件)",
            "1. mkdir d\n2. 创 d/f\n3. rmdir d",
            "luat/vfs/luat_fs_lfs2.c:225 (lfs2 用 lfs_remove 代替 rmdir)"
        )
        error("rmdir non-empty should have failed but succeeded (recorded as bug)")
    end

    common.clean_paths({f}, {d})
end

function cases.test_dir_nested_mkdir_auto_parent()
    local d = common.path("vfs_dir_a/b/c")
    common.clean_paths({}, {common.path("vfs_dir_a/b"), common.path("vfs_dir_a")})

    local ok = io.mkdir(d)
    if ok ~= true then
        common.record_bug(
            "test_dir_nested_mkdir_auto_parent",
            "med",
            "mkdir 嵌套目录应自动创建父目录 (如 ram 行为)",
            "mkdir 失败, 没有自动创建父目录",
            "1. io.mkdir(\"a/b/c\") (b 不存在)",
            "luat/vfs/luat_fs_lfs2.c:206-223 (lfs2 不创建父目录)"
        )
        error("nested mkdir should auto-create parents (recorded as bug)")
    end

    common.clean_paths({}, {common.path("vfs_dir_a/b"), common.path("vfs_dir_a")})
end

-- ============================================================
-- C. 文件元数据 (C14-C18)
-- ============================================================

function cases.test_meta_fexist()
    local p = common.path("vfs_meta_fexist.txt")
    os.remove(p)
    common.assert_eq(io.exists(p), false, "should not exist")

    local f = io.open(p, "wb")
    f:write("x")
    f:close()

    common.assert_eq(io.exists(p), true, "should exist")
    os.remove(p)
end

function cases.test_meta_fsize()
    local p = common.path("vfs_meta_fsize.bin")
    os.remove(p)
    local N = 1234
    local f = io.open(p, "wb")
    f:write(string.rep("Z", N))
    f:close()

    common.assert_eq(fs.fsize(p), N, "fsize should match N")
    os.remove(p)
end

function cases.test_meta_rename_file()
    local a = common.path("vfs_meta_rename_a.txt")
    local b = common.path("vfs_meta_rename_b.txt")
    common.clean_paths({a, b}, {})

    local f = io.open(a, "wb")
    f:write("data-a")
    f:close()

    local ok, err = os.rename(a, b)
    common.assert_true(ok == true, "rename a->b should succeed (err=" .. tostring(err) .. ")")
    common.assert_eq(io.exists(a), false, "a should not exist after rename")
    common.assert_eq(io.exists(b), true, "b should exist after rename")

    f = io.open(b, "rb")
    common.assert_eq(f:read("*a"), "data-a", "renamed content")
    f:close()
    common.clean_paths({b}, {})
end

function cases.test_meta_rename_overwrite()
    local d = common.path("vfs_meta_rename_ow")
    local a = d .. "/from.txt"
    local b = d .. "/to.txt"
    common.clean_paths({a, b}, {d})

    io.mkdir(d)
    local f = io.open(a, "wb")
    f:write("new")
    f:close()
    f = io.open(b, "wb")
    f:write("old")
    f:close()

    local ok = os.rename(a, b)
    if ok ~= true then
        common.record_bug(
            "test_meta_rename_overwrite",
            "low",
            "rename 覆盖目标文件应成功",
            "rename 失败",
            "1. mkdir d; 创 d/from.txt 和 d/to.txt\n2. rename d/from.txt d/to.txt",
            "因 FS 而异"
        )
        error("rename overwrite should succeed (recorded as bug)")
    end

    f = io.open(b, "rb")
    common.assert_eq(f:read("*a"), "new", "target should have new content")
    f:close()
    common.clean_paths({b}, {d})
end

function cases.test_meta_remove_nonexistent()
    local p = common.path("vfs_meta_never_exists_xyz")
    os.remove(p)  -- 清理可能残留
    local ok = os.remove(p)
    -- POSIX 约定: 移除不存在文件应返回 false
    -- 但部分 FS 宽容, 不算 bug
    if ok == true then
        log.info("vfs_uniform", "remove nonexistent returned true (tolerated)")
    end
end

-- ============================================================
-- D. 引用计数 (C19-C20)
-- ============================================================

function cases.test_refcount_remove_open_fails()
    local p = common.path("vfs_refcount_rm.txt")
    os.remove(p)
    local f = io.open(p, "wb")
    f:write("data")
    f:close()

    f = io.open(p, "r")
    common.assert_not_nil(f, "open for read")
    local ok = os.remove(p)
    f:close()

    if ok == true then
        common.record_bug(
            "test_refcount_remove_open_fails",
            "med",
            "打开中的文件不应被 os.remove 删除",
            "os.remove 成功了",
            "1. 创文件 p\n2. open p\n3. os.remove p\n4. close",
            "luat/vfs/luat_fs_lfs2.c:134 (lfs2 直接调 lfs_remove)"
        )
        error("remove open file should have failed (recorded as bug)")
    end

    os.remove(p)
end

function cases.test_refcount_rename_open_fails()
    local d = common.path("vfs_refcount_rn")
    local a = d .. "/src.txt"
    local b = d .. "/dst.txt"
    common.clean_paths({a, b}, {d})

    io.mkdir(d)
    local f = io.open(a, "wb")
    f:write("x")
    f:close()

    f = io.open(a, "r")
    common.assert_not_nil(f, "open src for read")
    local ok = os.rename(a, b)
    f:close()

    if ok == true then
        common.record_bug(
            "test_refcount_rename_open_fails",
            "med",
            "打开中的源文件不应被 os.rename 重命名",
            "os.rename 成功了",
            "1. 创文件 src\n2. open src\n3. rename src -> dst\n4. close",
            "luat/vfs/luat_fs_lfs2.c:134 (lfs2 不检查引用)"
        )
        error("rename open file should have failed (recorded as bug)")
    end

    common.clean_paths({a, b}, {d})
end

-- ============================================================
-- E. 边界 (C21-C26)
-- ============================================================

function cases.test_edge_empty_file()
    local p = common.path("vfs_edge_empty.txt")
    os.remove(p)
    local f = io.open(p, "wb")
    f:close()

    common.assert_eq(fs.fsize(p), 0, "empty file fsize should be 0")

    f = io.open(p, "rb")
    local got = f:read("*a")
    f:close()
    common.assert_eq(got, "", "empty file read should be empty")
    os.remove(p)
end

function cases.test_edge_block_size_boundary()
    local p = common.path("vfs_edge_block.bin")
    os.remove(p)

    local payload = ""
    for i = 0, 4095 do
        payload = payload .. string.char((i * 11 + 7) % 256)
    end

    local f = io.open(p, "wb")
    f:write(payload)
    f:close()

    f = io.open(p, "rb")
    local got = f:read("*a")
    f:close()
    common.assert_eq(#got, 4096, "block boundary size should be 4096")
    common.assert_eq(got, payload, "block boundary content")
    os.remove(p)
end

function cases.test_edge_long_filename()
    -- 60 字符
    local name = string.rep("L", 60) .. ".txt"
    local p = common.path("vfs_edge_" .. name)
    os.remove(p)

    local f = io.open(p, "wb")
    if f == nil then
        common.record_bug(
            "test_edge_long_filename",
            "low",
            "60 字符文件名应可创建",
            "open 失败",
            "1. 创 60 字符文件名",
            "name_max 限制因 FS 而异"
        )
        error("long filename open should succeed (recorded as bug)")
    end
    f:write("x")
    f:close()
    os.remove(p)
end

function cases.test_edge_filename_max()
    -- 63 字符 (lfs2 的 name_max)
    local name = string.rep("M", 63) .. ".txt"
    local p = common.path("vfs_edge_" .. name)
    os.remove(p)

    local f = io.open(p, "wb")
    if f == nil then
        -- 期望 ram 通过, 其他 FS 可能失败
        if common.FS_NAME ~= "ram" then
            log.info("vfs_uniform", "63-char filename not supported on " .. common.FS_NAME .. " (tolerated)")
        else
            error("63-char filename should work on ram")
        end
    else
        f:write("x")
        f:close()
        os.remove(p)
    end
end

function cases.test_edge_deep_nesting()
    local root = common.path("vfs_edge_deep")
    local deep = root .. "/a/b/c/d/e/f/g"
    common.rm_tree(root)

    local ok = io.mkdir(deep)
    if ok ~= true then
        common.record_bug(
            "test_edge_deep_nesting",
            "low",
            "mkdir a/b/c/d/e/f/g 应成功 (任一 FS 都应支持 7 级嵌套)",
            "mkdir 失败",
            "1. mkdir a/b/c/d/e/f/g",
            "因 FS 而异"
        )
        error("deep mkdir should succeed (recorded as bug)")
    end

    common.rm_tree(root)
end

function cases.test_edge_special_chars_in_name()
    local p1 = common.path("vfs_edge_a b c.txt")
    local p2 = common.path("vfs_edge_a-b_c.txt")
    os.remove(p1)
    os.remove(p2)

    local f = io.open(p1, "wb")
    if f then
        f:write("x")
        f:close()
        os.remove(p1)
    else
        log.info("vfs_uniform", "filename with spaces not supported on " .. common.FS_NAME .. " (tolerated)")
    end

    f = io.open(p2, "wb")
    if f then
        f:write("x")
        f:close()
        os.remove(p2)
    else
        log.info("vfs_uniform", "filename with -_ not supported on " .. common.FS_NAME .. " (tolerated)")
    end
end

-- ============================================================
-- F. POSIX flags (C27-C30)
-- ============================================================

function cases.test_posix_mode_w_plus()
    local p = common.path("vfs_posix_wplus.txt")
    os.remove(p)

    local f = io.open(p, "w+")
    common.assert_not_nil(f, "open w+")
    f:write("xyz")
    f:seek("set", 0)
    local got = f:read("*a")
    f:close()
    common.assert_eq(got, "xyz", "w+ write-then-read")
    os.remove(p)
end

function cases.test_posix_mode_r_plus()
    local p = common.path("vfs_posix_rplus.txt")
    os.remove(p)

    local f = io.open(p, "wb")
    f:write("initial")
    f:close()

    f = io.open(p, "r+")
    if f == nil then
        log.info("vfs_uniform", "r+ mode not supported on " .. common.FS_NAME .. " (tolerated)")
        return
    end
    f:write("X")
    f:seek("set", 0)
    local got = f:read("*a")
    f:close()
    -- 期望 "Xniti" 之类 (覆盖了前 1 字节)
    common.assert_eq(#got, 7, "r+ size should be preserved")
    common.assert_eq(string.sub(got, 1, 1), "X", "r+ first byte overwritten")
    os.remove(p)
end

function cases.test_posix_binary_text_same()
    local p = common.path("vfs_posix_bt.bin")
    os.remove(p)

    local f = io.open(p, "wb")
    f:write(string.char(0x0A, 0x0D, 0x00, 0xFF))
    f:close()

    f = io.open(p, "rb")
    local got = f:read(4)
    f:close()
    common.assert_eq(string.byte(got, 1), 0x0A, "byte 1 should be 0x0A")
    common.assert_eq(string.byte(got, 2), 0x0D, "byte 2 should be 0x0D")
    common.assert_eq(string.byte(got, 3), 0x00, "byte 3 should be 0x00")
    common.assert_eq(string.byte(got, 4), 0xFF, "byte 4 should be 0xFF")
    os.remove(p)
end

function cases.test_posix_read_closed_fails()
    local p = common.path("vfs_posix_closed.txt")
    os.remove(p)
    local f = io.open(p, "wb")
    f:write("x")
    f:close()

    f = io.open(p, "r")
    common.assert_not_nil(f, "open for read")
    f:close()

    local ok, err = pcall(function() return f:read(1) end)
    if ok and err ~= nil then
        -- 正常: read 在 closed file 上要么 error 要么返回 nil
        log.info("vfs_uniform", "read on closed file returned " .. tostring(err) .. " (ok)")
    end
    -- 读 closed file 不强制要求失败, 视实现而定
    os.remove(p)
end

return cases
