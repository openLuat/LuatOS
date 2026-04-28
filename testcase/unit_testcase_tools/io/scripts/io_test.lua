io_context = {}
local luatos_version, luatos_version_num, luatos_version_system = rtos.version(true)

-- 测试文件路径
local test_file_path = "/test_io.txt"

function io_context.test_open_read()
    log.info("io_context", "开始 io.open 读取模式测试")
    -- 先创建一个测试文件
    local file = io.open(test_file_path, "w")
    assert(file, "创建测试文件失败")
    file:write("Hello, LuatOS!")
    file:close()
    
    -- 测试读取模式
    local file = io.open(test_file_path, "r")
    assert(file, "打开文件失败")
    local content = file:read("*a")
    assert(content == "Hello, LuatOS!", "读取文件内容失败")
    file:close()
    log.info("io_context", "io.open 读取模式测试通过")
end

function io_context.test_open_write()
    log.info("io_context", "开始 io.open 写入模式测试")
    local file = io.open(test_file_path, "w")
    assert(file, "打开文件失败")
    local success = file:write("Test write mode")
    assert(success, "写入文件失败")
    file:close()
    
    -- 验证写入内容
    local file = io.open(test_file_path, "r")
    assert(file, "打开文件失败")
    local content = file:read("*a")
    assert(content == "Test write mode", "写入文件内容失败")
    file:close()
    log.info("io_context", "io.open 写入模式测试通过")
end

function io_context.test_open_append()
    log.info("io_context", "开始 io.open 追加模式测试")
    -- 先创建并写入初始内容
    local file = io.open(test_file_path, "w")
    assert(file, "创建文件失败")
    file:write("Test write mode")
    file:close()
    
    -- 测试追加模式
    local file = io.open(test_file_path, "a")
    assert(file, "打开文件失败")
    local success = file:write(" - appended")
    assert(success, "追加写入失败")
    file:close()
    
    -- 验证追加内容
    local file = io.open(test_file_path, "r")
    assert(file, "打开文件失败")
    local content = file:read("*a")
    log.info("io_context", "追加后文件内容:", content)
    assert(content == "Test write mode - appended", "追加写入内容失败")
    file:close()
    log.info("io_context", "io.open 追加模式测试通过")
end

function io_context.test_open_binary()
    log.info("io_context", "开始 io.open 二进制模式测试")
    local file = io.open(test_file_path, "wb")
    assert(file, "打开文件失败")
    local success = file:write(string.char(0x48, 0x65, 0x6C, 0x6C, 0x6F))
    assert(success, "二进制写入失败")
    file:close()
    
    -- 验证二进制内容
    local file = io.open(test_file_path, "rb")
    assert(file, "打开文件失败")
    local content = file:read("*a")
    assert(content == "Hello", "二进制读取内容失败")
    file:close()
    log.info("io_context", "io.open 二进制模式测试通过")
end

function io_context.test_open_invalid_mode()
    log.info("io_context", "开始 io.open 无效模式测试")
    -- 捕获错误
    local success, file = pcall(io.open, test_file_path, "invalid_mode")
    assert(not success, "无效模式应该抛出错误")
    log.info("io_context", "io.open 无效模式测试通过")
end

function io_context.test_open_nil_filename()
    log.info("io_context", "开始 io.open nil文件名测试")
    -- 捕获错误
    local success, file = pcall(io.open, nil, "r")
    assert(not success, "nil文件名应该抛出错误")
    log.info("io_context", "io.open nil文件名测试通过")
end

function io_context.test_open_number_filename()
    log.info("io_context", "开始 io.open 数字文件名测试")
    local file, err = io.open(123, "r")
    assert(file == nil, "数字文件名应该返回nil")
    assert(err ~= nil, "数字文件名应该返回错误信息")
    log.info("io_context", "io.open 数字文件名测试通过")
end

function io_context.test_file_read()
    log.info("io_context", "开始 file:read 测试")
    -- 准备测试文件
    local file = io.open(test_file_path, "w")
    assert(file, "创建测试文件失败")
    file:write("Line 1\nLine 2\nLine 3")
    file:close()
    
    -- 测试读取整行
    local file = io.open(test_file_path, "r")
    assert(file, "打开文件失败")
    local line1 = file:read("*a")
    assert(line1 == "Line 1\nLine 2\nLine 3", "读取整文件失败")
    file:close()
    
    -- 测试逐行读取
    local file = io.open(test_file_path, "r")
    assert(file, "打开文件失败")
    local line1 = file:read("*l")
    assert(line1 == "Line 1", "读取第一行失败")
    local line2 = file:read("*l")
    assert(line2 == "Line 2", "读取第二行失败")
    local line3 = file:read("*l")
    assert(line3 == "Line 3", "读取第三行失败")
    local eof = file:read("*l")
    assert(eof == nil, "读取到EOF应该返回nil")
    file:close()
    log.info("io_context", "file:read 测试通过")
