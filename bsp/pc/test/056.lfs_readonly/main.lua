

local path = "/lfs2/abc.txt"
io.writeFile(path, "ABC")

print("测试前的数据", io.readFile(path))
local f = io.open(path, "rb")
if f then
    f:write("DFEF")
    f:close()
end

print("测试后的数据", io.readFile(path))