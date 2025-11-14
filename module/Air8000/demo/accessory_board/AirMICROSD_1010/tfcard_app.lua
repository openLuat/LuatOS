--[[
@module  tfcard_app
@summary TF卡文件操作测试模块
@version 1.0.0
@date    2025.08.25
@author  王棚嶙
@usage
本文件为TF卡的文件操作测试流程：
1. 创建目录
2. 创建并写入文件
3. 检查文件是否存在
4. 获取文件大小
5. 读取文件内容
6. 启动计数文件操作
7. 文件追加测试
8. 按行读取测试
9. 读取后关闭文件
10. 文件重命名
11. 列举目录内容
12. 删除文件
13. 删除目录
本文件没有对外接口，直接在main.lua中require "tfcard_app"就可以加载运行
]] 

function tfcard_main_task() -- 开始进行主测试流程。

    -- ##########  SPI初始化 ##########
    -- Air8000核心板上TF卡的的pin_cs为gpio12，spi_id为1.请根据实际硬件修改
    spi_id, pin_cs = 1, 12
    spi.setup(spi_id, nil, 0, 0, 400 * 1000)
    gpio.setup(pin_cs, 1)

    -- ########## 开始进行tf卡挂载 ##########
    --挂载失败默认格式化，
    -- 如无需格式化应改为fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000, nil, 1, false),
    -- 一般是在测试硬件是否有问题的时候把格式化取消掉
    mount_ok, mount_err = fatfs.mount(fatfs.SPI, "/sd", spi_id, pin_cs, 24 * 1000 * 1000)
    if mount_ok then
        log.info("fatfs.mount", "挂载成功", mount_err)
    else
        log.error("fatfs.mount", "挂载失败", mount_err)
        goto resource_cleanup
    end

    -- ########## 获取SD卡的可用空间信息并打印。 ########## 
    data, err = fatfs.getfree("/sd")
    if data then
        --打印SD卡的可用空间信息
        log.info("fatfs", "getfree", json.encode(data))
    else
        --打印错误信息
        log.info("fatfs", "getfree", "err", err)
        goto resource_cleanup
    end

    -- 列出所有挂载点，如不需要，可注释掉。
    data = io.lsmount()
    log.info("fs", "lsmount", json.encode(data))

    -- ########## 功能: 启用fatfs调试模式 ##########
    -- fatfs.debug(1) -- 若挂载失败,可以尝试打开调试信息,查找原因.(设置调试模式)

    -- 执行tfcard文件操作演示
    log.info("文件操作", "===== 开始文件操作 =====")

    dir_path = "/sd/io_test"

    -- 1. 创建目录
    if io.mkdir(dir_path) then
        log.info("io.mkdir", "目录创建成功", "路径:" .. dir_path)
    else
        -- 检查是否目录已存在
        if io.exists(dir_path) then
            log.warn("io.mkdir", "目录已存在，跳过创建", "路径:" .. dir_path)
        else
            log.error("io.mkdir", "目录创建失败且目录不存在", "路径:" .. dir_path)
            goto resource_cleanup
        end
    end

    -- 2. 创建并写入文件
    file_path = dir_path .. "/boottime"
    file = io.open(file_path, "wb")
    if file then
        file:write("这是io库API文档示例的测试内容")
        file:close()
        --在LuatOS文件操作中，执行file:close()是必须且关键的操作，它用于关闭文件句柄，释放资源，并确保数据被正确写入磁盘。
        -- 如果不执行file:close()，可能会导致数据丢失、文件损坏或其他不可预测的问题。
        log.info("文件创建", "文件写入成功", "路径:" .. file_path)
    else
        log.error("文件创建", "文件创建失败", "路径:" .. file_path)
        goto resource_cleanup
    end

    -- 3. 检查文件是否存在
    if io.exists(file_path) then
        log.info("io.exists", "文件存在", "路径:" .. file_path)
    else
        log.error("io.exists", "文件不存在", "路径:" .. file_path)
        goto resource_cleanup
    end

    -- 4. 获取文件大小
    file_size = io.fileSize(file_path)
    if file_size then
        log.info("io.fileSize", "文件大小:" .. file_size .. "字节", "路径:" .. file_path)
    else
        log.error("io.fileSize", "获取文件大小失败", "路径:" .. file_path)
        goto resource_cleanup
    end

    -- 5. 读取文件内容
    file = io.open(file_path, "rb")
    if file then
        content = file:read("*a")
        log.info("文件读取", "路径:" .. file_path, "内容:" .. content)
        file:close()
    else
        log.error("文件操作", "无法打开文件读取内容", "路径:" .. file_path)
        goto resource_cleanup
    end

    -- 6. 启动计数文件操作
    count = 0
    --以只读模式打开文件
    file = io.open(file_path, "rb")
    if file then
        data = file:read("*a")
        log.info("启动计数", "文件内容:", data, "十六进制:", data:toHex())
        count = tonumber(data) or 0
        file:close()
    else
        log.warn("启动计数", "文件不存在或无法打开")

    end

    log.info("启动计数", "当前值:", count)
    count=count + 1
    log.info("启动计数", "更新值:", count)

    file = io.open(file_path, "wb")
    if file then
        file:write(tostring(count))
        file:close()
        log.info("文件写入", "路径:" .. file_path, "内容:", count)
    else
        log.error("文件写入", "无法打开文件", "路径:" .. file_path)
        goto resource_cleanup
    end

    -- 7. 文件追加测试
    append_file = dir_path .. "/test_a"
    -- 清理旧文件
    os.remove(append_file)

    -- 创建并写入初始内容
    file = io.open(append_file, "wb")
    if file then
        file:write("ABC")
        file:close()
        log.info("文件创建", "路径:" .. append_file, "初始内容:ABC")
    else
        log.error("文件创建", "无法创建文件", "路径:" .. append_file)
        goto resource_cleanup
    end

    -- 追加内容
    file = io.open(append_file, "a+")
    if file then
        file:write("def")
        file:close()
        log.info("文件追加", "路径:" .. append_file, "追加内容:def")
    else
        log.error("文件追加", "无法打开文件进行追加", "路径:" .. append_file)
        goto resource_cleanup

    end

    -- 验证追加结果
    file = io.open(append_file, "r")
    if file then
        data = file:read("*a")
        log.info("文件验证", "路径:" .. append_file, "内容:" .. data, "结果:",
            data == "ABCdef" and "成功" or "失败")
        file:close()
    else
        log.error("文件验证", "无法打开文件进行验证", "路径:" .. append_file)
        goto resource_cleanup
    end

    -- 8. 按行读取测试
    line_file = dir_path .. "/testline"
    file = io.open(line_file, "w")
    if file then
        file:write("abc\n")
        file:write("123\n")
        file:write("wendal\n")
        file:close()
        log.info("文件创建", "路径:" .. line_file, "写入3行文本")
    else
        log.error("文件创建", "无法创建文件", "路径:" .. line_file)
        goto resource_cleanup
    end

    -- 按行读取文件
    file = io.open(line_file, "r")
    if file then
        log.info("按行读取", "路径:" .. line_file, "第1行:", file:read("*l"))
        log.info("按行读取", "路径:" .. line_file, "第2行:", file:read("*l"))
        log.info("按行读取", "路径:" .. line_file, "第3行:", file:read("*l"))
        file:close()
    else
        log.error("按行读取", "无法打开文件", "路径:" .. line_file)
        goto resource_cleanup
    end

    -- 9. 文件重命名
    old_path = append_file
    new_path = dir_path .. "/renamed_file.txt"
    success, err = os.rename(old_path, new_path)
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
        goto resource_cleanup
    end

    -- 10. 列举目录内容
    log.info("目录操作", "===== 开始目录列举 =====")

    ret, data = io.lsdir(dir_path, 50, 0) -- 50表示最多返回50个文件，0表示从目录开头开始
    if ret then
        log.info("fs", "lsdir", json.encode(data))
    else
        log.info("fs", "lsdir", "fail", ret, data)
        goto resource_cleanup
    end

    -- 11. 删除文件测试
    -- 测试删除renamed_file.txt文件
    if os.remove(new_path) then
        log.info("os.remove", "文件删除成功", "路径:" .. new_path)

        -- 验证renamed_file.txt删除结果
        if not io.exists(new_path) then
            log.info("验证结果", "renamed_file.txt文件删除验证成功")
        else
            log.error("验证结果", "renamed_file.txt文件删除验证失败")
        end
    else
        log.error("io.remove", "renamed_file.txt文件删除失败", "路径:" .. new_path)
        goto resource_cleanup
    end

    -- 测试删除testline文件
    if os.remove(line_file) then
        log.info("os.remove", "testline文件删除成功", "路径:" .. line_file)

        -- 验证删除结果
        if not io.exists(line_file) then
            log.info("验证结果", "testline文件删除验证成功")
        else
            log.error("验证结果", "testline文件删除验证失败")
        end
    else
        log.error("io.remove", "testline文件删除失败", "路径:" .. line_file)
        goto resource_cleanup
    end

    if os.remove(file_path) then
        log.info("os.remove", "文件删除成功", "路径:" .. file_path)

        -- 验证删除结果
        if not io.exists(file_path) then
            log.info("验证结果", "boottime文件删除验证成功")
        else
            log.error("验证结果", "boottime文件删除验证失败")
        end
    else
        log.error("io.remove", "boottime文件删除失败", "路径:" .. file_path)
        goto resource_cleanup
    end

    -- 12. 删除目录（不能删除非空目录，所以在删除目录前要确保目录内没有文件或子目录）
    if io.rmdir(dir_path) then
        log.info("io.rmdir", "目录删除成功", "路径:" .. dir_path)

        -- 验证删除结果
        if not io.exists(dir_path) then
            log.info("验证结果", "目录删除验证成功")
        else
            log.error("验证结果", "目录删除验证失败")
        end
    else
        log.error("io.rmdir", "目录删除失败", "路径:" .. dir_path)
        goto resource_cleanup
    end

    log.info("文件操作", "===== 文件操作完成 =====")

    -- ########## 功能: 收尾功能演示##########
    -- 卸载文件系统和关闭SPI
    ::resource_cleanup::

    log.info("结束", "开始执行关闭操作...")  
    -- 如已挂载需先卸载文件系统，未挂载直接关闭SPI
    if mount_ok then
        if fatfs.unmount("/sd") then
            log.info("文件系统", "卸载成功")
        else
            log.error("文件系统", "卸载失败")
        end
    end

    -- 2. 关闭SPI接口
    spi.close(spi_id)
    log.info("SPI接口", "已关闭")

end

sys.taskInit(tfcard_main_task)


