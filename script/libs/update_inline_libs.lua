
local function lsdir(path, files, shortname)
    local exe = io.popen("dir /b " .. (shortname and " " or " /s ") .. path)
    if exe then
        for line in exe:lines() do
            if string.endsWith(line, ".lua") then
                table.insert(files, line)
            end
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
lsdir("core", files, true)
oscall("mkdir tmp")

local f = io.open("..\\..\\luat\\vfs\\luat_inline_libs.c", "wb")

if not f then
    os.exit("can't write luat_inline_libs.c")
end

f:write([[#include "luat_base.h"]])
f:write("\r\n")
f:write([[#include "luat_fs.h"]])
f:write("\r\n")
f:write([[#include "luat_luadb.h"]])
f:write("\r\n\r\n")


kvs = {}
for _, value in ipairs(files) do
    local lf = loadfile("core\\" .. value)
    local data = string.dump(lf, false)
    local buff = zbuff.create(256*1024)
    -- local data = io.readFile("tmp\\" .. value .. "c")
    buff:write(data)
    f:write("//------- " .. value .. "\r\n")

    local k = "luat_inline2_" .. value:sub(1, value:len() - 4)
    print(value, #data, k)
    table.insert(kvs, {size=#data,ptr=k, name=value})

    f:write("const char ".. k .."[] = {\r\n")
    local index = 0
    local max = #data
    while index < max do
        if index % 8 == 0 then
            f:write("\r\n")
        end
        f:write(string.format("0x%02X, ", buff[index]))
        index = index + 1
    end
    f:write("};\r\n\r\n")
end

f:write("const luadb_file_t luat_inline2_libs[] = {\r\n")
for _, value in ipairs(kvs) do
    f:write("   {.name=\"" .. value.name .. "\",.size=" .. tostring(value.size) .. ", .ptr=" .. value.ptr .. "},\r\n")
end
f:write("   {.name=\"\",.size=0,.ptr=NULL}\r\n")
f:write("};\r\n\r\n")
f:close()

os.exit(0)
