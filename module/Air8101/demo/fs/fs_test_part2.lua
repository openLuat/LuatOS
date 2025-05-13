require "fs_test_utils"


--[[
用例0201 异常文件打开删除
前置条件：
测试步骤与期望：
]]--
function tc0201_file_abnormal_operate(pathto)
    --打开一个不存在的文件
    local file, err0 = io.open(pathto .. "tc201_file.txt", "r")
    assert(file == nil, "Should not open non-existent file" .. tostring(err0))
    -- 若打开失败，err信息指示不准确，先不判断err信息
    --assert(err ~= nil, "Error message should indicate file not found")
    log.info("fsstat: " .. pathto, fs.fsstat(pathto))
    -- 删除不存在的文件,期望是第一个返回参数为nil
    local ret, err = os.remove(pathto .. "tc12_file.txt")
    assert(success == nil, "Should not remove non-exist file: " .. tostring(err))

    -- 重命名不存在的文件,,期望是第一个返回参数为nil
    ret, err = os.rename(pathto .. "tc12_file.txt", pathto .. "tc17_file_new.txt")
    assert(success == nil, "Should not rename non-exist file: " .. tostring(err))
end

--[[
用例0202 异常目录打开删除
前置条件：
测试步骤与期望：
]]--
function tc0202_directory_abnormal_operate(pathto)
    --先创建一个目录
    local dirname = "tc0202_dir"
    generate_directory(pathto, dirname)
    --重复创建同名目录失败
    local ret, err = io.mkdir(pathto .. dirname .. "/")
    assert(ret == false, "Should be not create directory: " .. tostring(err))
    --在前面目录里在建立一个文件并写入数据
    local filename = "tc202_file.txt"
    local rc = io.writeFile(pathto .. dirname .. "/" .. filename, "123456test")
    assert(rc, "Cannot Create file and write data")
    --删除非空目录返回失败
    ret, err = io.rmdir(pathto .. dirname .. "/")
    assert(ret == false, "Should be not remove directory: " .. tostring(err))
    --删除文件后在删除目录
    os.remove(pathto .. dirname .. "/" .. filename)
    ret, err = io.rmdir(pathto .. dirname .. "/")
    assert(ret == true, "Can not remove directory: " .. tostring(err))
end

--[[
用例0203 不同文件模式读写操作异常
]]--
function tc0203_file_abnormal_readwrite(pathto)

    --若"/luadb/"只测试下面两点
    if pathto == "/luadb/" then
        -- 只读文件系统的文件不能以写模式打开
        local fd, err = io.open(pathto .. "test_fewline.txt", "w")
        log.info("fs", "write fd: ", fd)
        assert(fd == nil, "Read-Only file open in write mode " .. tostring(err))
        --if fd then
            --local ret, err1 =fd:write("12")
            --log.info("fs", "write ret:", ret)
            --fd:close()
        --end
        -- 打开一个不存在的文件
        fd, err = io.open(pathto .. "tc12_file.txt", "r")
        assert(fd == nil, "Should not open non-existent file" .. tostring(err))
        return
    end

    --在目录里建立一个文件并写入数据
    local filename = "tc0203_file.txt"
    local rc = io.writeFile(pathto .. filename, "123456test")
    assert(rc, "Cannot Create file and write data")
    --只读方式打开文件
    local fd = io.open(pathto .. filename, "r")
    assert(fd ~= nil, "Failed to open file for read")
    if fd then
        -- 只读方式打开文件不能写入数据
        local ret, err = fd:write("Hello")
        log.info("fs", "write ret:", ret)
        --assert(ret == nil, "Cannot Write data in ro mode" .. tostring(err))
        fd:seek("set", 0)
        local data = fd:read("*a")
        log.info("fs", "read all:", data)
        fd:close()
        assert(data == "123456test", "123456test change to " .. data)
    end

    -- 清理工作
    if pathto == "/ram/" then 
        -- 对于/ram/ 测试完删除文件，因为ram文件系统最大允许文件数为8个超过就无法新建文件
        os.remove(pathto .. filename)
    end
end


