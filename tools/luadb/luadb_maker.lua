--[[
luadb maker, for script.bin

-- 使用说明
1. 需要打包的文件存放到  disk 目录
2. 用luatos.exe luadb_maker.lua 执行本脚本
3. 然后就会生成script.bin

-- 工作流程
1. 遍历disk目录,得到列表
2. 对.lua文件进行luac编译
3. 按luadb格式合成文件

运行所需要的程序:
1. luatos.exe, 可通过bsp/win32编译, 也可以从github action获取现成的
2. luac536.exe 与原版luac.exe的区别是启用了 `#define LUA_32BITS`
]]

-- 存放脚本和其他资源文件的目录,不能带子文件夹
script_dir = "disk"
-- 是否保留全部
debug_all = false

-- 遍历文件, io.lsdir应该也行
local function lsdir(path, files, shortname)
    local exe = io.popen("dir /b " .. (shortname and " " or " /s ") .. path)
    if exe then
        for line in exe:lines() do
            table.insert(files, line)
        end
        exe:close()
    end
end

-- 封装一下调用本地程序的逻辑
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

-- TLD格式打包, Tag - Len - data
function TLD(buff, T, D)
    buff:pack("bb", T, D:len())
    buff:write(D)
end

-----------------------
--- 开始正式的逻辑
-----------------------

-- 获取disk目录下的全部文件列表
local files = {}
lsdir(script_dir, files, true)
oscall("mkdir tmp")

-- 创建所需的缓冲区
local buff = zbuff.create(1024*1024)
local magic = string.char(0x5A, 0xA5, 0X5A, 0xA5)

-- 先写入magic
--buff:pack("bbbbbb", 0x01, 0x04, 0XA5, 0x5A, 0xA5, 0x5A)
TLD(buff, 0x01, magic)

-- 然后是版本号, 当前是2
--buff:write(string.char(0x02, 0x02, 0x00, 0x02))
TLD(buff, 0x02, string.char(0x00, 0x02))

-- head长度,固定长度
buff:write(string.char(0x03, 0x04))
buff:pack("I", 0x12)

-- 文件数量, 按实际情况的
buff:write(string.char(0x04, 0x02))
buff:pack("H", #files)

-- CRC值, 虽然有,但实际不校验
buff:write(string.char(0xFE, 0x02))
buff:pack("H", 0xFFFF)

-- 如果是lua文件,转luac,然后添加
-- 如果是其他文件,直接添加
for _, value in ipairs(files) do
    TLD(buff, 0x01, magic)
    if value:endsWith(".lua") then
        TLD(buff, 0x02, value .. "c")
        -- 内置的dump也能用. 不过得考虑size_t和32bit是否启用的问题
        -- local lf = loadfile(script_dir .. "\\" .. value)
        -- local data = string.dump(lf, value == "main.lua" or debug_all)
        io.popen("luac536.exe -s -o tmp.luac " .. script_dir .. "\\" .. value):read("*a")
        local data = io.readFile("tmp.luac")
        TLD(buff, 0x03, pack.pack("I", #data))
        TLD(buff, 0xFE, string.char(0xFF, 0xFF))
        buff:write(data)
    else
        TLD(buff, 0x02, value)
        TLD(buff, 0x03, io.fileSize(script_dir .. "\\" .. value))
        TLD(buff, 0xFE, string.char(0xFF, 0xFF))
        buff:write(io.readFile( script_dir .. "\\" .. value))
    end
end

-- 最后获取全部数据
local data = buff:toStr(0, buff:seek(0, zbuff.SEEK_CUR))
log.info("target size", #data)

-- 写入目标文件
io.writeFile("script.bin", data)

-- 收工
os.exit(0)
