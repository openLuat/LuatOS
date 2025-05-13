require "fs_test_utils"

--[[
用例0101 测试文件创建、打开、关闭与删除
]]--
function tc0101_file_operation(pathto)
    local filename = "tc101_data.txt"
    --打开文件，若不存在则创建；
    local file = io.open(pathto .. filename, "w+")
    assert(file ~= nil, "Should not creat file")
    if file then
        -- 检查文件打开状态
        local rc = io.type(file)
        --log.info("fs", "io.type: ", "rc")
        assert(rc == "file", "Should be the opened file")
        file:close()

        -- 关闭文件，可以获取文件关闭状态
        rc = file:__tostring()
        --log.info("fs", "io.type: ", "rc")
        assert(string.find(rc, "closed") ~= nil, "Should be the closed file")
        rc = io.type(file)
        assert(string.find(rc, "closed") ~= nil, "Should be the closed file")
    end

    --重复打开同一文件，会返回不同的文件句柄
    local file1 = io.open(pathto .. filename, "r+")
    assert(file1 ~= nil, "Failed to open file in in \"r+\" mode")
    local file2 = io.open(pathto .. filename, "a+")
    assert(file2 ~= nil, "Should not reopen the same file in \"a+\" mode")
    file1:close()
    file2:close()

    -- 删除文件
    local ret, err = os.remove(pathto .. filename)
    assert(ret ~= nil and ret == true, "Remove file failed")
    -- 查询文件不存在则文件删除成功
    ret = io.exists(pathto .. filename)
    assert(ret == false, "Should not exist file")
end

--[[
用例0102 测试文件系统创建与删除目录
]]--
function tc0102_directory_operation(pathto)
    local dirname = "tc102_dir"
    -- 判断目录是否存在
    local rc = check_dir_exist(pathto, dirname)
    local success, err = 0, 0
    if rc == 0 then 
        -- 创建一个新目录
        success, err = io.mkdir(pathto .. dirname .. "/")
        assert(success, "Failed to create directory: " .. tostring(err))
        rc = check_dir_exist(pathto, dirname)
        assert(rc == 1, "Not exist directory")
    end

    -- 删除创建的目录
    success, err = io.rmdir(pathto .. dirname .. "/")
    assert(success, "Failed to remove directory: " .. tostring(err))
    
    -- 验证目录是否被成功删除
    rc = check_dir_exist(pathto, dirname)
    assert(rc == 0, "Directory should be removed")
end

--[[
用例0103 测试打开文件写入数据功能(标准库接口)
]]--
function tc0103_file_writedata_std(pathto)
    local file = "tc103_file_01.txt"
    local testdata = "Test contents:\n123456\n"
    -- 写模式创建/打开文件，标准库io接口写入数据
    local fdw = io.open(pathto .. file, "w")
    if fdw then
        -- 标准库io接口写入数据
        fdw:write(testdata)
        fdw:close()
    end
    -- 只读模式打开文件
    local fdr = io.open(pathto .. file, "r")
    assert(fdr ~= nil, "Cannot open file")
    if fdr then
        -- 标准库io接口读取全部数据
        local readdata = fdr:read("*a")
        fdr:close()
        -- 比较读取数据和测试数据是否一致
        assert(readdata == testdata, "Read data should be as same as Test data")
    end
    -- 清理工作
    if pathto == "/ram/" then 
        -- 对于/ram/ 测试完删除文件，因为ram文件系统最大允许文件数为8个超过就无法新建文件
        os.remove(pathto .. file)
    end
end

--[[
用例0104 测试打开文件写入数据功能(扩展库接口)
]]--
function tc0104_file_writedata_ext(pathto)
    local file = "tc104_file.txt"
    local testdata = "Test contents:\n123456\n"
    -- 通过luatos扩展io库接口来直接向文件写入数据
    local rc = io.writeFile(pathto .. file, testdata)
    assert(rc, "Cannot Write file")
    -- 只读模式打开文件
    local fdr = io.open(pathto .. file, "r")
    assert(fdr ~= nil, "Cannot open file")
    if fdr then
        -- 标准库io接口读取全部数据
        local readdata = fdr:read("*a")
        fdr:close()
        -- 比较读取数据和测试数据是否一致
        assert(readdata == testdata, "Read data should be as same as Test data")
    end
    -- 清理工作
    if pathto == "/ram/" then 
        -- 对于/ram/ 测试完删除文件，因为ram文件系统最大允许文件数为8个超过就无法新建文件
        os.remove(pathto .. file)
    end
