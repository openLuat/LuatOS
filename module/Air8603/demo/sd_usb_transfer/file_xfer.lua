--[[
@module  file_xfer
@summary 目录/文件搬运：遍历 → 分块复制 → 回读校验 →（可选）删源
@version 1.0
@date    2026.11.06
@author  黄何
@usage
本文件提供 file_xfer.copy_tree() 和 file_xfer.summary_text() 两个接口。

设计取舍：
  · 只用 io 核心库（io.open / read / write / lsdir / fileSize / mkdir），不引入
    crypto、exfs 之类额外依赖，换固件也能直接跑；
  · 校验用"分块回读逐字节比较"，不依赖md5，代价是写完后多读一遍（可以用verify=false关掉）；
  · 大文件按 opt.chunk（默认32KB）流式读写，内存占用与文件大小无关；
  · 单个文件失败只记一笔、继续下一个，不会因为一个坏文件把整批停下。
]]

local M = {}

-- ==================== 路径工具 ====================
local function join(a, b)
    if not a or a == "" then return b end
    if a:sub(-1) == "/" then return a .. b end
    return a .. "/" .. b
end

local function with_slash(p)
    if p:sub(-1) ~= "/" then return p .. "/" end
    return p
end

local function is_dir(path)
    if io.dexist then
        local ok, r = pcall(io.dexist, path)
        if ok and r then return true end
    end
    if io.exists then
        local ok, r = pcall(io.exists, path)
        if ok and r then return true end
    end
    return false
end

local function ensure_dir(path)
    if is_dir(path) then return true end
    local ok, err = io.mkdir(path)
    -- 返回码 -8 = 已存在，当作成功
    if ok == true or err == -8 then return true end
    log.warn("xfer", string.format("建目录失败 %s（ret=%s err=%s）", path, tostring(ok), tostring(err)))
    return false
end

