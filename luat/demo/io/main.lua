PROJECT = "io"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

_G.sys = require("sys")



if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end


-- Lua IO 操作测试 Demo
log.info("io_test", "开始测试IO模块功能")

-- 1. 测试文件存在性检查
local testFile = "/test_io_demo.txt"
if io.exists(testFile) then
    log.info("io_test", "测试文件已存在，将被删除")
    os.remove(testFile)
end

-- 2. 测试文件写入
local writeSuccess = io.writeFile(testFile, "这是第一行数据1\n第二行数据12\n第三行数据123")
if writeSuccess then
    log.info("io_test", "文件写入成功")
else
    log.error("io_test", "文件写入失败")
    return
end

-- 3. 测试文件存在性检查
log.info("io_test", "文件存在检查:", io.exists(testFile))

-- 4. 测试获取文件大小
local fileSize = io.fileSize(testFile)
log.info("io_test", "文件大小:", fileSize)

-- 5. 测试读取整个文件
local fileContent = io.readFile(testFile)
log.info("io_test", "文件内容:", fileContent)

-- 6. 测试部分读取文件
local partialContent = io.readFile(testFile, "rb", 10, 5)
log.info("io_test", "部分文件内容(偏移10,长度5):", partialContent)

-- 7. 测试文件操作API
local fd = io.open(testFile, "rb")
if fd then
    log.info("io_test", "文件打开成功")
    
    -- 测试读取
    local firstLine = fd:read("*l")
    log.info("io_test", "第一行内容:", firstLine)
    -- 测试seek
    -- fd:seek(1024, io.SEEK_SET)
    local first5Bytes = fd:read(5)
    log.info("io_test", "前5字节:", first5Bytes)
    
    -- 测试写入(需要重新以写入模式打开)
    fd:close()
    fd = io.open(testFile, "ab")
    if fd then
        fd:write("\n追加的数据")
        fd:close()
        log.info("io_test", "数据追加成功")
    end
end
    
-- 8. 测试目录操作
local testDir = "/test_dir"
log.info("io_test", "创建目录:", io.mkdir(testDir))
log.info("io_test", "目录存在:", io.exists(testDir))

-- 在目录中创建几个测试文件
io.writeFile(testDir.."/file1.txt", "测试文件1")
io.writeFile(testDir.."/file2.txt", "测试文件2")
io.writeFile(testDir.."/file3.txt", "测试文件3")

-- 9. 测试列出目录
local success, dirList = io.lsdir(testDir, 10, 0)
if success then
    log.info("io_test", "目录列表:", json.encode(dirList))
else
    log.error("io_test", "获取目录列表失败:", dirList)
end

-- 10. 测试挂载点列表
local mountPoints = io.lsmount()
log.info("io_test", "挂载点列表:", json.encode(mountPoints))

-- 11. 测试删除目录
log.info("io_test", "删除目录:", io.rmdir(testDir))
log.info("io_test", "目录删除后存在:", io.exists(testDir))

-- 12. 测试文件系统格式化(通常不执行，因为会清空数据)
--[[
local formatOk, err = io.mkfs("/sd")
log.info("io_test", "格式化文件系统:", formatOk, err)
]]

-- 清理测试文件
os.remove(testFile)
log.info("io_test", "测试完成，已清理测试文件")

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!