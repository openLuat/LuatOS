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
    
    -- 调用 unzip 函数
    local success = miniz.unzip(zip_file, target_dir)
    
    if success then
        log.info("test", "解压成功！")
        local ok_root, root_entries = io.lsdir(extracted_root)
        assert(ok_root and type(root_entries) == "table", "pac_man 目录应存在")

        local ok_nested, nested_entries = io.lsdir(nested_dir)
        assert(ok_nested and type(nested_entries) == "table", "pac_man/user 目录应存在")

        for _, item in ipairs(expected_files) do
            assert(io.exists(item.path), "缺少解压文件: " .. item.path)
            local file_size = io.fileSize(item.path)
            assert(file_size == item.size, string.format("文件大小不匹配 %s 预期 %d 实际 %d", item.path, item.size, file_size or -1))
            log.info("test", "解压文件校验通过", item.path, file_size)
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

        log.info("test", "目录创建测试通过")
        os.exit(0)
    else
        log.error("test", "解压失败！")
        os.exit(1)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!