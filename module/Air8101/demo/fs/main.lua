-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "demo_fs_test"
VERSION = "1.0.0"

-- 通过屏蔽变量来控制测试对应FS路径,默认打开LFS
local PATH_LFS = "/"
--local PATH_RAM = "/ram/"
--local PATH_LUADB = "/luadb/"

-- 通过屏蔽module来开关不同测试,默认不打开part3压力测试
require "fs_test_part1"
require "fs_test_part2"
--require "fs_test_part3"

-- test_run函数接受一个table参数，table中包含测试用例函数
-- 调用了sys.wait()需要在任务中调用
function test_run(test_cases, path)
    local successCount = 0  -- 成功的测试用例计数
    local failureCount = 0  -- 失败的测试用例计数

    -- 遍历table中的每个测试用例函数
    for name, testCase in pairs(test_cases) do
        -- 检查testCase是否为函数
        if type(testCase) == "function" then
            -- 使用pcall来捕获测试用例执行中的错误, 若有错误也继续往下执行
            local success, err = pcall(testCase, path)  
            if success then
                -- 测试成功，增加成功计数
                successCount = successCount + 1  
                log.info("fs", "Test case passed: " .. name)
            else
                -- 测试失败，增加失败计数
                failureCount = failureCount + 1  
                log.info("fs", "Test case failed: " .. name .. " - Error: " .. err)
            end
        else
            log.info("fs", "Skipping non-function entry: " .. name)
        end
        -- 稍等一会在继续测试
        sys.wait(1000)
    end
    -- 打印测试结果
    log.info("fs", "Test run complete - Success: " .. successCount .. ", Failures: " .. failureCount)
end


-- 测试用例的table,以函数名为键，函数为值，实际运行无序可以增加测试的随机性
-- lfs的测试函数集
local fs_test_suite_lfs = {
    --[[
    基本功能测试，需定义require "fs_test_part1"
    ]]-- 
    ["tc0101_file_operation"] = tc0101_file_operation,
    ["tc0102_directory_operation"] = tc0102_directory_operation,
    ["tc0103_file_writedata_std"] = tc0103_file_writedata_std, --
    ["tc0104_file_writedata_ext"] = tc0104_file_writedata_ext, --
    ["tc0105_file_readdata_ext"] = tc0105_file_readdata_ext,--
    ["tc0106_file_readdata_std"] = tc0106_file_readdata_std,--
    ["tc0107_file_write_trunc_append"] = tc0107_file_write_trunc_append,
    ["tc0108_file_pointer_readwrite"] = tc0108_file_pointer_readwrite,
    ["tc0109_file_write_read_bindata"] = tc0109_file_write_read_bindata,
    ["tc0110_file_rename_readwrite"] = tc0110_file_rename_readwrite,
    ["tc0111_file_size"] = tc0111_file_size,
    ["tc0112_directory_size"] = tc0112_directory_size, --
    ["tc0113_filesystem_info"] = tc0113_filesystem_info,
    --[[
    异常与边界测试，需定义require "fs_test_part2"
    ]]--
    ["tc0201_file_abnormal_operate"] = tc0201_file_abnormal_operate,
    ["tc0202_directory_abnormal_operate"] = tc0202_directory_abnormal_operate,
    ["tc0203_file_abnormal_readwrite"] = tc0203_file_abnormal_readwrite,
    ["tc0204_filename_max"] = tc0204_filename_max,
    ["tc0205_file_writemax"] = tc0205_file_writemax,
    ["tc0206_filesystem_full_readwrite"] = tc0206_filesystem_full_readwrite,
    ["tc0207_files_multiopen_readwrite"] = tc0207_files_multiopen_readwrite,
    --[[
    文件读写压力测试，默认不打开，需定义require "fs_test_part3"，若需要测试建议单独打开测试
    ]]--    
    ["tc0301_file_write_chunkdata_remove"] = tc0301_file_write_chunkdata_remove,
    ["tc0302_file_readbin_frequency"] = tc0302_file_readbin_frequency,
    ["tc0303_file_readline_frequency"] = tc0303_file_readline_frequency,
    ["tc0304_file_openremove_frequency"] = tc0304_file_openremove_frequency,
}

