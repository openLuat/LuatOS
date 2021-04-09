
local function lsdir(path, files, shortname)
    local exe = io.popen("dir /b " .. (shortname and " " or " /s ") .. path)
    if exe then
        for line in exe:lines() do
            table.insert(files, line)
        end
        exe:close()
    end
end

function TLD(buff, T, D)
    buff:pack("bb", T, D:len())
    buff:write(D)
end

local files = {}
lsdir("lib", files, true)

local buff = zbuff.create(256*1024)
local magic = string.char(0XA5, 0x5A, 0xA5, 0x5A)

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
    TLD(buff, 0x02, value)
    --TLD(buff, 0x03, pack.pack("I", io.fileSize("lib\\" .. value)))
    TLD(buff, 0xFE, string.char(0xFF, 0xFF))
    --buff:write(io.readFile("lib\\" .. value))
end

os.exit(0)
