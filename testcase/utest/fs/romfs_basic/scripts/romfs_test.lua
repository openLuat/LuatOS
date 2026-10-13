-- romfs_test.lua - ROMFS 功能测试
-- /romfs  = 指针模式挂载; /romfs2 = read回调模式挂载(同一镜像)
local romfs_test = {}

local HELLO = "Hello ROMFS!\n"
local NOTE  = "nested file ok\n"
local LONG  = "long name ok\n"
local LONGNAME = "a_very_long_file_name_over_16_chars.txt"
-- 边界用例: 4 层目录里的文件 / 恰好 64 字节的名字(对应 luat_vfs_romfs.c 的两处 off-by-one 修复)
local DEPTH4      = "depth4 dir file ok\n"          -- four/b/c/d/nested4.txt
local NAME64      = string.rep("n", 60) .. ".txt"   -- 不含 NUL 恰好 64 字节
local NAME64_DATA = "max name ok\n"

local function databin_byte(i)  -- fixture data.bin 第 i 字节(0 基)
    return (i * 7 + 13) % 256
end

function romfs_test.test_mount_ok()
    assert(io.exists("/romfs/hello.txt") == true, "/romfs 未挂载或 hello.txt 缺失")
    assert(io.exists("/romfs2/hello.txt") == true, "/romfs2(回调模式) 未挂载")
end

function romfs_test.test_read_file()
    local data = io.readFile("/romfs/hello.txt")
    assert(data == HELLO, "hello.txt 内容不匹配: " .. tostring(data))
end

