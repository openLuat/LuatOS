
sys.taskInit(function()
    local ok, err = pcall(function()
        log.info("lsdir_tests", "正在执行 io.lsdir/io.dexist 测试")
        io.mkdir("/tmp/")
        io.mkdir("/tmp/subdir/")
        io.writeFile("/tmp/test.txt", "Hello, World!")

        assert(io.dexist("/tmp"), "/tmp 应存在")
        assert(io.dexist("/tmp/subdir"), "/tmp/subdir 应存在")
        assert(not io.dexist("/tmp/test.txt"), "文件路径不应被识别为目录")

        local ls_ok, result = io.lsdir("/tmp")
        assert(ls_ok, "读取 /tmp 目录失败")

        local found_file = false
        local found_dir = false
        for _, file in ipairs(result) do
            log.info("lsdir_tests", "文件:", json.encode(file))
            if file.name == "test.txt" and file.type == 0 then
                found_file = true
            end
            if file.name == "subdir" and file.type == 1 then
                found_dir = true
            end
        end

        assert(found_file, "lsdir 结果缺少 test.txt")
        assert(found_dir, "lsdir 结果缺少 subdir")
    end)

    if ok then
        log.info("lsdir_tests", "测试通过")
        os.exit(0)
    else
        log.error("lsdir_tests", "测试失败", err)
        os.exit(1)
    end
end)

sys.run()