--[[
@module  flash_fs_io
@summary 内置Flash文件系统操作测试模块
@version 1.0.0
@date    2025.09.23
@author  王棚嶙
@usage
本文件为内置Flash文件系统的操作测试流程：
1. 获取文件系统信息( io.fsstat)
2. 创建目录
3. 创建并写入文件
4. 检查文件是否存在
5. 获取文件大小(io.fileSize)
6. 读取文件内容
7. 启动计数文件操作
8. 文件追加测试
9. 按行读取测试
10. 文件重命名
11. 列举目录内容
12. 删除文件
13. 删除目录
本文件没有对外接口，直接在main.lua中require "flash_fs_io"就可以加载运行
]]

function flash_fs_io_task()
    -- 使用内置Flash文件系统，根目录为"/",
    local base_path = "/"
    -- 创建一个目录
    local demo_dir = "flash_demo"
    -- 文件名
    local dir_path = base_path .. demo_dir

    -- ########## 开始进行内置Flash文件系统操作 ##########
    log.info("文件系统操作", "===== 开始文件系统操作 =====")

    -- 1. 获取文件系统信息 (使用 io.fsstat接口)
    local success, total_blocks, used_blocks, block_size, fs_type  =  io.fsstat(base_path)
    if success then
        log.info(" io.fsstat成功:", 
            "总空间=" .. total_blocks .. "块", 
            "已用=" .. used_blocks .. "块", 
            "块大小=" .. block_size.."字节",
            "类型=" .. fs_type)
    else
        log.error(" io.fsstat", "获取文件系统信息失败")
        return
    end

    -- 2. 创建目录
    -- 如果目录不存在，则创建目录
    if not io.dexist(dir_path) then
        -- 创建目录
        if io.mkdir(dir_path) then
            log.info("io.mkdir", "目录创建成功", "路径:" .. dir_path)
        else
            log.error("io.mkdir", "目录创建失败", "路径:" .. dir_path)
            return
        end
    else
        log.warn("io.mkdir", "目录已存在，跳过创建", "路径:" .. dir_path)
    end

    -- 3. 创建并写入文件
    local file_path = dir_path .. "/boottime"
    local file = io.open(file_path, "wb")
    if file then
        file:write("这是内置Flash文件系统API文档示例的测试内容")
        file:close()
        log.info("文件创建", "文件写入成功", "路径:" .. file_path)
    else
        log.error("文件创建", "文件创建失败", "路径:" .. file_path)
        return
    end

    -- 4. 检查文件是否存在
    if io.exists(file_path) then
        log.info("io.exists", "文件存在", "路径:" .. file_path)
    else
        log.error("io.exists", "文件不存在", "路径:" .. file_path)
        return
    end

    -- 5. 获取文件大小 (使用io.fileSize接口)
    local file_size = io.fileSize(file_path)
    if file_size then
        log.info("io.fileSize", "文件大小:" .. file_size .. "字节", "路径:" .. file_path)
    else
        log.error("io.fileSize", "获取文件大小失败", "路径:" .. file_path)
        return
    end

    -- 6. 读取文件内容
    file = io.open(file_path, "rb")
    if file then
        local content = file:read("*a")
        log.info("文件读取", "路径:" .. file_path, "内容:" .. content)
        file:close()
    else
        log.error("文件操作", "无法打开文件读取内容", "路径:" .. file_path)
        return
    end

    -- 7. 启动计数文件操作
    local count = 0
    file = io.open(file_path, "rb")
    if file then
        local data = file:read("*a")
        log.info("启动计数", "文件内容:", data, "十六进制:", data:toHex())
        count = tonumber(data) or 0
        file:close()
    else
        log.warn("启动计数", "文件不存在或无法打开")
    end

    log.info("启动计数", "当前值:", count)
    count = count + 1
    log.info("启动计数", "更新值:", count)

    file = io.open(file_path, "wb")
    if file then
        file:write(tostring(count))
        file:close()
        log.info("文件写入", "路径:" .. file_path, "内容:", count)
    else
        log.error("文件写入", "无法打开文件", "路径:" .. file_path)
        return
    end

    -- 8. 文件追加测试
    local append_file = dir_path .. "/test_a"
    os.remove(append_file) -- 清理旧文件

    file = io.open(append_file, "wb")
    if file then
        file:write("ABC")
        file:close()
        log.info("文件创建", "路径:" .. append_file, "初始内容:ABC")
    else
        log.error("文件创建", "无法创建文件", "路径:" .. append_file)
        return
    end

    file = io.open(append_file, "a+")
    if file then
        file:write("def")
        file:close()
        log.info("文件追加", "路径:" .. append_file, "追加内容:def")
    else
        log.error("文件追加", "无法打开文件进行追加", "路径:" .. append_file)
        return
    end

    -- 验证追加结果
    file = io.open(append_file, "r")
    if file then
        local data = file:read("*a")
        log.info("文件验证", "路径:" .. append_file, "内容:" .. data, "结果:",
            data == "ABCdef" and "成功" or "失败")
        file:close()
    else
        log.error("文件验证", "无法打开文件进行验证", "路径:" .. append_file)
        return
    end

    -- 9. 按行读取测试
    local line_file = dir_path .. "/testline"
    file = io.open(line_file, "w")
    if file then
        file:write("abc\n")
        file:write("123\n")
        file:write("wendal\n")
        file:close()
        log.info("文件创建", "路径:" .. line_file, "写入3行文本")
    else
        log.error("文件创建", "无法创建文件", "路径:" .. line_file)
        return
    end

    file = io.open(line_file, "r")
    if file then
        log.info("按行读取", "路径:" .. line_file, "第1行:", file:read("*l"))
        log.info("按行读取", "路径:" .. line_file, "第2行:", file:read("*l"))
        log.info("按行读取", "路径:" .. line_file, "第3行:", file:read("*l"))
        file:close()
    else
        log.error("按行读取", "无法打开文件", "路径:" .. line_file)
        return
    end

    -- 10. 文件重命名
    local old_path = append_file
    local new_path = dir_path .. "/renamed_file.txt"
    local success, err = os.rename(old_path, new_path)
    if success then
        log.info("os.rename", "文件重命名成功", "原路径:" .. old_path, "新路径:" .. new_path)

        -- 验证重命名结果
        if io.exists(new_path) and not io.exists(old_path) then
            log.info("验证结果", "重命名验证成功", "新文件存在", "原文件不存在")
        else
            log.error("验证结果", "重命名验证失败")
        end
    else
        log.error("os.rename", "重命名失败", "错误:" .. tostring(err), "原路径:" .. old_path)
        return
    end

    -- 11. 列举目录内容
    log.info("目录操作", "===== 开始目录列举 =====")

    local ret, data = io.lsdir(dir_path, 50, 0)
    if ret then
        log.info("fs", "lsdir", json.encode(data))
    else
        log.info("fs", "lsdir", "fail", ret, data)
        return
    end

    -- 12. 删除文件测试
    if os.remove(new_path) then
        log.info("os.remove", "文件删除成功", "路径:" .. new_path)
        if not io.exists(new_path) then
            log.info("验证结果", "renamed_file.txt文件删除验证成功")
        else
            log.error("验证结果", "renamed_file.txt文件删除验证失败")
        end
    else
        log.error("os.remove", "renamed_file.txt文件删除失败", "路径:" .. new_path)
        return
    end

    if os.remove(line_file) then
        log.info("os.remove", "testline文件删除成功", "路径:" .. line_file)
        if not io.exists(line_file) then
            log.info("验证结果", "testline文件删除验证成功")
        else
            log.error("验证结果", "testline文件删除验证失败")
        end
    else
        log.error("os.remove", "testline文件删除失败", "路径:" .. line_file)
        return
    end

    if os.remove(file_path) then
        log.info("os.remove", "文件删除成功", "路径:" .. file_path)
        if not io.exists(file_path) then
            log.info("验证结果", "boottime文件删除验证成功")
        else
            log.error("验证结果", "boottime文件删除验证失败")
        end
    else
        log.error("os.remove", "boottime文件删除失败", "路径:" .. file_path)
        return
    end

    -- 13. 删除目录
    if io.rmdir(dir_path) then
        log.info("io.rmdir", "目录删除成功", "路径:" .. dir_path)
        if not io.dexist(dir_path) then
            log.info("验证结果", "目录删除验证成功")
        else
            log.error("验证结果", "目录删除验证失败")
        end
    else
        log.error("io.rmdir", "目录删除失败", "路径:" .. dir_path)
        return
    end

    -- 再次获取文件系统信息，查看空间变化
    local final_success, final_total_blocks, final_used_blocks, final_block_size, final_fs_type =  io.fsstat(base_path)
    if final_success then
        log.info(" io.fsstat", "操作后文件系统信息:", 
                 "总空间=" .. final_total_blocks .. "块", 
                 "已用=" .. final_used_blocks .. "块", 
                 "块大小=" .. final_block_size.."字节",
                 "类型=" .. final_fs_type)
    end

    log.info("文件系统操作", "===== 文件系统操作完成 =====")
end

sys.taskInit(flash_fs_io_task)