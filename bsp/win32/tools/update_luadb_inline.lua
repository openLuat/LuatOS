
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
lsdir("lib", files, true)
oscall("mkdir tmp")

local buff = zbuff.create(256*1024)
local magic = string.char(0x5A, 0xA5, 0X5A, 0xA5)

-- 先写入magic
--buff:pack("bbbbbb", 0x01, 0x04, 0XA5, 0x5A, 0xA5, 0x5A)
TLD(buff, 0x01, magic)

-- 然后是版本号
--buff:write(string.char(0x02, 0x02, 0x00, 0x02))
TLD(buff, 0x02, string.char(0x00, 0x02))

-- head长度
buff:write(string.char(0x03, 0x04))
buff:pack("I", 0x12)

-- 文件数量
buff:write(string.char(0x04, 0x02))
buff:pack("H", #files)

-- CRC值
buff:write(string.char(0xFE, 0x02))
buff:pack("H", 0xFFFF)

for _, value in ipairs(files) do
    TLD(buff, 0x01, magic)
    TLD(buff, 0x02, value .. "c")
    oscall("..\\air640w\\tools\\luac_536_32bits.exe -s -o tmp\\".. value .. "c lib\\" .. value)
    TLD(buff, 0x03, pack.pack("I", io.fileSize("tmp\\" .. value .. "c")))
    TLD(buff, 0xFE, string.char(0xFF, 0xFF))
    buff:write(io.readFile("tmp\\" .. value .. "c"))
end

local data = buff:toStr(0, buff:seek(0, zbuff.SEEK_CUR))
log.info("target", #data)

local f = io.open("..\\..\\luat\\vfs\\luat_luadb_inline.c", "wb")
if f then
    f:write([[#include "luat_base.h"]])
    f:write("\n\nconst char luadb_inline[] = {\n")
    local index = 0
    local max = #data
    while index < max do
        if index % 8 == 0 then
            f:write("\n")
        end
        f:write(string.format("0x%02X, ", buff[index]))
        index = index + 1
    end
    f:write("};\n")
    f:close()
end

os.exit(0)