end

--[[
用例0105 测试打开文件读取数据功能(扩展库接口)
]]--
function tc0105_file_readdata_ext(pathto)
    local filename = "tc105_file.txt"
    local testdata = "Test contents:\r\n12345\r\n"
    local fdw = io.open(pathto .. filename, "w+")
    if fdw then
        -- 标准库io接口写入数据
        fdw:write(testdata)
        fdw:close()
    end
    -- 若"/luadb/"则直接指定测试文件
    if pathto == "/luadb/" then
        filename = "test_fewline.txt" -- same as testdata
    end
    -- 通过luatos扩展io库接口io.readFile读取数据,从0位置开始读指定长度大小
    local readdata = io.readFile(pathto .. filename, "r", 0, #testdata)
    log.info("fs", "read data ", readdata)
    assert(readdata == testdata, "Read data is not as same as Test data")

    -- 清理工作
    if pathto == "/ram/" then 
        -- 对于/ram/ 测试完删除文件，因为ram文件系统最大允许文件数为8个超过就无法新建文件
        os.remove(pathto .. filename)
    end
end

--[[
用例0106 测试打开文件读取数据功能(标准库接口)
]]--
function tc0106_file_readdata_std(pathto)
    local filename = "tc106_file.txt"
    local testdata = "Test contents:\r\n12345\r\n"
    local fdw = io.open(pathto .. filename, "w+")
    if fdw then
        -- 标准库io接口写入数据
        fdw:write(testdata)
        fdw:close()
    end

    -- 若"/luadb/"则直接指定测试文件
    if pathto == "/luadb/" then
        filename = "test_fewline.txt" -- same as testdata
    end
    -- 只读模式打开文件，通过标准io库接口file:read方式读取数据
    local fdr = io.open(pathto .. filename, "r")
    if fdr then
        local readdata = fdr:read(1)
        log.info("fs", "read data", readdata)
        while true do
            -- 循环按指定字节数读取，读取不到就退出循环
            local data = fdr:read(10)
            if not data or #data == 0 then
                break
            end
            log.info("fs", "read data", data)
            readdata = readdata .. data
        end
        fdr:close()
        assert(readdata == testdata, "Read data != Test data")
    end
    -- 只读模式打开文件，通过标准io库接口file:read方式读取数据
    fdr = io.open(pathto .. filename, "r")
    --assert(fdr ~= nil, "Cannot open file")
    if fdr then
        local content = {}
        while true do
            -- 循环按行方式读取，读取不到就退出循环
            local line = fdr:read() -- 不带参数即默认与fdr:read("l")方式一致
            if not line or #line == 0 then
                break
            end
            log.info("fs", "read line", line)
            table.insert(content, line)
        end
        fdr:close()
        assert(#content == 2, "Should be two lines")
        assert(content[1] == "Test contents:\r", "Should be first line")
        assert(content[2] == "12345\r", "Should be second line")
    end
    -- 只读模式打开文件，通过标准io库接口file:read方式读取数据
    fdr = io.open(pathto .. filename, "r")
    --assert(fdr ~= nil, "Cannot open file")
    if fdr then
        local content = {}
        -- 标准库io接口按行方式获取数据
        for line in fdr:lines() do
            log.info("fs", "read line", line)
            table.insert(content, line)
        end
        fdr:close()
        assert(#content == 2, "Should be two lines")
        assert(content[1] == "Test contents:\r", "Not the first line")
        assert(content[2] == "12345\r", "Not the second line")
    end
    -- 通过标准io库接口io.lines按行方式读取
    local lines = io.lines(pathto .. filename) --相当于io.lines(pathto .. filename, "l")
    local content = {}
    for line in lines do
        log.info("fs", "read line ", line)
        table.insert(content, line)
    end
    assert(#content == 2, "Should be two lines")
    assert(content[1] == "Test contents:\r", "Should be first line")
    assert(content[2] == "12345\r", "Should be second line")
end

--[[
用例0107 测试打开文件写入数据的截断与追加功能
]]--
function tc0107_file_write_trunc_append(pathto)
    local filename = "tc107_file.txt"
    local file_path = pathto .. filename
    -- 测试前先删掉之前的测试文件(若存在)
    if io.exists(file_path) then
        os.remove(file_path)
    end
    -- 创建新文件并写入初始内容
    local file = io.open(file_path, "w+")
    --assert(fdr ~= nil, "Cannot open file")
    if file then
        file:write("Initial content\n")
        file:close()
        -- 使用写模式打开文件,截断文件
        file = io.open(file_path, "w+")
        file:write("Truncated content\n")
        file:close()
        -- 从文件末尾追加内容
        file = io.open(file_path, "a")
        file:write("Appended content\n")
        file:close()
        -- 读取文件内容并验证
        file = io.open(file_path, "r")
        local content = file:read("*a")
        file:close()
        log.info("fs", "data: ", content)
        assert(content == "Truncated content\nAppended content\n", "Content should match after truncation and append")
    end
    -- 清理工作
    if pathto == "/ram/" then 
        -- 对于/ram/ 测试完删除文件，因为ram文件系统最大允许文件数为8个超过就无法新建文件
        os.remove(pathto .. filename)
    end
end

--[[
用例0108 测试文件指针偏移时写入数据立即读取数据功能
]]--
function tc0108_file_pointer_readwrite(pathto)
    local filename = "tc108_file.txt"
    local file = io.open(pathto .. filename, "w+")
    file:write("Hello, World!")
    -- 设置文件指针到文件开始偏移7字节的位置
    file:seek("set", 7)
    -- 读取完2字节，文件指针也向后偏移2
    local content = file:read(2)
    log.info("fs", "content: ", content)
    assert(content == "Wo", "Read data wrong")
    -- 获取当前文件指针位置
    local cur_pos = file:seek() -- 等同于file:seek("cur")
    assert(cur_pos == 9, "File pointer should be at the offset 9 not " .. tostring(cur_pos))
    -- 设定为"end",offset为-2(回退2)，获取文件指针
    local end_pos = file:seek("end", -2) -- 倒数第2的位置
    assert(end_pos == 11, "File pointer should be at the offset 11 not " .. tostring(end_pos))
    -- 设置文件指针到开始的位置
    file:seek("set", 0)
    content = file:read("*a")
    -- 读取完，文件指针已到文件尾,相当于获取文件大小
    local pos = file:seek()
    file:close()
    log.info("fs", "content: ", content)
    assert(pos == 13, "File pointer should be at the end after read")
end

--[[
用例0109 测试文件写入读取Bin数据
]]--
function tc0109_file_write_read_bindata(pathto)
    local filename = "tc109_data.bin"
    -- 若路径为luadb，仅测试读取该路径下test_fewdata.bin数据
    if pathto == "/luadb/" then
        filename = "/luadb/test_fewdata.bin"
        local dst_bindata = "\x00\xAA\xBB\xCC\xDD\xEE\xFF\x13\x46\x80\x12\x34\x56\x78\x90\x00"
        -- 扩展接口读取二进制数据
        local readdata2 = io.readFile(pathto .. filename, "r", 0, #dst_bindata)
        assert(readdata2 == dst_bindata, "Read data != Test data")
    else
        -- 准备二进制数据
        local binaryData1 = string.char(0, 1, 2, 255, 254)
        local binaryData2 = "\x12\x34\x56\78\90\xAB\xCD\xEF"
        --log.info("fs", "data1:" .. string.toHex(binaryData1))
        --log.info("fs", "data1+data2:" .. string.toHex(binaryData1 .. binaryData2))
        -- 扩展接口写入二进制数据
        local rc = io.writeFile(pathto .. filename, binaryData1)
        assert(rc, "Write Bin File Error")
        -- 标准库接口：读取二进制数据
        local file = io.open(pathto .. filename, "rb")
        assert(file, "Failed to open file for reading")
        local readData = file:read("*a")
        file:close()
        assert(readData == binaryData1, "Read data != written data")
        -- 标准库接口：追加写入二进制数据
        local file = io.open(pathto .. filename, "ab")
        assert(file ~= nil, "Failed to open file for writing")
        file:write(binaryData2)
        file:close()
        -- 扩展接口读取二进制数据
        local readdata2 = io.readFile(pathto .. filename, "r", 0, #binaryData1 + #binaryData2)
        assert(readdata2 == binaryData1 .. binaryData2, "Read data != Test data")
        -- 清理工作
        if pathto == "/ram/" then 
            -- 对于/ram/ 测试完删除文件，因为ram文件系统最大允许文件数为8个超过就无法新建文件
            os.remove(pathto .. filename)
        end
    end
end


--[[
用例0110 测试文件重命名并写入读取数据
]]--
function tc0110_file_rename_readwrite(pathto)
    local filename = "tc110_file.txt"
    local filename_chg = "tc110_file_new.txt"
    local testdata = "Test contents:\n123456\n"
    local chg_data = "Hello\n123"

    local file = io.open(pathto .. filename, "w+")
    assert(file ~= nil, "Failed to open file for writing")
    file:write(testdata)
    file:close()
    -- 文件重命名
    os.rename(pathto .. filename, pathto .. filename_chg)
    assert(io.exists(pathto .. filename) == false, "Should not exit file")
    -- 扩展接口读取数据，文件内容不变
    local readdata = io.readFile(pathto .. filename_chg, "r", 0, #testdata)
    assert(readdata == testdata, "Read data should be as same as Test data")
    -- 打开重命名的文件写入新数据(截断文件)
    file = io.open(pathto .. filename_chg, "w")
    if file then
        file:write(chg_data)
        file:close()
    end

    -- 扩展接口读取数据
    log.info("fs", "chg data:" .. chg_data)
    readdata = io.readFile(pathto .. filename_chg, "r", 0, #chg_data)
    log.info("fs", "data:" .. readdata)
    assert(readdata == chg_data, "Read data should be as same as Test data")
end

--[[
用例0111 测试查询文件大小
]]--
function tc0111_file_size(pathto)
    local filename = "tc111_file.txt"
    local testdata = "Test contents:\r\n12345\r\n"
    local fdw = io.open(pathto .. filename, "w")
    if fdw then
        fdw:write(testdata)
        fdw:close()
    end
    -- 若"/luadb/"则直接指定测试文件
    if pathto == "/luadb/" then
        filename = "test_fewline.txt" -- same as testdata
    end
    -- 验证文件长度大小, 有三种方法可以获取的文件长度
    local filelen1 = io.fileSize(pathto .. filename)
    local filelen2 = fs.fsize(pathto .. filename)
    local filelen3 = get_size_from_lsdir(pathto, filename, io.FILE)
    log.info("fs", "filelen1: ", filelen1)
    log.info("fs", "filelen2: ", filelen2)
    log.info("fs", "filelen3: ", filelen3)
    assert((filelen1 == #testdata 
            and filelen2 == #testdata 
            and filelen3 == #testdata), 
            "Read lengths are not equal " .. #testdata)
    -- 若"/luadb/"则测试到这个地方结束        
    if pathto == "/luadb/" then return end
    
    -- 继续追加写入数据，检查文件大小变化
    fdw = io.open(pathto .. filename, "a+")
    if fdw then
        fdw:write(testdata)
        fdw:close()
    end
    filelen1 = io.fileSize(pathto .. filename)
    filelen2 = fs.fsize(pathto .. filename)
    filelen3 = get_size_from_lsdir(pathto, filename, io.FILE)
    log.info("fs", "filelen1: ", filelen1)
    log.info("fs", "filelen2: ", filelen2)
    log.info("fs", "filelen3: ", filelen3)
    assert((filelen1 == #testdata * 2
            and filelen2 == #testdata * 2
            and filelen3 == #testdata * 2), 
            "Read lengths are not equal")  
end

--[[
用例0112 测试查询目录大小
]]--
function tc0112_directory_size(pathto)
    -- 验证目录大小
    local dirname01 = "tc112_dir_01"
    local dirname02 = "tc112_dir_02"
    local filename = "tc112_file.txt"
    local success, err = 0, 0
    --log.info("fsstat: " .. pathto, fs.fsstat(pathto))
    -- 创建一个新目录
    success, err = io.mkdir(pathto .. dirname01 .. "/")
    assert(success, "Failed to create dir: " .. tostring(err))
    success, err = io.mkdir(pathto .. dirname02 .. "/")
    assert(success, "Failed to create dir: " .. tostring(err))
    -- 在其中一个新目录创建文件
    local rc = io.writeFile(pathto .. dirname01 .. "/" .. filename, "Hello1234\n")
    assert(rc, "Write File Error")
    local rc, data = io.lsdir(pathto .. dirname01 .. "/", 10, 0)
    if rc then
        log.info("fs", "ls " .. pathto .. dirname01 .. "/", json.encode(data))
    end
    log.info("fsstat: " .. pathto, fs.fsstat(pathto))
    -- 获取目录大小(目录占用空间而不是整个目录的文件大小)
    local size1 = get_size_from_lsdir(pathto, dirname01, io.DIR)
    local size2 = get_size_from_lsdir(pathto, dirname02, io.DIR)
    -- 清理工作 先删除文件,非空目录才能删除
    os.remove(pathto .. dirname01 .. "/" .. filename)
    -- 清理工作 删除创建的目录
    success, err = io.rmdir(pathto .. dirname01 .. "/")
    assert(success, "Failed to remove dir: " .. tostring(err))
    success, err = io.rmdir(pathto .. dirname02 .. "/")
    assert(success, "Failed to remove dir: " .. tostring(err))
    -- 判断结果 当前返回的DIR size都为0？
    log.info("fs", pathto .. dirname01 .. "/" .. "  dir size: " .. size1)
    log.info("fs", pathto .. dirname02 .. "/" .. "  dir size: " .. size2)
    assert(size1 == 0, "Reture dir size is " .. tostring(size1)) 
    assert(size2 == 0, "Reture dir size is " .. tostring(size2))    
end


--[[
用例0113 测试查询文件系统信息
]]--
function tc0113_filesystem_info(pathto)
    -- 获取所有文件系统挂载信息
    local data = io.lsmount()
    log.info("fs", "lsmount", json.encode(data))
    -- 获取指定文件系统信息
    log.info("fsstat: " .. pathto, fs.fsstat(pathto))

    if pathto ~= "/luadb/" then
        -- 在目录下新建文件
        local filename = "tc113_file.txt"
        generate_file(pathto, filename)
        log.info("fsstat: " .. pathto, fs.fsstat(pathto))
        if pathto == "/" then -- 测试lfs时支持目录
            local dirname = "tc113_dir"
            generate_directory(pathto, dirname)
            -- 在新建目录里创建文件
            generate_file(pathto .. dirname .. "/", filename)
            -- 获取新建目录的目录信息
            local rc, data1 = io.lsdir(pathto .. dirname .. "/", 10, 0)
            log.info("fs", "ls " .. pathto .. dirname .. "/", json.encode(data1))
        end
    end
    -- 获取文件系统目录信息
    local rc, data1 = io.lsdir(pathto, 10, 0)
    log.info("fs", "ls " .. pathto, json.encode(data1))
end

--[[
用例0114 文件系统格式化
]]--
function tc0114_filesystem_format(pathto)
    --log.info("fsstat: " .. pathto, fs.fsstat(pathto))
    -- 创建一个新的空目录
    local success, err = io.mkdir(pathto .. "tc114_dir")
    assert(success, "Failed to create directory: " .. pathto .. "tc114_dir" .. tostring(err))
    -- 创建一个新的空文件
    local fd = io.open(pathto .. "tc114_file.txt", "w+")
    if fd then fd:close() end
    local rc, data = io.lsdir(pathto, 10, 0)
    log.info("fs", "ls " .. pathto, json.encode(data))
    --log.info("fs", "table len=", #data)
    -- 指定挂载路径，文件系统格式化
    local rc, err = io.mkfs(pathto)
    assert(rc, "FS format error")
    log.info("fsstat: " .. pathto, fs.fsstat(pathto))
    -- 格式化后 挂载目录下无目录和文件
    rc, data = io.lsdir(pathto, 10, 0)
    --log.info("fs", "ls " .. pathto, json.encode(data))
    --log.info("fs", "table len=", #data)
    assert(#data == 0, "root dir not empty")
end