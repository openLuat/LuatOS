require "fs_test_utils"

--配置压力测试的次数，默认为5
STRESS_TEST_TIMES=5
--[[
用例0301 压力测试，文件分块，频繁写入删除
此用例调用了sys.wait()需要在任务中调用
]]--

function tc0301_file_write_chunkdata_remove(pathto)
    -- 先格式化文件系统,lfs的根目录"/"才能执行成功，ram和luadb不支持这里保留操作不影响
    local rc, err = io.mkfs(pathto)
    --assert(rc, "FS format error")
    local filename = "tc301_data.txt"
    local data = "[TC301]: " .. string.rep("D", 300) .. "\n"
    local test_time = STRESS_TEST_TIMES
    
    for i=1, test_time do
        log.info("fs", "Test time: ", i)
        -- 扩展io库创建并写入数据
        local rc = io.writeFile(pathto .. filename, data)
        assert(rc, "File write data Error")
        sys.wait(1000)
        -- 使用标准库接口，延时重复写入数据
        local fd = io.open(pathto .. filename, "a+")
        if fd then
            local ret = file_chunkdata_write(fd, data, 5)
            assert(ret ~= nil, "Write chunk data failed")
            sys.wait(1000)
            ret = file_chunkdata_write(fd, data, 5)
            assert(ret ~= nil, "Write chunk data failed")
            sys.wait(1000)
            fd:close()
        end
        -- 最后删除文件
        os.remove(pathto .. filename)
        assert(io.exists(pathto .. filename) == false, "Should not exit file")
    end

end

--[[
用例0302 压力测试，文件分块频繁读取
]]--
function tc0302_file_readbin_frequency(pathto)
    local succss, data = io.lsdir("/luadb/", 10, 0)
    if succss then
        log.info("fs", "ls " .. "/luadb/", json.encode(data))
    end   
    -- 测试/luadb/时可以直接开始测试，否则还需搬移以下测试数据
    if pathto ~= "/luadb/" then
        -- 读取/luadb/test_data.bin 中测试文件数据
        local bindata = io.readFile("/luadb/test_data.bin", "rb", 0, 2048)
        assert(#bindata == 1308, "Read Size is error, len=" .. #bindata)
        -- 写入指定文件路径
        local rc = io.writeFile(pathto .. "test_data.bin", bindata)
        assert(rc, "Write Bin File Error")
        log.info("fsstat: " .. pathto, fs.fsstat(pathto))
    end
    local test_time = STRESS_TEST_TIMES
    for i=1, test_time do
        log.info("fs", "Test time: ", i)
        local total_len = 0
        local fd = io.open(pathto .. "test_data.bin", "r")
        --assert(fd ~= nil, "Cannot open file")
        if fd then
            while true do
                -- 循环按指定字节数读取，读取不到就退出循环
                local data = fd:read(512)
                if not data or #data == 0 then
                    break
                end
                log.info("fs", "Read data len:", #data)
                -- 收到的字节数累加
                total_len = total_len + #data
                sys.wait(100)
            end
            fd:close()
            assert(total_len == 1308, "Read Size is error, len=" .. tostring(total_len))
        end
        sys.wait(1000)
    end
end

--[[
用例0303 压力测试，文件按行频繁读取
]]--
function tc0303_file_readline_frequency(pathto)
    local succss, data = io.lsdir("/luadb/", 10, 0)
    if succss then
        log.info("fs", "ls " .. "/luadb/", json.encode(data))
    end   
    -- 测试/luadb/时可以直接开始测试，否则还需搬移以下测试数据
    if pathto ~= "/luadb/" then
        -- 读取/luadb/test_lines.bin 中测试文件数据
        local data = io.readFile("/luadb/test_lines.txt", "r", 0, 2048)
        assert(#data == 1194, "Read Size is error, len=" .. #data)
        -- 写入指定文件路径
        local rc = io.writeFile(pathto .. "test_lines.txt", data)
        assert(rc, "Write Bin File Error")
        log.info("fsstat: " .. pathto, fs.fsstat(pathto))
    end
    local test_time = STRESS_TEST_TIMES
    for i=1, test_time do
        log.info("fs", "Test time: ", i)
        local total_len = 0
        local fd = io.open(pathto .. "test_lines.txt", "r")
        --assert(fd ~= nil, "Cannot open file")
        if fd then
            while true do
                -- 循环按指定字节数读取，读取不到就退出循环
                local line = fd:read("l")
                if not line or #line == 0 then
                    break
                end
                log.info("fs", "Read line:", line)
                total_len = total_len + 1
                sys.wait(100)
            end
            --log.info("fs", total_len)
            fd:close()
            assert(total_len == 54, "Shoule be 54, but total_len=" .. tostring(total_len))
        end
        sys.wait(1000)
    end
end

--[[
用例0304 压力测试，多文件频繁创建与删除
]]--
function tc0304_file_openremove_frequency(pathto)
    local filename1 = "tc304_file01.txt"
    local dirname1 = "tc304_dir_01"
    local filename2 = "tc304_file02.txt"
    local dirname2 = "tc304_dir_02"
    -- 先清理之前遗留测试文件，格式化文件系统
    io.mkfs(pathto) -- lfs的根目录"/"才能执行成功,ram和luadb不支持这里保留，没具体操作不影响
    log.info("fsstat: " .. pathto, fs.fsstat(pathto))
    local test_time = STRESS_TEST_TIMES
    for i=1, test_time do
        log.info("fs", "Test time: ", i)
        if pathto ~= "/ram/" then -- ram不支持目录,luadb不测试这项
            log.info("fs", "Create Dir" .. pathto .. dirname1 .. "/")
            generate_directory(pathto, dirname1)
        end
        log.info("fs", "Create File" .. pathto .. filename1)
        local fd = io.open(pathto .. filename1, "w+")
        assert(fd ~= nil)
        if fd then
            fd:close()
        end
        if pathto ~= "/ram/" then -- ram不支持目录,luadb不测试这项
            log.info("fs", "Create Dir" .. pathto .. dirname2 .. "/")
            generate_directory(pathto, dirname2)
        end
        log.info("fs", "Create File" .. pathto .. filename2)
        local rc = io.writeFile(pathto .. filename2, "1qaz2wsx3edc4rfv\n")
        assert(rc, "Write Bin File Error")
        sys.wait(1000)
    end
end