end

function io_context.test_file_write()
    log.info("io_context", "开始 file:write 测试")
    local file = io.open(test_file_path, "w")
    assert(file, "打开文件失败")
    
    -- 测试写入字符串
    local success = file:write("Hello")
    assert(success, "写入字符串失败")
    
    -- 测试写入多个参数
    success = file:write(" ", "World", "!")
    assert(success, "写入多个参数失败")
    file:close()
    
    -- 验证写入内容
    local file = io.open(test_file_path, "r")
    assert(file, "打开文件失败")
    local content = file:read("*a")
    assert(content == "Hello World!", "写入内容失败")
    file:close()
    log.info("io_context", "file:write 测试通过")
end

function io_context.test_file_seek()
    log.info("io_context", "开始 file:seek 测试")
    -- 准备测试文件
    local file = io.open(test_file_path, "w")
    assert(file, "创建测试文件失败")
    file:write("0123456789")
    file:close()
    
    local file = io.open(test_file_path, "r")
    assert(file, "打开文件失败")
    
    -- 测试从开头偏移
    local pos = file:seek("set", 5)
    log.info("io_context", "seek set后位置:", pos)
    assert(pos == 5, "seek set失败")
    local char = file:read(1)
    log.info("io_context", "读取字符:", char)
    assert(char == "5", "seek后读取失败")
    
    -- 测试从当前位置偏移
    pos = file:seek("cur", 1)
    log.info("io_context", "seek cur后位置:", pos)
    assert(pos == 7, "seek cur失败")
    char = file:read(1)
    log.info("io_context", "读取字符:", char)
    assert(char == "7", "seek后读取失败")
    
    -- 测试从结尾偏移
    pos = file:seek("end", -3)
    log.info("io_context", "seek end后位置:", pos)
    assert(pos == 7, "seek end失败")
    char = file:read(1)
    log.info("io_context", "读取字符:", char)
    assert(char == "7", "seek后读取失败")
    
    -- 测试获取当前位置
    pos = file:seek()
    log.info("io_context", "当前位置:", pos)
    assert(pos == 8, "seek获取当前位置失败")
    file:close()
    log.info("io_context", "file:seek 测试通过")
end

function io_context.test_file_close()
    log.info("io_context", "开始 file:close 测试")
    local file = io.open(test_file_path, "w")
    assert(file, "打开文件失败")
    local success = file:close()
    assert(success == true, "close应该返回true")
    log.info("io_context", "file:close 测试通过")
end





function io_context.test_io_type()
    log.info("io_context", "开始 io.type 测试")
    local file = io.open(test_file_path, "w")
    assert(file, "打开文件失败")
    assert(io.type(file) == "file", "io.type应该返回'file'")
    file:close()
    assert(io.type(file) == "closed file", "io.type应该返回'closed file'")
    assert(io.type("not a file") == nil, "io.type非文件应该返回nil")
    assert(io.type(123) == nil, "io.type数字应该返回nil")
    assert(io.type(nil) == nil, "io.type nil应该返回nil")
    log.info("io_context", "io.type 测试通过")
end

function io_context.test_io_lines()
    log.info("io_context", "开始 io.lines 测试")
    -- 准备测试文件
    local file = io.open(test_file_path, "w")
    assert(file, "创建测试文件失败")
    file:write("Line 1\nLine 2\nLine 3")
    file:close()
    
    local lines = {}
    for line in io.lines(test_file_path) do
        table.insert(lines, line)
    end
    assert(#lines == 3, "io.lines应该返回3行")
    assert(lines[1] == "Line 1", "第一行内容错误")
    assert(lines[2] == "Line 2", "第二行内容错误")
    assert(lines[3] == "Line 3", "第三行内容错误")
    log.info("io_context", "io.lines 测试通过")
end





-- 清理测试文件
function io_context.cleanup()
    os.remove(test_file_path)
    os.remove("/test_io2.txt")
end

return io_context