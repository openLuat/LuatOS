
--[[
本文件用于生成内嵌到固件里的脚本

默认是corelib目录里的全部.lua文件

如需新增或更新, 把.lua文件放入corelib目录, 在当前目录下执行:
luatos_32bit.exe update_inline_libs.lua

相关exe文件可以在 https://gitee.com/openLuat/LuatOS/attach_files 下载
]]

-- 主要配置项, lua分需要区分两种编译环境:
-- lua_Integer的大小, 受 LUA_32BITS控制, 默认是启用
-- size_t 大小, 与平台相关, MCU上通常为32bit
-- 虽然可以两两组成, 但实际情况只有2种,当前:

-- local bittype = "64bit_size32"
local bittype = "32bit"


local typename = bittype
if bittype == "32bit" then
    typename = ""
else 
    typename = "_" .. bittype
end

local function lsdir(path, files, shortname)
    local cmd = "dir /b " .. (shortname and " " or " /s ") .. path
    log.info("cmd", cmd)
    local exe = io.popen(cmd)
    if exe then
        for line in exe:lines() do
            if string.endsWith(line, ".lua") then
                log.info("found", line)
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
lsdir("corelib", files, true)
oscall("mkdir tmp")

local path = "..\\luat\\vfs\\luat_inline_libs".. typename .. ".c"
local f = io.open(path, "wb")

if not f then
    log.info("can't write", path)
    os.exit(-1)
end

f:write([[#include "luat_base.h"]])
f:write("\r\n")
f:write([[#include "luat_fs.h"]])
f:write("\r\n")
f:write([[#include "luat_luadb.h"]])
f:write("\r\n\r\n")


kvs = {}
for _, value in ipairs(files) do
    local lf = loadfile("corelib\\" .. value)
    local data = string.dump(lf, true)
    -- local cmd = 
    -- io.popen("luac_" .. bittype .. ".exe -s -o tmp.luac " .. "core\\" .. value):read("*a")
    -- local data = io.readFile("tmp.luac")
    local buff = zbuff.create(256*1024)
    -- local data = io.readFile("tmp\\" .. value .. "c")
    buff:write(data)
    f:write("//------- " .. value .. "\r\n")

    local k = "luat_inline2_" .. value:sub(1, value:len() - 4) .. typename
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

f:write("const luadb_file_t luat_inline2_libs".. typename .. "[] = {\r\n")
for _, value in ipairs(kvs) do
    f:write("   {.name=\"" .. value.name .. "\",.size=" .. tostring(value.size) .. ", .ptr=" .. value.ptr .. "},\r\n")
end
f:write("   {.name=\"\",.size=0,.ptr=NULL}\r\n")
f:write("};\r\n\r\n")
f:close()

log.info("all done")
os.exit(0)
