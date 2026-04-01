-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "miniz_test"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()
    sys.wait(1000) -- 等待系统稳定
    log.info("test", "开始测试 miniz.unzip 功能")
    
    -- 测试文件路径
    local zip_file = "/luadb/pac_man.zip"
    local target_dir = "/ram/miniz_unzip"
    local extracted_root = target_dir .. "/pac_man"
    local nested_dir = extracted_root .. "/user"
    local expected_files = {
        {path = extracted_root .. "/main.lua", size = 223},
        {path = extracted_root .. "/meta.json", size = 493},
        {path = extracted_root .. "/icon.png", size = 3241},
        {path = nested_dir .. "/pacman_game_win.lua", size = 15173},
    }
    
    -- 确保测试文件存在
    if not io.exists(zip_file) then
        log.error("test", "测试ZIP文件不存在:", zip_file)
        os.exit(1)
        return
    end
    
    log.info("test", "解压文件:", zip_file, "到目录:", target_dir)

    local invalid_success = miniz.unzip(zip_file, target_dir)
    if invalid_success then
        log.error("test", "未以 / 结尾的 target_dir 不应成功")
        os.exit(1)
        return
    end
    
    -- 调用 unzip 函数
    local success = miniz.unzip(zip_file, target_dir .. "/")
    local pass = true
    if success then
        log.info("test", "解压成功！")
        local ok_root, root_entries = io.lsdir(extracted_root)
        assert(ok_root and type(root_entries) == "table", "pac_man 目录应存在")

        local ok_nested, nested_entries = io.lsdir(nested_dir)
        assert(ok_nested and type(nested_entries) == "table", "pac_man/user 目录应存在")

        for _, item in ipairs(expected_files) do
            if not io.exists(item.path) then
                log.error("test", "缺少解压文件: " .. item.path)
                pass = false
            else
                local file_size = io.fileSize(item.path)
                if file_size ~= item.size then
                    log.error("test", string.format("文件大小不匹配 %s 预期 %d 实际 %d", item.path, item.size, file_size or -1))
                    pass = false
                else
                    log.info("test", "解压文件校验通过", item.path, file_size)
                end
            end
        end

        -- 列出解压后的文件
        local ok, files = io.lsdir(target_dir)
        if files then
            log.info("test", "解压后的文件列表:")
            for i, file in pairs(files) do
                log.info("test", "-", i, json.encode(file))
            end
        else
            log.info("test", "无法列出解压后的文件")
        end

        -- 测试解压到 /lfs2
        local lfs_target = "/lfs2/"
        local success_lfs = miniz.unzip(zip_file, lfs_target)
        if success_lfs then
            log.info("test", "解压到 /lfs2 成功！")
            local ok_lfs, lfs_entries = io.lsdir(lfs_target .. "pac_man")
            assert(ok_lfs and type(lfs_entries) == "table", "/lfs2/pac_man 目录应存在")
            -- 再检查文件和目录是不是都存在
            for _, item in ipairs(expected_files) do
                if not io.exists(lfs_target .. item.path:sub(#target_dir + 1)) then
                    log.error("test", "缺少解压文件在 /lfs2: " .. lfs_target .. item.path:sub(#target_dir + 1))
                    pass = false
                else
                    local file_size = io.fileSize(lfs_target .. item.path:sub(#target_dir + 1))
                    if file_size ~= item.size then
                        log.error("test", string.format("文件大小不匹配在 /lfs2 %s 预期 %d 实际 %d", lfs_target .. item.path:sub(#target_dir + 1), item.size, file_size or -1))
                        pass = false
                    else
                        log.info("test", "解压文件校验通过在 /lfs2", item.path, file_size)
                    end
                end
            end
        else
            log.error("test", "解压失败！")
            pass = false
        end
    else
        log.error("test", "解压失败！")
        pass = false
    end

    if os.exit == nil then
        if code == 0 then
            log.info("test", "测试通过√")
        else
            log.error("test", "测试失败")
        end
        return
    end

    -- 输出到/abc/目录进行测试
    local abc_target = "/abc/"
    local success_abc = miniz.unzip(zip_file, abc_target)
    if success_abc then
        log.info("test", "解压到 /abc 成功！")
        local ok_abc, abc_entries = io.lsdir(abc_target .. "pac_man")
        assert(ok_abc and type(abc_entries) == "table", "/abc/pac_man 目录应存在")
        for _, item in ipairs(expected_files) do
            local abc_path = abc_target .. item.path:sub(#target_dir + 1)
            if not io.exists(abc_path) then
                log.error("test", "缺少解压文件在 /abc: " .. abc_path)
                pass = false
            else
                local file_size = io.fileSize(abc_path)
                if file_size ~= item.size then
                    log.error("test", string.format("文件大小不匹配在 /abc %s 预期 %d 实际 %d", abc_path, item.size, file_size or -1))
                    pass = false
                else
                    log.info("test", "解压文件校验通过在 /abc", abc_path, file_size)
                end
            end
        end
    else
        log.error("test", "解压到 /abc 失败！")
        pass = false
    end

    if pass then
        log.info("test", "目录创建测试通过")
        os.exit(0)
    else
        log.error("test", "目录创建测试失败")
        os.exit(1)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!