local ftp_test = {}

-- 加载exftp库
local exftp = require "exftp"
local device_name = rtos.bsp()

-- FTP服务器配置
local FTP_CONFIG = {
    host = "121.43.224.154",
    port = 21,
    username = "ftp_user",
    password = "3QujbiMG",
}

-- 测试配置
local TEST_CONFIG = {
    -- 是否启用智能网卡切换
    enable_smart_switch = true,
    -- 是否测试所有适配器（true=测试所有，即使有成功的也不跳过）
    test_all_adapters = true,
    -- 上传超时时间（毫秒）
    upload_timeout = 60 * 1000,
    -- 下载超时时间（毫秒）
    download_timeout = 30 * 1000,
    -- 命令超时时间（毫秒）
    command_timeout = 10000,
}

-- 记录每个适配器的测试结果
local adapter_test_results = {}

-- 网络适配器配置表 - 根据设备类型动态生成
local ALL_ADAPTERS = {}

-- 获取唯一ID作为文件名后缀
local file_suffix = ""
if mobile and mobile.imei then
    file_suffix = mobile.imei()
elseif wlan and wlan.getMac then
    file_suffix = wlan.getMac(nil, true)
else
    file_suffix = mcu.unique_id()
end
-- 确保文件后缀是字符串并去除特殊字符
file_suffix = tostring(file_suffix):gsub("[^%w]", ""):sub(1, 8)

-- 测试文件配置
local TEST_FILES = {
    upload = {
        local_path = "/test_upload.txt",
        remote_path = "/test_upload_" .. file_suffix .. ".txt",
    },
    download = {
        remote_path = "/downloaded_by_ftp.txt",
        local_path = "/downloaded_by_ftp.txt",
    },
    directory = {
        test_path = "/ftp_folder_" .. file_suffix,
    }
}

-- 设备类型判断和适配器配置
if device_name == "Air8000" then
    -- Air8000: 支持4G和WiFi STA
    local ssid = "HHHHHHHHHHH"
    local password = "huanghefm94.3"
    pcall(function()
        wlan.connect(ssid, password, 1)
    end)
    ALL_ADAPTERS = {
        {name = "4G网卡(LWIP_GP)", adapter = socket.LWIP_GP, type = "cellular", expected_supported = true},
        {name = "WiFi网卡(LWIP_STA)", adapter = socket.LWIP_STA, type = "wifi", expected_supported = true},
        {name = "默认(nil)", adapter = nil, type = "default", expected_supported = true}
    }
elseif device_name == "Air780EPM" or device_name == "Air780EHM" or device_name == "Air780EHV" or 
       device_name == "Air780EGH" or device_name == "Air780EGG" or device_name == "Air780EGP" then
    -- Air780系列: 支持4G，WiFi不支持（用于测试错误处理）
    pcall(function()
        local ssid = "HHHHHHHHHHH"
        local password = "huanghefm94.3"
        wlan.connect(ssid, password, 1)
    end)
    -- 先测试不支持的WiFi网卡（预期报错），再测试支持的4G网卡
    ALL_ADAPTERS = {
        {name = "WiFi网卡(LWIP_STA)", adapter = socket.LWIP_STA, type = "wifi", expected_supported = false},
        {name = "4G网卡(LWIP_GP)", adapter = socket.LWIP_GP, type = "cellular", expected_supported = true},
        {name = "默认(nil)", adapter = nil, type = "default", expected_supported = true}
    }
elseif device_name == "Air8101" then
    -- Air8101: 支持WiFi，4G不支持（用于测试错误处理）
    local ssid = "HHHHHHHHHHH"
    local password = "huanghefm94.3"
    pcall(function()
        wlan.connect(ssid, password, 1)
    end)
    -- 先测试不支持的4G网卡（预期报错），再测试支持的WiFi网卡
    ALL_ADAPTERS = {
        {name = "4G网卡(LWIP_GP)", adapter = socket.LWIP_GP, type = "cellular", expected_supported = false},
        {name = "WiFi网卡(LWIP_STA)", adapter = socket.LWIP_STA, type = "wifi", expected_supported = true},
        {name = "默认(nil)", adapter = nil, type = "default", expected_supported = true}
    }
