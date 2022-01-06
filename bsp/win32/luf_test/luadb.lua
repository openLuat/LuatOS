
-- 读取命令行参数
local srcpath = "disk"
if arg[1] then
    srcpath = arg[1]
end


local function lsdir(path, files, shortname)
    local exe = io.popen("dir /b " .. (shortname and " " or " /s ") .. path)
    if exe then
        for line in exe:lines() do
            table.insert(files, line)
        end
        exe:close()
    end
end


local function oscall(cmd, quite, cwd)
    if cwd and Base_CWD then
        lfs.chdir(cwd)
    end
    if tool_debug then
        log.info("cmd", cmd)
    end
    local exe = io.popen(cmd)
    if exe then
        for line in exe:lines() do
            if not quite then
                log.info("cmd", line)
            end
        end
        exe:close()
    end
    if cwd and Base_CWD then
        lfs.chdir(Base_CWD)
    end
end

function TLD(buff, T, D)
    buff:pack("bb", T, D:len())
    buff:write(D)
end

local files = {}
lsdir(srcpath, files, true)
-- oscall("mkdir tmp")

local buff = zbuff.create(256*1024)
local magic = string.char(0x5A, 0xA5, 0X5A, 0xA5)

-- -- 先写入magic
--buff:pack("bbbbbb", 0x01, 0x04, 0XA5, 0x5A, 0xA5, 0x5A)
TLD(buff, 0x01, magic)

-- 然后是版本号
--buff:write(string.char(0x02, 0x02, 0x00, 0x02))
TLD(buff, 0x02, string.char(0x00, 0x02))

-- head长度
buff:write(string.char(0x03, 0x04))
buff:pack("I", 0x18)

-- 文件数量
buff:write(string.char(0x04, 0x02))
buff:pack("H", #files)

-- CRC值
buff:write(string.char(0xFE, 0x02))
buff:pack("H", 0xFFFF)

for _, value in ipairs(files) do
    TLD(buff, 0x01, magic)
    local tname = value
    local data = nil
    if value:sub(-4) == ".lua" then
        tname = value .. "c"
        local func, err = loadfile(srcpath .. "\\" .. value)
        if err then
            log.error("luac", "bad lua format", err)
            os.exit(1)
        end
        -- if value == "main.lua" then
            -- data = string.dump(func)
            -- io.writeFile(tname, string.dump(func))
        -- else
            -- io.writeFile("tmp\\" .. tname, luf.dump(func, false, 0x80E0000 + buff:seek(0, zbuff.SEEK_CUR) + 3*2 + tname:len() + 4 + 2))
            -- log.info("what pos", buff:seek(0, zbuff.SEEK_CUR))
            -- log.info(">> pos", string.format("%08X", 0x080E0000 + buff:seek(0, zbuff.SEEK_CUR) + 3*2 + tname:len() + 4 + 2 + 64))
            -- data = luf.dump(func, false, 0x80E0000 + buff:seek(0, zbuff.SEEK_CUR) + 3*2 + tname:len() + 4 + 2)
            data = luf.dump(func, false, 0x080E0033)
            log.info("iowrite", tname, #data)
            io.writeFile(tname, data)
        -- end
    else
        data = io.readFile(srcpath .. "\\" .. value)
    end
    -- log.info("luadb1", tname, #data, buff:seek(0, zbuff.SEEK_CUR))
    TLD(buff, 0x02, tname)
    TLD(buff, 0x03, pack.pack("I", #data))
    TLD(buff, 0xFE, string.char(0xFF, 0xFF))
    log.info("luadb2", tname, #data, buff:seek(0, zbuff.SEEK_CUR), string.format("%02X", buff:seek(0, zbuff.SEEK_CUR)))
    -- log.info(">> pos", string.format("%08X", 0x80E0000 + buff:seek(0, zbuff.SEEK_CUR)))
    buff:write(data)
    log.info("luadb3", tname, #data, buff:seek(0, zbuff.SEEK_CUR))
end

local data = buff:toStr(0, buff:seek(0, zbuff.SEEK_CUR))
log.info("target", #data)

io.writeFile("disk.bin", data)

--print(json.encode(arg))

os.exit(0)