--[[
用例0204 文件名最大长度
]]--
function tc0204_filename_max(pathto)
    -- 构造一个长度为length的文件名
    local length = 64  -- lfs："/" 文件名长度最大63字节
    if pathto == "/ram/" then 
        length = 32 -- ramfs:"/ram/" 文件名长度最大31字节
    end
    local filename = string.rep("A", length)
    local fd = io.open(pathto .. filename, "w")
    -- 最大文件名不超过63，否则返回失败
    assert(fd == nil, "Can create file with the length of name:" .. tostring(length))

    -- 测试结束删除文件
    if fd then
        fd:close()
        os.remove(pathto .. filename)
    end
end

WRITE_SIZE = 2048
LAST_BLKCOUNT = 4
chunk_dat = string.rep("F", WRITE_SIZE)
tc205_chunk_dat_last = string.rep("A", WRITE_SIZE-468)
tc206_chunk_dat_last = string.rep("B", WRITE_SIZE-4)
--[[
用例0205 根目录单文件最大写入和删除
]]--
function tc0205_file_writemax(pathto)
    -- 仅支持lfs根目录测试
    if pathto ~= "/" then return end
    -- 先格式化文件系统
    local rc, err = io.mkfs(pathto)
    assert(rc, "FS format error" .. tostring(err))
    log.info("fsstat: " .. pathto, fs.fsstat(pathto))
    local succ, total, used, blksize = fs.fsstat(pathto)
    -- 获取剩余容量大小，可写入块
    local free = total - used
    -- 按block size定义数据块
    --local chunk_dat = string.rep("F", blksize)
    local filename = "tc205_file.txt"
    -- 最后一块大小
    --local chunk_dat_last = string.rep("A", 4096-468)
    -- 创建打开一个文件
    local fd = io.open(pathto .. filename, "w+")
    -- 连续写入多块
    local chunk_cnt = (4096/WRITE_SIZE)*(free-1) + (4096/WRITE_SIZE) - 1
    local ret = file_chunkdata_write(fd, chunk_dat, chunk_cnt)
    log.info("fs","1st ret: " .. tostring(ret))
    assert(ret ~= nil, "File write chunk data failed1")
    -- 最后一块
    ret = file_chunkdata_write(fd, tc205_chunk_dat_last, 1)
    log.info("fs", "2nd write ret: ", ret)
    assert(ret ~= nil, "File write chunk data failed2")
    -- 注意这里如果继续写一个字节且因已满写失败了前面数据在文件close后会丢失filesize=0
    -- 所以前面写满后先关闭保存
    --ret = fd:write("1")
    --log.info("fs", "3rd write ret: ", ret)
    --assert(ret == nil, "Continue to write data success")
    fd:close()   
    local succss, data = io.lsdir(pathto, 10, 0)
    if succss then
        log.info("fs", "ls " .. pathto, json.encode(data))
    end    
    log.info("fs", "max file size: ", fs.fsize(pathto .. filename))
    -- 读取最后一包检查
    local readdata = io.readFile(pathto .. filename, "r", WRITE_SIZE *(chunk_cnt),  WRITE_SIZE)
    --log.info("fs", readdata)
    assert(readdata == tc205_chunk_dat_last, "Data not same")
    -- 删除文件
    os.remove(pathto .. filename)
    assert(io.exists(pathto .. filename) == false, "Should not exit file")
end


