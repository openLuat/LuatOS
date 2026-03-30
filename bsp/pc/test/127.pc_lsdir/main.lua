
sys.taskInit(function()
    log.info("lsdir_tests", "正在执行 io.lsdir 测试")
    io.mkdir("/tmp/")
    io.writeFile("/tmp/test.txt", "Hello, World!")
    local ok, result = io.lsdir("/tmp")
    if ok then
        for _, file in ipairs(result) do
            log.info("lsdir_tests", "文件:", json.encode(file))
        end
    else
        log.error("lsdir_tests", "读取目录失败")
    end
    os.exit()
end)

sys.run()