function romfs_test.test_fsize()
    assert(io.fileSize("/romfs/hello.txt") == #HELLO, "hello.txt fileSize 不匹配")
    assert(io.fileSize("/romfs/subdir/data.bin") == 256, "data.bin 大小应为 256")
end

function romfs_test.test_seek_read()
    local f = assert(io.open("/romfs/subdir/data.bin", "rb"), "open data.bin 失败")
    assert(f:seek("set", 10) == 10, "seek set 10")
    local b = f:read(4)
    assert(b and #b == 4 and string.byte(b, 1) == databin_byte(10), "seek 后读取内容不对")
    assert(f:seek("end") == 256, "seek end 应得 256")
    assert(f:seek("cur", -6) == 250, "seek cur -6 应得 250")
    assert(f:seek("set", 9999) == 256, "越界 seek 应钳制到 256")
    f:close()
end

function romfs_test.test_binary_integrity()
    local f = assert(io.open("/romfs/subdir/data.bin", "rb"))
    local data = f:read("*a")
    f:close()
    assert(#data == 256, "data.bin 长度应为 256")
    for i = 1, 256 do
        assert(string.byte(data, i) == databin_byte(i - 1), "data.bin 第 " .. i .. " 字节不匹配")
    end
end

function romfs_test.test_empty_file()
    assert(io.exists("/romfs/empty.txt") == true)
    assert(io.fileSize("/romfs/empty.txt") == 0)
    local f = assert(io.open("/romfs/empty.txt", "rb"))
    assert(f:read("*a") == "", "空文件应读出空串")
    f:close()
end

function romfs_test.test_long_filename()
    local p = "/romfs/" .. LONGNAME
    assert(io.exists(p) == true, "长文件名文件不存在")
    assert(io.readFile(p) == LONG, "长文件名文件内容不匹配")
end

function romfs_test.test_subdir()
    assert(io.readFile("/romfs/subdir/note.txt") == NOTE, "嵌套文件内容不匹配")
end

function romfs_test.test_lsdir_root()
    local ok, ents = io.lsdir("/romfs/", 50, 0)
    assert(ok == true and type(ents) == "table", "lsdir /romfs/ 失败")
    local by_name = {}
    for _, e in ipairs(ents) do by_name[e.name] = e end
    assert(by_name["hello.txt"] and by_name["hello.txt"].type == 0, "hello.txt 应存在且为文件")
    assert(by_name["hello.txt"].size == #HELLO, "lsdir 回填 size 不对")
    assert(by_name["subdir"] and by_name["subdir"].type == 1, "subdir 应存在且为目录")
    assert(by_name["empty.txt"], "empty.txt 应在列表中")
    assert(by_name[LONGNAME], "长文件名应在列表中")
end

function romfs_test.test_lsdir_subdir()
    local ok, ents = io.lsdir("/romfs/subdir/", 50, 0)
    assert(ok == true, "lsdir subdir 失败")
    assert(#ents == 2, "subdir 应有 2 个条目, 实际 " .. #ents)
end

function romfs_test.test_lsdir_offset()
    local ok1, all = io.lsdir("/romfs/", 50, 0)
    local ok2, part = io.lsdir("/romfs/", 50, 2)
    assert(ok1 and ok2 and #part == #all - 2, "lsdir offset 分页不对")
end

function romfs_test.test_not_exist()
    assert(io.exists("/romfs/no_such_file.txt") == false)
    assert(io.open("/romfs/no_such_file.txt", "rb") == nil, "打开不存在文件应失败")
    assert(io.open("/romfs/subdir", "rb") == nil, "打开目录应失败")
end

function romfs_test.test_readonly()
    assert(io.open("/romfs/hello.txt", "w") == nil, "w 模式应被拒绝")
    assert(io.open("/romfs/newfile.txt", "wb") == nil, "wb 模式应被拒绝")
    assert(os.remove("/romfs/hello.txt") ~= true, "remove 应失败")
    assert(io.mkdir("/romfs/newdir") ~= true, "mkdir 应失败")
end

function romfs_test.test_hardlink()
    assert(io.readFile("/romfs/link_hello.txt") == HELLO, "硬链接读取应与目标一致")
end

function romfs_test.test_symlink()
    assert(io.readFile("/romfs/sym_hello.txt") == HELLO, "符号链接读取应与目标一致")
end

function romfs_test.test_callback_mode_parity()
    assert(io.readFile("/romfs2/hello.txt") == HELLO, "回调模式 hello.txt 不一致")
    assert(io.readFile("/romfs2/subdir/note.txt") == NOTE, "回调模式嵌套文件不一致")
    assert(io.readFile("/romfs2/" .. LONGNAME) == LONG, "回调模式长文件名不一致")
    assert(io.fileSize("/romfs2/subdir/data.bin") == 256, "回调模式 fsize 不一致")
    local ok, ents = io.lsdir("/romfs2/", 50, 0)
    assert(ok == true and #ents >= 5, "回调模式 lsdir 异常")
    local f = assert(io.open("/romfs2/subdir/data.bin", "rb"))
    f:seek("set", 255)
    local b = f:read(1)
    f:close()
    assert(b and string.byte(b) == databin_byte(255), "回调模式 seek+read 不一致")
end

-- 4 层目录里的文件可用: 旧实现对目录的每个子节点(含文件)都做 depth+1 检查,
-- 会让第 LUAT_ROMFS_MAX_DIR_DEPTH 层目录里的文件把整个 mount 判失败。
function romfs_test.test_file_in_deepest_dir()
    assert(io.exists("/romfs/four/b/c/d/nested4.txt") == true, "4 层目录内的文件应可见")
    assert(io.readFile("/romfs/four/b/c/d/nested4.txt") == DEPTH4, "4 层目录内文件内容不匹配")
    assert(io.fileSize("/romfs/four/b/c/d/nested4.txt") == #DEPTH4, "4 层目录内文件大小不匹配")
    assert(io.exists("/romfs2/four/b/c/d/nested4.txt") == true, "回调模式 4 层目录文件缺失")
end

-- 恰好 LUAT_ROMFS_MAX_NAME(默认 64) 字节的名字可用: 旧实现"读满 64 字节仍未遇到 NUL"
-- 就判名字过长, 会让 64 字节名被静默丢弃(条目不参与匹配也不出现在 lsdir 中)。
function romfs_test.test_max_name_length_file()
    assert(io.exists("/romfs/" .. NAME64) == true, "64 字节名字应可见")
    assert(io.readFile("/romfs/" .. NAME64) == NAME64_DATA, "64 字节名字内容不匹配")
    assert(io.fileSize("/romfs/" .. NAME64) == #NAME64_DATA, "64 字节名字大小不匹配")
    local ok, ents = io.lsdir("/romfs/", 50, 0)
    assert(ok == true, "lsdir /romfs/ 失败")
    local seen = false
    for _, e in ipairs(ents) do
        if e.name == NAME64 then seen = true end
    end
    assert(seen, "64 字节名字应出现在 lsdir 中")
end

return romfs_test