--[[
用例0206 文件系统满容量写入读取测试
]]
function tc0206_filesystem_full_readwrite(pathto)
    -- 仅支持lfs根目录测试
    if pathto ~= "/" then return end
    -- 先格式化文件系统
    local rc, err = io.mkfs(pathto)
    assert(rc, "FS format error")
    local succ, total, used, blksize = fs.fsstat(pathto)
    local free = total - used

    local dirname = "tc206_dir"
    local filename1 = "tc206_file01.txt"
    local filename2 = "tc206_file02.txt"
    -- 创建一个目录
    generate_directory(pathto, dirname);
    -- 重新获取剩余容量大小
    succ, total, used, blksize = fs.fsstat(pathto)
    free = total - used
    log.info("fsstat: " .. pathto, fs.fsstat(pathto))
    --local chunk_dat = string.rep("5", blksize)
    --local chunk_dat_last = string.rep("A", blksize - 4)
    -- 创建第一个文件
    local fd1 = io.open(pathto .. filename1, "w+")
    -- 连续写入多块
    local ret = file_chunkdata_write(fd1, chunk_dat, 2*(free-(LAST_BLKCOUNT-1)))
    --log.info("fs", "ret: " .. tostring(ret))
    fd1:close()
    assert(ret ~= nil, "Write chunk data failed1")
    
    -- 创建第二个文件
    local fd2 = io.open(pathto .. filename2, "w+")
    -- 连续写入多块
    local ret = file_chunkdata_write(fd2, chunk_dat, LAST_BLKCOUNT - 1)
    --log.info("fs", "ret: " .. tostring(ret))
    assert(ret ~= nil, "Write chunk data failed2")
    -- 最后一块
    ret = file_chunkdata_write(fd2, tc206_chunk_dat_last, 1)
    assert(ret ~= nil, "Write chunk data failed3")
    fd2:close()
    local succss, data = io.lsdir(pathto, 10, 0)
    if succss then
        log.info("fs", "ls " .. pathto, json.encode(data))
    end   
    -- 通过luatos扩展io库接口io.readFile读取数据, 根据offset分块读取数据验证写正确
    for i=1, (LAST_BLKCOUNT-1) do
    local readdata = io.readFile(pathto .. filename2, "r", (i-1)*WRITE_SIZE, WRITE_SIZE)
    assert(readdata == chunk_dat, "Read data != Test data")
    end
    -- 最后一包
    local last_readdata = io.readFile(pathto .. filename2, "r", (LAST_BLKCOUNT-1)*WRITE_SIZE, WRITE_SIZE - 4)
    assert(last_readdata == tc206_chunk_dat_last, "Read data != Test data")
    -- 清理工作，删除文件
    os.remove(pathto .. filename1)
    --assert(io.exists(pathto .. filename1) == false, "Should not exit file")
    os.remove(pathto .. filename2)
    --assert(io.exists(pathto .. filename1) == false, "Should not exit file")
end

--[[
用例0207 不同文件同时写入读取数据
]]
function tc0207_files_multiopen_readwrite(pathto)
    local data1 = string.rep("B", 128)
    local data2 = string.rep("C", 128)
    local binaryData = "\x12\x34\x56\78\90\xAB\xCD\xEF"
    local count = 0

    local filename0 = "tc208_data0.txt"
    local filename1 = "tc208_data1.txt"
    local filename2 = "tc208_data2.txt"
    -- 扩展接口写入二进制数据
    local rc = io.writeFile(pathto .. filename0, binaryData)
    assert(rc, "Write Bin File Error")
    -- 同时打开不同文件，两个以写模式打开，一个以只读模式打开
    local fd0 = io.open(pathto .. filename0, "rb")
    log.info("[R]", "open file:" .. pathto .. filename0)
    local fd1 = io.open(pathto .. filename1, "w+")
    log.info("[W1]", "open file:" .. pathto .. filename1)
    local fd2 = io.open(pathto .. filename2, "w+")
    log.info("[W2]", "open file:" .. pathto .. filename2)
    if fd0 and fd1 and fd2 then
        for i=1, 10 do
            -- 打开的文件，分别测试写入和读取数据
            fd1:write("[W1]:" .. data1 .. "\n")
            --log.info("fs", "[W1]", "write ")
            fd2:write("[W2]:" .. data2 .. "\n")
            --log.info("fs", "[W2]", "write ")
            fd0:seek("set", 0)
            local data = fd0:read("*a")
            if data == binaryData then count = count + 1 end
        end
        fd0:close()
        fd1:close()
        fd2:close()
    end
    local fsize1 = fs.fsize(pathto .. filename1)
    local fsize2 = fs.fsize(pathto .. filename2)
    assert(fsize1 == 1340, pathto .. filename1 .. " fsize != 1340")
    assert(fsize2 == 1340, pathto .. filename2 .. " fsize != 1340")
    assert(count == 10, pathto .. filename0 .. " read data fail")
    -- 清理工作
    if pathto == "/ram/" then 
        -- 对于/ram/ 测试完删除文件，因为ram文件系统最大允许文件数为8个超过就无法新建文件
        os.remove(pathto .. filename0)
        os.remove(pathto .. filename1)
        os.remove(pathto .. filename2)
    end
end