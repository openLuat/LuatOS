PROJECT = "lcd_qspi"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- require "co5300"
-- require "jd9261t"
-- require "sh8601z"

function read_write_test(src, dst, rw_size)
-- 逐段写入测试
    local fd = io.open(src, "r")
    local fd2 = io.open(dst, "w+")
    while true do
        local chunk = fd:read(rw_size)
        if not chunk then break end
        fd2:write(chunk)
    end
    fd:close()
    fd2:close()

    local data = io.readFile(src)
    local data3 = io.readFile(dst)
    if #data ~= #data3 then
        log.error("文件大小不一致", #data, #data3, rw_size)
        os.exit(1)
    end
    if crypto.md5(data) ~= crypto.md5(data3) then
        log.error("md5不一致", crypto.md5(data), crypto.md5(data3), rw_size)
        os.exit(1)
    end

    -- 还得测试分段读取
    local fd = io.open(src, "r")
    local fd2 = io.open(dst, "r")
    while true do
        local chunk = fd:read(rw_size)
        local chunk2 = fd2:read(rw_size)
        if not chunk and not chunk2 then break end
        if chunk ~= chunk2 then
            log.error("分段读取不一致", #chunk, #chunk2, rw_size)
            os.exit(1)
        end
    end
    fd:close()
    fd2:close()

    -- 测试设置seek之后读
    local fd = io.open(src, "r")
    local fd2 = io.open(dst, "r")
    while true do
        local chunk = fd:read(rw_size)
        local chunk2 = fd2:read(rw_size)
        if not chunk and not chunk2 then break end
        if chunk ~= chunk2 then
            log.error("分段读取不一致", #chunk, #chunk2, rw_size)
            os.exit(1)
        end
        -- log.info("执行seek操作")
        fd:seek("cur", 1)
        -- log.info("执行seek操作2")
        fd2:seek("cur", 1)
    end
    fd:close()
    fd2:close()
end

sys.taskInit(function()
    local src = "/luadb/clock.jpg"
    local dst = "/ram/clock.jpg"

    read_write_test(src, dst, 4096)
    read_write_test(src, dst, 4095)
    read_write_test(src, dst, 4097)
    read_write_test(src, dst, 1024)
    read_write_test(src, dst, 512)
    read_write_test(src, dst, 256)
    read_write_test(src, dst, 128)
    read_write_test(src, dst, 64)
    read_write_test(src, dst, 32)
    read_write_test(src, dst, 16)
    read_write_test(src, dst, 8)
    read_write_test(src, dst, 4)
    read_write_test(src, dst, 2)
    read_write_test(src, dst, 1)

    for i = 1, 8199 do
        read_write_test(src, dst, i)
    end

    log.info("测试PASS")

    os.exit(1)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

