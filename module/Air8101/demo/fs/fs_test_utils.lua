
--[[
    fs_test_utils.lua, 封装用于测试的公共函数
]]--

-- 通过lsdir信息检查目录是否存在
function check_dir_exist(pathto, dir)
    local rc, data = io.lsdir(pathto, 10, 0)
    if rc then
        --log.info("fs", "ls " .. pathto, json.encode(data))
        for _, v in ipairs(data) do
            if v["name"] == dir and v["type"] == io.DIR then
                --print("find!!!")
                return 1
            end
        end
    end
    return 0
end

-- 通过lsdir信息获取目录或文件的大小
function get_size_from_lsdir(pathto, name, type)
    local rc, data = io.lsdir(pathto, 10, 0)
    if rc then
        log.info("fs", "ls " .. pathto, json.encode(data))
        for _, v in ipairs(data) do
            if v["name"] == name and v["type"] == type then
                --print("find!!!")
                return v["size"]
            end
        end
    end
    return 0
end

-- 封装一个用于检查并生成目录的测试函数
function generate_directory(pathto, dirname)
    local dir_path = pathto .. dirname .. "/"
    -- 判断目录是否存在
    local rc = check_dir_exist(pathto, dirname)
    if rc == 1 then 
        io.rmdir(dir_path)
    end
    -- 创建新目录
    local success, err = io.mkdir(dir_path)
    assert(success, "Failed to create directory: " .. dir_path .. tostring(err))
    rc = check_dir_exist(pathto, dirname)
    assert(rc == 1, "Not exist directory")
end

-- 封装一个用于检查并生成文件的测试函数
function generate_file(pathto, filename)
    -- 判断文件是否存在
    local rc = io.exists(pathto, filename)
    if rc  then 
        os.remove(pathto .. filename)
    end
    -- 创建新文件并写入固定数量测试数据
    local fd = io.open(pathto .. filename, "w+")
    local ret, err
    if fd then 
        ret, err = fd:write("123456789012345678901234567890123456789012345678901234567890\n")
        fd:close()
        return ret
    else
        return fd
    end
end

-- 递归方式删除目录(先删除文件保证空目录在删除目录）
function recursive_delete_directory(pathto, dirname)
    local dir_path = pathto .. dirname .. "/"
    -- 删除目录内所有文件
    local rc, data = io.lsdir(dir_path, 20, 0)
    if rc then
        log.info("fs", "ls", json.encode(data))
        for _, v in ipairs(data) do
            if v["type"] == 0 then
                --log.info("fs", "find0!!!")
                rc = os.remove(dir_path .. v["name"])
                assert(rc, "Not remove")
            elseif v["type"] == 1 then
                --log.info("fs", "find1!!!")
                recursive_delete_directory(dir_path, v["name"])
            end
        end
    end
    -- 删除目录
    local success, err = io.rmdir(dir_path)
    log.info("fs", "rmdir ", dir_path)
    assert(success, "Failed to remove directory: " .. tostring(err))
end

-- 文件写入数据块指定次数
function file_chunkdata_write(fd, chunkdata, write_times)
    if fd == nil then
        return nil
    end
    -- 分块写入数据
    local ret, err
    for i = 1, write_times do
        ret, err = fd:write(chunkdata)
        sys.wait(100)
        -- 写成功ret值为file handle写失败为nil
        --log.info("fs", "write ret: ", tostring(ret) .. " block: " .. tostring(i) )
        --log.info("fsstat: " .. pathto, fs.fsstat(pathto))
        if ret == nil then 
            return ret
        end
    end
    return ret
end