-- ram的测试函数集
local fs_test_suite_ram = {
    --[[
    基本功能测试，需定义require "fs_test_part1"
    ]]--     
    ["tc0101_file_operation"] = tc0101_file_operation,
    ["tc0103_file_writedata_std"] = tc0103_file_writedata_std, --
    ["tc0104_file_writedata_ext"] = tc0104_file_writedata_ext, --
    ["tc0105_file_readdata_ext"] = tc0105_file_readdata_ext,--
    ["tc0106_file_readdata_std"] = tc0106_file_readdata_std,--
    ["tc0107_file_write_trunc_append"] = tc0107_file_write_trunc_append,
    ["tc0108_file_pointer_readwrite"] = tc0108_file_pointer_readwrite,
    ["tc0109_file_write_read_bindata"] = tc0109_file_write_read_bindata,
    ["tc0110_file_rename_readwrite"] = tc0110_file_rename_readwrite,
    ["tc0111_file_size"] = tc0111_file_size,
    ["tc0113_filesystem_info"] = tc0113_filesystem_info,
    --[[
    异常与边界测试，需定义require "fs_test_part2"
    ]]--
    ["tc0201_file_abnormal_operate"] = tc0201_file_abnormal_operate,
    ["tc0203_file_abnormal_readwrite"] = tc0203_file_abnormal_readwrite,--
    ["tc0204_filename_max"] = tc0204_filename_max,
    ["tc0207_files_multiopen_readwrite"] = tc0207_files_multiopen_readwrite,
    --[[
    文件读写压力测试, 默认不打开，需定义require "fs_test_part3"，若需要测试建议单独打开测试
    ]]--
    ["tc0301_file_write_chunkdata_remove"] = tc0301_file_write_chunkdata_remove,
    ["tc0302_file_readbin_frequency"] = tc0302_file_readbin_frequency,
    ["tc0303_file_readline_frequency"] = tc0303_file_readline_frequency,
    ["tc0304_file_openremove_frequency"] = tc0304_file_openremove_frequency,
}

-- luadb的测试函数集
local fs_test_suite_luadb = {
    --[[
    基本功能测试，需定义require "fs_test_part1"
    ]]--    
    ["tc0105_file_readdata_ext"] = tc0105_file_readdata_ext,--
    ["tc0106_file_readdata_std"] = tc0106_file_readdata_std,--
    ["tc0111_file_size"] = tc0111_file_size,
    ["tc0113_filesystem_info"] = tc0113_filesystem_info,
    --[[
    异常与边界测试，需定义require "fs_test_part2"
    ]]--
    ["tc0203_file_abnormal_readwrite"] = tc0203_file_abnormal_readwrite,
    --[[
    文件读写压力测试, 默认不打开，需定义require "fs_test_part3"，若需要测试建议单独打开测试
    ]]--
    ["tc0302_file_readbin_frequency"] = tc0302_file_readbin_frequency,
    ["tc0303_file_readline_frequency"] = tc0303_file_readline_frequency,
}

-- 定义任务来开始demo测试流程
sys.taskInit(function()
    -- 为了显示日志,这里特意延迟一秒
    -- 正常使用不需要delay
    sys.wait(1000)
    
    -- 运行测试套件
    if PATH_LFS then
        -- 开机首先获取文件系统根目录信息确认可掉电保存正常
        local rc, data = io.lsdir(PATH_LFS, 10, 0)
        log.info("fs", "ls " .. PATH_LFS, json.encode(data))
        log.info("fsstat: " .. PATH_LFS, fs.fsstat(PATH_LFS))
        -- 先格式化文件系统
        io.mkfs(PATH_LFS)
        --tc0114_filesystem_format(PATH_LFS)
        sys.wait(200)
        log.info("fs", "Test path on " .. "\"" .. PATH_LFS .. "\"")
        test_run(fs_test_suite_lfs, PATH_LFS)

        -- LFS根目录下创建一个新目录,原则上新目录需要完成根目录一致的测试确保新建目录中操作功能正常，
        -- 默认不打开
        --[[
        log.info("fs", "Test path on " .. "\"" .. PATH_LFS .. "test/" .. "\"")
        generate_directory(PATH_LFS, "test")
        test_run(fs_test_suite_lfs, PATH_LFS .. "test/")
        -- 递归删除，需保证目录内容为空才能删除目录
        recursive_delete_directory(PATH_LFS, "test")
        ]]--
    end

    if PATH_RAM then
        log.info("fsstat: " .. PATH_RAM, fs.fsstat(PATH_RAM))
        log.info("fs", "Test path on " .. PATH_RAM)
        test_run(fs_test_suite_ram, PATH_RAM)
    end

    if PATH_LUADB then
        log.info("fsstat: " .. PATH_LUADB, fs.fsstat(PATH_LUADB))
        log.info("fs", "Test path on " .. PATH_LUADB)
        test_run(fs_test_suite_luadb, PATH_LUADB)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!