-- vfs_common.lua
-- 共享助手 + bug 记录器
-- 配合 vfs_cases.lua + mount_*.lua 使用

local M = {}

-- 由 mount_*.lua 在 setup() 中填充
M.MOUNT_POINT = ""        -- 例 "/ram" / "/lfs2" / ""(posix 用根)
M.FS_NAME = "unknown"     -- "ram" | "posix" | "lfs2" | "fatfs" | "tfs" | "pgfs"
M.SKIPPED = {}             -- 本 FS 跳过的 test_* 名集合

-- 已发现的 bug 列表 (在 dump_bugs() 时输出)
M.BUGS = {}
M.BUG_COUNTER = 0

-- 路径拼接: 把相对路径接到挂载点后面
-- posix 的 MOUNT_POINT 是 "" , 直接返回 p (即根)
function M.path(p)
    if M.MOUNT_POINT == "" then
        return p
    end
    -- 去掉 p 开头的 "/" 避免变成 "//"
    if string.sub(p, 1, 1) == "/" then
        return M.MOUNT_POINT .. p
    end
    return M.MOUNT_POINT .. "/" .. p
end

-- 跳过判断
function M.should_skip(name)
    for _, s in ipairs(M.SKIPPED) do
        if s == name then
            log.info("vfs_uniform", string.format("SKIP %s on %s", name, M.FS_NAME))
            return true
        end
    end
    return false
end

-- 错误时记录到 M.BUGS (运行时不会中断测试, 但会产生一个失败标记)
function M.record_bug(test_name, severity, expected, actual, repro, src_ref)
    M.BUG_COUNTER = M.BUG_COUNTER + 1
    local entry = {
        id = M.BUG_COUNTER,
        fs = M.FS_NAME,
        test = test_name,
        severity = severity or "low",
        expected = expected or "",
        actual = actual or "",
        repro = repro or "",
        src = src_ref or "",
    }
    table.insert(M.BUGS, entry)
    -- 立即在日志里打印
    log.warn("vfs_uniform", string.format(
        "BUG #%d [fs=%s test=%s sev=%s]\n  expected: %s\n  actual:   %s\n  src:      %s",
        entry.id, entry.fs, entry.test, entry.severity, entry.expected, entry.actual, entry.src))
end

-- 清理: 删除一组文件, 然后从下到上删除一组目录
function M.clean_paths(files, dirs)
    if files then
        for _, f in ipairs(files) do
            pcall(os.remove, f)
        end
    end
    if dirs then
        for i = #dirs, 1, -1 do
            pcall(io.rmdir, dirs[i])
        end
    end
end

-- 带文件类型/名字的递归 rm
function M.rm_tree(path)
    local ok, entries = io.lsdir(path, 200, 0)
    if ok and type(entries) == "table" then
        for _, entry in ipairs(entries) do
            local name = entry.name or entry
            local ftype = entry.type or 0
            local child = path .. "/" .. name
            if ftype == 1 then
                M.rm_tree(child)
                pcall(os.remove, child)
            else
                pcall(os.remove, child)
            end
        end
    end
    pcall(os.remove, path)
end

-- 在用例内用更友好的 assert
function M.assert_eq(actual, expected, msg)
    if actual ~= expected then
        local detail = string.format("expected %s, got %s", tostring(expected), tostring(actual))
        if msg then detail = msg .. " | " .. detail end
        error(detail, 2)
    end
end

function M.assert_true(cond, msg)
    if not cond then
        error(msg or "assert_true failed", 2)
    end
end

function M.assert_not_nil(v, msg)
    if v == nil then
        error(msg or "expected non-nil", 2)
    end
end

-- 把 BUGS 输出到 <MOUNT>/_bugs.md
function M.dump_bugs()
    if #M.BUGS == 0 then
        return
    end
    local lines = {}
    table.insert(lines, "# VFS 统一测试发现的 Bug — " .. M.FS_NAME)
    table.insert(lines, "")
    table.insert(lines, "由 vfs_uniform 框架自动生成, 共 " .. #M.BUGS .. " 条")
    table.insert(lines, "")
    for _, b in ipairs(M.BUGS) do
        table.insert(lines, string.format("## #%d %s::%s  [%s]", b.id, b.fs, b.test, b.severity))
        table.insert(lines, "")
        table.insert(lines, "- **Expected**: " .. b.expected)
        table.insert(lines, "- **Actual**: " .. b.actual)
        if b.src and b.src ~= "" then
            table.insert(lines, "- **Source**: `" .. b.src .. "`")
        end
        if b.repro and b.repro ~= "" then
            table.insert(lines, "- **Repro**:")
            for line in string.gmatch(b.repro, "([^\n]+)") do
                table.insert(lines, "  " .. line)
            end
        end
        table.insert(lines, "")
    end

    local out_path = M.path("_bugs.md")
    local f = io.open(out_path, "wb")
    if f then
        f:write(table.concat(lines, "\n"))
        f:close()
        log.info("vfs_uniform", "BUGS dumped to " .. out_path)
    else
        log.warn("vfs_uniform", "无法写 " .. out_path .. " (FS 只读?)")
        log.info("vfs_uniform", "BUGS:\n" .. table.concat(lines, "\n"))
    end
end

-- 用 SKIPPED 表包装 cases 表, 让 test_<name> 出现在 SKIPPED 中时直接 return
function M.wrap_skips(cases)
    for k, v in pairs(cases) do
        if type(v) == "function" and string.sub(k, 1, 5) == "test_" then
            local orig = v
            cases[k] = function(...)
                if M.should_skip(k) then return end
                return orig(...)
            end
        end
    end
    return cases
end

return M
