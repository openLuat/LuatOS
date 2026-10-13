PROJECT = "ramfs_seek_write"
VERSION = "1.0.0"

local function hexdump(s)
    if s == nil then return "nil" end
    local t = {}
    for i = 1, #s do t[#t + 1] = string.format("%02X", s:byte(i)) end
    return string.format("len=%d [%s]", #s, table.concat(t, " "))
end

local function check(name, got, want)
    local ok = (got == want)
    log.info("SEEK", string.format("%-42s %s got=%s want=%s", name, ok and "PASS" or "FAIL", hexdump(got), hexdump(want)))
    return ok
end

-- case1: seek inside existing size, overwrite
local function case1(prefix)
    local path = prefix .. "t1.bin"
    local f = io.open(path, "wb")
    if not f then return nil, "open fail" end
    f:write("0123456789")
    local p = f:seek("set", 3)
    local r = f:write("XY")
    local tell = f:seek()
    f:close()
    return io.readFile(path), string.format("seek_ret=%s tell_after_write=%s", tostring(p), tostring(tell))
end

-- case2: seek beyond EOF then write (sparse / zero fill)
local function case2(prefix)
    local path = prefix .. "t2.bin"
    local f = io.open(path, "wb")
    if not f then return nil, "open fail" end
    local p = f:seek("set", 5)
    f:write("AB")
    local tell = f:seek()
    f:close()
    return io.readFile(path), string.format("seek_ret=%s tell_after_write=%s", tostring(p), tostring(tell))
end

-- case3: seek inside size then write past EOF (must extend, preserve gap)
local function case3(prefix)
    local path = prefix .. "t3.bin"
    local f = io.open(path, "wb")
    if not f then return nil, "open fail" end
    f:write("0123456789")
    local p = f:seek("set", 8)
    f:write("ABCDEF")
    f:close()
    return io.readFile(path), string.format("seek_ret=%s", tostring(p))
end

-- case4: r+b update mode, seek + overwrite
local function case4(prefix)
    local path = prefix .. "t4.bin"
    local f = io.open(path, "wb")
    f:write("0123456789")
    f:close()
    f = io.open(path, "r+b")
    if not f then return nil, "reopen fail" end
    local p = f:seek("set", 4)
    f:write("ZZ")
    f:close()
    return io.readFile(path), string.format("seek_ret=%s", tostring(p))
end

-- case5: sliding-window fragments arriving out of order (frag0 lost, frag1 first,
--        then frag0 retransmit, then frag2) -- each send carries its absolute offset
local function case5(prefix)
    local path = prefix .. "t5.bin"
    local chunk = 4
    local f = io.open(path, "wb")
    if not f then return nil, "open fail" end
    local trace = {}
    local function pwrite(off, data)
        local p = f:seek("set", off)
        f:write(data)
        trace[#trace + 1] = string.format("off=%d->seek_ret=%s", off, tostring(p))
    end
    pwrite(chunk * 1, "BBBB")
    pwrite(chunk * 0, "AAAA")
    pwrite(chunk * 2, "CCCC")
    f:close()
    return io.readFile(path), table.concat(trace, " | ")
end

sys.taskInit(function()
    local fs_list = {
        { name = "ramfs ", prefix = "/ram/" },
        { name = "lfs2  ", prefix = "/lfs2/" },
        { name = "posix ", prefix = "" },
    }

    local cases = {
        { name = "c1 in-file seek+overwrite", fn = case1,
          want = "012XY56789" },
        { name = "c2 seek past EOF then write", fn = case2,
          want = string.char(0, 0, 0, 0, 0) .. "AB" },
        { name = "c3 seek+write crossing EOF", fn = case3,
          want = "01234567ABCDEF" },
        { name = "c4 r+b seek+overwrite", fn = case4,
          want = "0123ZZ6789" },
        { name = "c5 out-of-order frags", fn = case5,
          want = "AAAABBBBCCCC" },
    }

    for _, fs in ipairs(fs_list) do
        log.info("SEEK", "========== " .. fs.name .. " ==========")
        for _, c in ipairs(cases) do
            local ok, got, extra = pcall(c.fn, fs.prefix)
            if not ok then
                log.info("SEEK", string.format("%s %-42s ERROR %s", fs.name, c.name, tostring(got)))
            else
                check(fs.name .. " " .. c.name, got, c.want)
                if extra then log.info("SEEK", "        detail: " .. extra) end
            end
        end
    end

    log.info("SEEK", "done")
    os.exit(0)
end)

sys.run()