-- ==================== 列目录（分页取全） ====================
local function list_dir(path)
    local out, offset = {}, 0
    while true do
        local ok, data = io.lsdir(with_slash(path), 100, offset)
        if not ok or type(data) ~= "table" then break end
        for _, it in ipairs(data) do out[#out + 1] = it end
        if #data < 100 then break end
        offset = offset + 100
    end
    return out
end

-- ==================== 单文件复制 ====================
-- @return "ok" | "skip" | "fail", bytes, errmsg
local function copy_file(src, dst, opt, stats)
    local size = io.fileSize(src)
    if not size then return "fail", 0, "读不到源文件大小" end

    -- 目标已存在：按策略决定跳过还是覆盖
    local dsize = io.fileSize(dst)
    if dsize ~= nil then
        if opt.skip_same and dsize == size then
            return "skip", 0, nil
        end
        if not opt.overwrite then
            return "skip", 0, nil
        end
        os.remove(dst)
    end

    -- 1、复制
    local fin = io.open(src, "rb")
    if not fin then return "fail", 0, "打不开源文件（被占用/坏块）" end
    local fout = io.open(dst, "wb")
    if not fout then
        fin:close()
        return "fail", 0, "建不了目标文件（只读/空间满）"
    end

    local done, err = 0, nil
    while true do
        local data = fin:read(opt.chunk)
        if not data or #data == 0 then break end
        local wok = fout:write(data)
        if wok == false then err = "写入失败（空间满/掉盘）" break end
        done = done + #data
        if opt.on_bytes then opt.on_bytes(done, size) end
    end
    fin:close()
    fout:close()

    if err then
        os.remove(dst)
        return "fail", done, err
    end
    if done ~= size then
        os.remove(dst)
        return "fail", done, string.format("字节数不符（写 %d / 源 %d）", done, size)
    end

    -- 2、回读校验
    if opt.verify then
        local a = io.open(src, "rb")
        local b = io.open(dst, "rb")
        if not a or not b then
            if a then a:close() end
            if b then b:close() end
            return "fail", done, "校验时打不开文件"
        end
        local bad = nil
        while true do
            local da = a:read(opt.chunk)
            local db = b:read(opt.chunk)
            if (not da or #da == 0) and (not db or #db == 0) then break end
            if da ~= db then bad = true break end
        end
        a:close()
        b:close()
        if bad then
            return "fail", done, "回读校验不一致"
        end
    end

    -- 3、搬运模式：删源
    if opt.delete_src then
        local rok = os.remove(src)
        if rok == false then
            return "fail", done, "已复制但删源失败（只读？）"
        end
    end

    return "ok", done, nil
end

-- ==================== 递归复制 ====================
--[[
opt:
    overwrite   目标同名文件是否覆盖（false则跳过）
    skip_same   目标同名且大小相同就跳过（双向同步用）
    verify      写完后回读逐字节比较
    delete_src  复制成功后删源（= 剪切/搬运）
    chunk       单次读写字节数
    max_depth   递归深度上限（防止异常目录打转）
    should_abort function() -> boolean，返回true时中止（U盘拔出等）
    on_file     function(src, idx, total)
    on_bytes    function(done, size) 单文件内进度
]]
-- @return table stats {ok, files, bytes, skipped, failed, ms, errors}
function M.copy_tree(src_root, dst_root, opt)
    opt = opt or {}
    opt.chunk     = opt.chunk or 32 * 1024
    opt.max_depth = opt.max_depth or 6
    opt.overwrite = (opt.overwrite ~= false)
    opt.verify    = (opt.verify ~= false)
    opt.skip_same = (opt.skip_same == true)

    local stats = { ok = true, files = 0, bytes = 0, skipped = 0, failed = 0, ms = 0, errors = {} }
    local t0 = mcu and mcu.ticks and mcu.ticks() or 0

    if not is_dir(src_root) then
        stats.ok = false
        stats.errors[#stats.errors + 1] = "源目录不存在：" .. src_root
        return stats
    end
    if not ensure_dir(dst_root) then
        stats.ok = false
        stats.errors[#stats.errors + 1] = "目标目录建不出来：" .. dst_root
        return stats
    end

    local total_files = 0
    local function count_dir(p, depth)
        if depth > opt.max_depth then return end
        for _, it in ipairs(list_dir(p)) do
            if it.type == 1 then count_dir(join(p, it.name), depth + 1)
            else total_files = total_files + 1 end
        end
    end
    count_dir(src_root, 0)

    local idx = 0
    local function walk(sdir, ddir, depth)
        if depth > opt.max_depth then
            stats.errors[#stats.errors + 1] = "超过递归深度，跳过：" .. sdir
            return
        end
        ensure_dir(ddir)
        local items = list_dir(sdir)
        for _, it in ipairs(items) do
            if opt.should_abort and opt.should_abort() then
                stats.ok = false
                stats.errors[#stats.errors + 1] = "传输被中止（U盘拔出/用户取消）"
                return
            end

            local s = join(sdir, it.name)
            local d = join(ddir, it.name)

            if it.type == 1 then
                walk(s, d, depth + 1)
            else
                idx = idx + 1
                if opt.on_file then opt.on_file(s, idx, total_files) end
                local ret, n, err = copy_file(s, d, opt, stats)
                if ret == "ok" then
                    stats.files = stats.files + 1
                    stats.bytes = stats.bytes + n
                elseif ret == "skip" then
                    stats.skipped = stats.skipped + 1
                else
                    stats.failed = stats.failed + 1
                    if #stats.errors < 20 then
                        stats.errors[#stats.errors + 1] = string.format("%s：%s", s, tostring(err))
                    end
                    log.error("xfer", string.format("失败 %s：%s", s, tostring(err)))
                end
            end
        end
    end

    walk(src_root, dst_root, 0)

    local t1 = mcu and mcu.ticks and mcu.ticks() or 0
    local hz = (mcu and mcu.hz and mcu.hz()) or 1000
    stats.ms = math.floor((t1 - t0) * 1000 / hz)
    stats.ok = stats.ok and (stats.failed == 0)
    return stats
end

-- 摘要文本（日志用这个）
function M.summary_text(stats)
    local kb = stats.bytes / 1024
    local sec = math.max(0.001, stats.ms / 1000)
    local speed = kb / sec
    return string.format("成功 %d 个 / %.1f KB，跳过 %d，失败 %d，用时 %.1f s（%.0f KB/s）",
        stats.files, kb, stats.skipped, stats.failed, sec, speed)
end

return M