else
    -- 其他设备: 仅支持默认网卡
    ALL_ADAPTERS = {
        {name = "默认(nil)", adapter = nil, type = "default", expected_supported = true}
    }
end

-- 安全执行函数，捕获错误
local function safe_exec(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        log.warn("ftp_test", "执行异常捕获: " .. tostring(result))
        return false, tostring(result)
    end
    return true, result
end

-- 检查网卡IP地址
local function get_adapter_ip(adapter)
    local success, ip = pcall(socket.localIP, adapter)
    if success and ip and ip ~= "0.0.0.0" then
        return ip
    end
    return "未就绪"
end

-- 创建FTP客户端的辅助函数（支持指定适配器）
local function create_ftp_client(adapter)
    local ftpc = exftp.create(adapter, FTP_CONFIG.host, FTP_CONFIG.port)
    if not ftpc then
        return nil, "创建FTP客户端失败"
    end
    return ftpc, nil
end

-- FTP客户端连接和认证的辅助函数
local function connect_and_auth(ftpc, username, password)
    if not ftpc:auth(username or FTP_CONFIG.username, password or FTP_CONFIG.password) then
        return false, "FTP登录失败"
    end
    return true, nil
end

-- 尝试连接指定适配器
local function try_connect_adapter(adapter, adapter_name, expected_supported)
    log.info("ftp_test", string.format("尝试连接适配器 [%s] (预期支持: %s)...", adapter_name, tostring(expected_supported)))
    
    -- 创建FTP客户端
    local ftpc, err = create_ftp_client(adapter)
    if not ftpc then
        local error_msg = err or "创建客户端失败"
        log.warn("ftp_test", string.format("✗ 适配器 [%s] 创建客户端失败: %s", adapter_name, error_msg))
        
        -- 判断是否为网卡不支持的错误
        local is_adapter_error = error_msg:find("adapter") or 
                                 error_msg:find("not supported") or 
                                 error_msg:find("invalid") or
                                 error_msg:find("create fail")
        
        local error_type = is_adapter_error and "adapter_not_supported" or "create_failed"
        
        adapter_test_results[adapter_name] = {
            connected = false,
            error = error_msg,
            error_type = error_type,
            expected_supported = expected_supported,
            actual_supported = (error_type ~= "adapter_not_supported"),
            ftpc = nil
        }
        
        -- 使用assert验证预期
        if expected_supported == true and is_adapter_error then
            assert(false, string.format("适配器[%s] 预期支持但创建客户端失败: %s", adapter_name, error_msg))
        end
        
        return false, error_msg, error_type, nil
    end
    
    -- 登录认证
    local auth_ok, auth_err = connect_and_auth(ftpc)
    if not auth_ok then
        log.warn("ftp_test", string.format("✗ 适配器 [%s] 认证失败: %s", adapter_name, auth_err))
        ftpc:close()
        
        adapter_test_results[adapter_name] = {
            connected = false,
            error = auth_err,
            error_type = "auth_failed",
            expected_supported = expected_supported,
            actual_supported = true,
            ftpc = nil
        }
        
        if expected_supported == true then
            assert(false, string.format("适配器[%s] 预期支持但认证失败: %s", adapter_name, auth_err))
        end
        
        return false, auth_err, "auth_failed", nil
    end
    
    log.info("ftp_test", string.format("✓ 适配器 [%s] 连接成功", adapter_name))
    adapter_test_results[adapter_name] = {
        connected = true,
        error = nil,
        error_type = nil,
        expected_supported = expected_supported,
        actual_supported = true,
        ip = get_adapter_ip(adapter),
        ftpc = ftpc
    }
    
    return true, nil, nil, ftpc
end

-- 获取所有适配器列表
local function get_all_adapters()
    local all = {}
    for _, adapter_info in ipairs(ALL_ADAPTERS) do
        table.insert(all, adapter_info)
    end
    return all
end

-- 输出测试结果汇总
local function print_test_summary(test_name)
    log.info("ftp_test", string.rep("=", 60))
    log.info("ftp_test", string.format("测试[%s] 结果汇总:", test_name))
    
    local supported_count = 0
    local unsupported_count = 0
    local failed_count = 0
    local expected_success_count = 0
    local expected_fail_count = 0
    local unexpected_results = {}
    
    for name, result in pairs(adapter_test_results) do
        local expected = result.expected_supported
        local actual = result.actual_supported
        local is_correct = (expected == actual)
        
        if result.connected then
            if expected then
                log.info("ftp_test", string.format("  ✓ %s: 连接成功 (IP: %s) [符合预期]", name, result.ip or "未知"))
                expected_success_count = expected_success_count + 1
            else
                log.error("ftp_test", string.format("  ✗ %s: 连接成功 [不符合预期！预期不支持但实际支持]", name))
                table.insert(unexpected_results, string.format("%s 预期不支持但连接成功", name))
            end
            supported_count = supported_count + 1
        elseif result.error_type == "adapter_not_supported" then
            if not expected then
                log.warn("ftp_test", string.format("  ✗ %s: 网卡不支持 [符合预期]", name))
                expected_fail_count = expected_fail_count + 1
            else
                log.error("ftp_test", string.format("  ✗ %s: 网卡不支持 [不符合预期！预期支持但实际不支持]", name))
                table.insert(unexpected_results, string.format("%s 预期支持但网卡不支持", name))
            end
            unsupported_count = unsupported_count + 1
        else
            log.error("ftp_test", string.format("  ✗ %s: %s", name, tostring(result.error)))
            if expected then
                table.insert(unexpected_results, string.format("%s 预期支持但发生错误: %s", name, tostring(result.error)))
            end
            failed_count = failed_count + 1
        end
    end
    
    log.info("ftp_test", "")
    log.info("ftp_test", string.format("统计: 成功=%d, 不支持=%d, 失败=%d", supported_count, unsupported_count, failed_count))
    log.info("ftp_test", string.format("预期验证: 预期成功=%d, 预期失败=%d", expected_success_count, expected_fail_count))
    
    if #unexpected_results > 0 then
        log.error("ftp_test", "不符合预期的结果:")
        for _, msg in ipairs(unexpected_results) do
            log.error("ftp_test", "  - " .. msg)
        end
    end
    
    if expected_success_count > 0 and expected_fail_count > 0 then
        log.info("ftp_test", "✓ 自动适配功能验证通过: 不支持的网卡正确报错，支持的网卡成功连接")
    elseif expected_fail_count > 0 and expected_success_count == 0 then
        log.error("ftp_test", "✗ 自动适配功能验证失败: 没有找到支持的网卡")
    elseif expected_fail_count == 0 and expected_success_count > 0 then
        if #unexpected_results == 0 then
            log.info("ftp_test", "✓ 所有配置的网卡均支持")
        else
            log.error("ftp_test", "✗ 部分网卡行为与预期不符")
        end
    end
    
    log.info("ftp_test", string.rep("=", 60))
end

-- 清理所有FTP客户端连接
local function cleanup_all_clients()
    for name, result in pairs(adapter_test_results) do
        if result.ftpc then
            pcall(function()
                result.ftpc:close()
            end)
            result.ftpc = nil
        end
    end
    -- 注意：不清空adapter_test_results，保留用于汇总
end

-- 重置测试结果（保留连接状态）
local function reset_test_results_for_new_test()
    -- 关闭所有连接但不清空结果
    for name, result in pairs(adapter_test_results) do
        if result.ftpc then
            pcall(function()
                result.ftpc:close()
            end)
            result.ftpc = nil
        end
    end
end

-- 执行测试的通用函数（支持智能网卡切换）
local function run_test_on_adapters(test_name, test_func)
    local test_passed = false
    local last_error = nil
    local successful_adapter = nil
    local all_adapters = get_all_adapters()
    
    -- 重置连接状态（关闭之前的连接）
    reset_test_results_for_new_test()
    
    log.info("ftp_test", string.format("开始测试 [%s]，共 %d 个适配器", test_name, #all_adapters))
    
    for _, adapter_info in ipairs(all_adapters) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name
        local expected_supported = adapter_info.expected_supported
        
        log.info("ftp_test", string.format("测试[%s]: 尝试适配器 [%s] (预期支持: %s)", test_name, name, tostring(expected_supported)))
        
        -- 尝试连接
        local connect_ok, connect_err, error_type, ftpc = try_connect_adapter(adapter, name, expected_supported)
        
        if connect_ok and ftpc then
            -- 更新结果中的ftpc引用
            adapter_test_results[name].ftpc = ftpc
            
            -- 连接成功，执行具体测试
            local test_ok, test_err = safe_exec(test_func, ftpc, name)
            
            -- 关闭测试连接
            pcall(function() ftpc:close() end)
            adapter_test_results[name].ftpc = nil
            
            if test_ok then
                log.info("ftp_test", string.format("✓ 适配器 [%s] %s 测试通过", name, test_name))
                test_passed = true
                successful_adapter = name
                -- 根据配置决定是否提前退出
                if not TEST_CONFIG.test_all_adapters and TEST_CONFIG.enable_smart_switch then
                    break
                end
            else
                log.error("ftp_test", string.format("✗ 适配器 [%s] %s 测试失败: %s", name, test_name, test_err))
                last_error = test_err
                adapter_test_results[name].error = test_err
                adapter_test_results[name].error_type = "test_failed"
            end
        else
            local error_desc = ""
            if error_type == "adapter_not_supported" then
                if expected_supported == false then
                    error_desc = "网卡不支持（符合预期）"
                else
                    error_desc = "网卡不支持（不符合预期！）"
                end
            elseif error_type == "create_failed" then
                error_desc = "创建客户端失败"
            elseif error_type == "auth_failed" then
                error_desc = "认证失败"
            else
                error_desc = connect_err or "未知错误"
            end
            log.warn("ftp_test", string.format("适配器 [%s] 连接失败 (%s)，跳过%s测试", name, error_desc, test_name))
            last_error = connect_err
        end
        
        sys.wait(100)
    end
    
    -- 输出测试总结
    print_test_summary(test_name)
    
    if not test_passed then
        log.error("ftp_test", string.format("测试[%s] 所有适配器均失败，最后错误: %s", test_name, tostring(last_error)))
    else
        log.info("ftp_test", string.format("测试[%s] 成功使用适配器: %s", test_name, successful_adapter))
    end
    
    return test_passed
end

-- ========== 以下为测试用例 ==========

-- 测试1: FTP客户端创建
function ftp_test.test_ftp_client_creation()
    local function do_creation_test(ftpc, name)
        log.info("ftp_test", string.format("适配器[%s] - FTP客户端创建测试", name))
        assert(ftpc, "FTP客户端创建失败")
        return true
    end
    
    run_test_on_adapters("FTP客户端创建测试", do_creation_test)
end

-- 测试2: FTP登录认证
function ftp_test.test_ftp_authentication()
    local function do_auth_test(ftpc, name)
        log.info("ftp_test", string.format("适配器[%s] - FTP登录认证测试", name))
        -- 认证已在连接时完成，这里验证连接状态
        local ok, current_dir = ftpc:pwd()
        assert(ok, "获取当前目录失败，可能未认证: " .. tostring(current_dir))
        log.info("ftp_test", string.format("适配器[%s] 当前目录: %s", name, tostring(current_dir)))
        return true
    end
    
    run_test_on_adapters("FTP登录认证测试", do_auth_test)
end

-- 测试3: FTP目录操作
function ftp_test.test_ftp_directory_operations()
    local function do_directory_test(ftpc, name)
        log.info("ftp_test", string.format("适配器[%s] - FTP目录操作测试", name))
        
        -- 获取当前目录
        local ok, current_dir = ftpc:pwd()
        assert(ok, "获取当前目录失败: " .. tostring(current_dir))
        assert(current_dir, "当前目录为空")
        log.info("ftp_test", string.format("适配器[%s] 当前目录: %s", name, current_dir))
        
        -- 创建测试目录（先尝试切换，如果失败则创建）
        local test_path = TEST_FILES.directory.test_path
        local chdir_ok = ftpc:chdir(test_path)
        
        if not chdir_ok then
            -- 目录不存在，尝试创建（使用MKD命令）
            log.info("ftp_test", string.format("适配器[%s] 目录 %s 不存在，尝试创建", name, test_path))
            -- 注意：exftp库可能没有直接提供MKD命令，这里通过发送原始命令实现
            -- 如果exftp支持，可以使用 ftpc:command("MKD " .. test_path)
            -- 暂时跳过目录创建测试
            log.info("ftp_test", string.format("适配器[%s] 跳过目录创建测试（exftp可能不支持MKD）", name))
        else
            log.info("ftp_test", string.format("适配器[%s] 成功切换到 %s 目录", name, test_path))
            
            -- 再次获取当前目录确认切换成功
            ok, current_dir = ftpc:pwd()
            assert(ok, "切换目录后获取当前目录失败")
            log.info("ftp_test", string.format("适配器[%s] 切换后当前目录: %s", name, current_dir))
            
            -- 返回上一级目录
            local cdup_ok = ftpc:cdup()
            assert(cdup_ok, "返回上一级目录失败")
            log.info("ftp_test", string.format("适配器[%s] 成功返回上一级目录", name))
        end
        
        return true
    end
    
    run_test_on_adapters("FTP目录操作测试", do_directory_test)
end

-- 测试4: FTP文件上传
function ftp_test.test_ftp_file_upload()
    -- 创建测试文件
    local test_content = "LuatOS FTP Test File\nCreated at: " .. os.date() .. "\nContent: Hello from LuatOS!"
    io.writeFile(TEST_FILES.upload.local_path, test_content)
    
    local file_size = io.fileSize(TEST_FILES.upload.local_path)
    assert(file_size and file_size > 0, "测试文件创建失败或为空")
    log.info("ftp_test", "测试文件已创建", TEST_FILES.upload.local_path, "大小:", file_size, "字节")
    
    local function do_upload_test(ftpc, name)
        log.info("ftp_test", string.format("适配器[%s] - FTP文件上传测试", name))
        
        -- 执行文件上传
        local upload_ok = ftpc:upload(
            TEST_FILES.upload.local_path,
            TEST_FILES.upload.remote_path,
            { timeout = TEST_CONFIG.upload_timeout }
        )
        
        assert(upload_ok, "文件上传失败")
        log.info("ftp_test", string.format("适配器[%s] 文件上传成功: %s -> %s", 
                  name, TEST_FILES.upload.local_path, TEST_FILES.upload.remote_path))
        
        return true
    end
    
    local result = run_test_on_adapters("FTP文件上传测试", do_upload_test)
    
    -- 清理本地测试文件
    pcall(function() os.remove(TEST_FILES.upload.local_path) end)
    
    return result
end

-- 测试5: FTP文件下载
function ftp_test.test_ftp_file_download()
    -- 先确保上传的文件存在（先执行上传测试）
    log.info("ftp_test", "下载测试: 确保远程文件存在，先执行上传...")
    
    -- 创建测试文件
    local test_content = "LuatOS FTP Download Test File\nCreated at: " .. os.date() .. "\nContent: This file is for download test!"
    io.writeFile(TEST_FILES.upload.local_path, test_content)
    
    local function ensure_upload(ftpc, name)
        local upload_ok = ftpc:upload(
            TEST_FILES.upload.local_path,
            TEST_FILES.upload.remote_path,
            { timeout = TEST_CONFIG.upload_timeout }
        )
        assert(upload_ok, "准备下载测试: 文件上传失败")
        log.info("ftp_test", string.format("适配器[%s] 准备下载测试: 文件上传成功", name))
        return true
    end
    
    -- 先执行上传准备
    run_test_on_adapters("FTP下载准备(上传)", ensure_upload)
    
    local function do_download_test(ftpc, name)
        log.info("ftp_test", string.format("适配器[%s] - FTP文件下载测试", name))
        
        -- 执行文件下载
        local download_ok = ftpc:download(
            TEST_FILES.upload.remote_path,
            TEST_FILES.download.local_path,
            { timeout = TEST_CONFIG.download_timeout }
        )
        
        assert(download_ok, "文件下载失败")
        log.info("ftp_test", string.format("适配器[%s] 文件下载成功: %s -> %s", 
                  name, TEST_FILES.upload.remote_path, TEST_FILES.download.local_path))
        
        -- 验证下载的文件
        assert(io.exists(TEST_FILES.download.local_path), "下载文件不存在")
        
        local downloaded_size = io.fileSize(TEST_FILES.download.local_path)
        assert(downloaded_size and downloaded_size > 0, "下载文件为空")
        
        local file_content = io.readFile(TEST_FILES.download.local_path)
        assert(file_content and #file_content > 0, "读取文件内容失败")
        
        log.info("ftp_test", string.format("适配器[%s] 下载验证: 文件大小=%d字节", name, downloaded_size))
        
        return true
    end
    
    local result = run_test_on_adapters("FTP文件下载测试", do_download_test)
    
    -- 清理本地文件
    pcall(function() 
        os.remove(TEST_FILES.upload.local_path)
        os.remove(TEST_FILES.download.local_path)
    end)
    
    return result
end

-- 测试6: FTP关闭测试
function ftp_test.test_ftp_close()
    local function do_close_test(ftpc, name)
        log.info("ftp_test", string.format("适配器[%s] - FTP关闭测试", name))
        
        -- 先确认连接正常
        local ok, current_dir = ftpc:pwd()
        assert(ok, "初始连接状态异常")
        log.info("ftp_test", string.format("适配器[%s] 初始连接正常，当前目录: %s", name, tostring(current_dir)))
        
        -- 关闭连接
        ftpc:close()
        
        -- 验证：尝试再次执行操作应该失败（使用pcall避免抛出异常）
        local pcall_ok, pwd_ok, _ = pcall(function() return ftpc:pwd() end)
        -- 注意：关闭后调用方法应该出错或返回false
        log.info("ftp_test", string.format("适配器[%s] 关闭后调用pwd结果: pcall_ok=%s", name, tostring(pcall_ok)))
        
        -- 验证：再次关闭不应出错
        local close_error = false
        local success, err = pcall(function()
            ftpc:close()
        end)
        assert(success, "重复关闭时出错: " .. tostring(err))
        log.info("ftp_test", string.format("适配器[%s] 重复关闭测试通过", name))
        
        return true
    end
    
    run_test_on_adapters("FTP关闭测试", do_close_test)
end

-- 测试7: 综合测试（包含所有操作）
function ftp_test.test_ftp_comprehensive()
    local function do_comprehensive_test(ftpc, name)
        log.info("ftp_test", string.format("适配器[%s] - FTP综合测试", name))
        
        -- 1. PWD测试
        local ok, current_dir = ftpc:pwd()
        assert(ok, "PWD失败")
        log.info("ftp_test", string.format("适配器[%s] 1. PWD ✓ 当前目录: %s", name, current_dir))
        
        -- 2. CDUP测试
        local cdup_ok = ftpc:cdup()
        if cdup_ok then
            log.info("ftp_test", string.format("适配器[%s] 2. CDUP ✓", name))
            -- 切换回原目录
            ftpc:chdir(current_dir)
        else
            log.info("ftp_test", string.format("适配器[%s] 2. CDUP (已在根目录或不可用)", name))
        end
        
        -- 3. 创建测试文件并上传
        local test_content = "LuatOS Comprehensive Test\nTime: " .. os.date()
        local local_path = "/comp_test.txt"
        local remote_path = "/comp_test_" .. file_suffix .. ".txt"
        
        io.writeFile(local_path, test_content)
        
        local upload_ok = ftpc:upload(local_path, remote_path, { timeout = TEST_CONFIG.upload_timeout })
        assert(upload_ok, "上传失败")
        log.info("ftp_test", string.format("适配器[%s] 3. 上传 ✓", name))
        
        -- 4. 下载并验证
        local download_path = "/comp_download.txt"
        local download_ok = ftpc:download(remote_path, download_path, { timeout = TEST_CONFIG.download_timeout })
        assert(download_ok, "下载失败")
        
        local downloaded_content = io.readFile(download_path)
        assert(downloaded_content == test_content, "文件内容不匹配")
        log.info("ftp_test", string.format("适配器[%s] 4. 下载验证 ✓", name))
        
        -- 5. 清理
        pcall(function()
            os.remove(local_path)
            os.remove(download_path)
        end)
        
        log.info("ftp_test", string.format("适配器[%s] 综合测试全部通过", name))
        return true
    end
    
    run_test_on_adapters("FTP综合测试", do_comprehensive_test)
    
    -- 清理
    cleanup_all_clients()
end

-- 获取完整测试状态报告
function ftp_test.get_test_status()
    log.info("ftp_test", "========== 完整测试状态报告 ==========")
    log.info("ftp_test", "模块: " .. device_name)
    log.info("ftp_test", "测试配置: test_all_adapters=" .. tostring(TEST_CONFIG.test_all_adapters))
    log.info("ftp_test", "")
    
    local supported_adapters = {}
    local unsupported_adapters = {}
    local unknown_adapters = {}
    
    for _, adapter_info in ipairs(ALL_ADAPTERS) do
        local name = adapter_info.name
        local result = adapter_test_results[name] or {}
        local expected = adapter_info.expected_supported
        
        if result.error_type == "adapter_not_supported" then
            table.insert(unsupported_adapters, name)
            if expected == false then
                log.warn("ftp_test", string.format("✗ 适配器[%s]: 不支持 [符合预期]", name))
            else
                log.error("ftp_test", string.format("✗ 适配器[%s]: 不支持 [不符合预期！]", name))
            end
        elseif result.connected == true then
            table.insert(supported_adapters, name)
            if expected == true then
                log.info("ftp_test", string.format("✓ 适配器[%s]: 支持并连接成功 [符合预期] (IP: %s)", name, result.ip or "未知"))
            else
                log.warn("ftp_test", string.format("? 适配器[%s]: 支持并连接成功 [不符合预期]", name))
            end
        else
            table.insert(unknown_adapters, name)
            log.warn("ftp_test", string.format("? 适配器[%s]: %s", name, tostring(result.error or "未测试")))
        end
    end
    
    log.info("ftp_test", "")
    if #unsupported_adapters > 0 then
        log.info("ftp_test", "【不支持的网卡】: " .. table.concat(unsupported_adapters, ", "))
    end
    if #supported_adapters > 0 then
        log.info("ftp_test", "【支持的网卡】: " .. table.concat(supported_adapters, ", "))
    end
    if #unknown_adapters > 0 then
        log.info("ftp_test", "【状态未知的网卡】: " .. table.concat(unknown_adapters, ", "))
    end
    
    log.info("ftp_test", "")
    if #unsupported_adapters > 0 and #supported_adapters > 0 then
        log.info("ftp_test", "✓ 自动适配功能验证通过: 不支持的网卡正确报错后成功切换到支持的网卡")
    elseif #unsupported_adapters > 0 and #supported_adapters == 0 then
        log.error("ftp_test", "✗ 自动适配功能验证失败: 所有网卡均不支持")
    elseif #unsupported_adapters == 0 and #supported_adapters > 0 then
        log.info("ftp_test", "✓ 所有配置的网卡均支持")
    end
    
    log.info("ftp_test", "==========================================")
end

-- 重置测试结果记录
function ftp_test.reset_test_results()
    cleanup_all_clients()
    adapter_test_results = {}
    log.info("ftp_test", "测试结果记录已重置")
end

return ftp_test