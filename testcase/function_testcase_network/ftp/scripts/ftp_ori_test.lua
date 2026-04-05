local ftp_ori_test = {}
local device_name = rtos.bsp()

-- FTP服务器配置
local FTP_SERVER_CONFIG = {
    host = "121.43.224.154",
    port = 21,
    username = "ftp_user",
    password = "3QujbiMG"
}

-- 测试配置
local TEST_CONFIG = {
    -- 是否启用智能网卡切换（当某个适配器连接失败时自动尝试其他适配器）
    enable_smart_switch = true,
    -- 是否在连接前检查网卡就绪（false=直接尝试连接，捕获错误，用于测试不支持的网卡）
    precheck_adapter_ready = false,
    -- 是否测试所有适配器（true=测试所有，即使有成功的也不跳过）
    test_all_adapters = true,
    -- 连接超时时间（毫秒）
    connect_timeout = 10000,
    -- 命令执行超时时间（毫秒）
    command_timeout = 5000,
    -- 文件传输超时时间（毫秒）
    transfer_timeout = 15000
}

-- 记录每个适配器的测试结果（包括错误信息）
local adapter_test_results = {}

-- 网络适配器配置表 - 根据设备类型动态生成
local ALL_ADAPTERS = {}

-- 设备类型判断和适配器配置
if device_name == "Air8000" then
    -- Air8000: 支持4G和WiFi STA
    local ssid = "luatos1234"
    local password = "12341234"
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
        local ssid = "luatos1234"
        local password = "12341234"
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
    local ssid = "luatos1234"
    local password = "12341234"
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

-- 确保FTP连接已关闭（带错误捕获）
local function ensure_ftp_closed()
    pcall(function()
        ftp.close().wait()
    end)
    sys.wait(50)
end

-- 检查网卡是否就绪（可选，用于调试）
local function is_adapter_ready(adapter)
    if adapter == nil then
        local is_ready = socket.adapter()
        return is_ready == true
    else
        local is_ready = socket.adapter(adapter)
        return is_ready == true
    end
end

-- 获取网卡IP地址
local function get_adapter_ip(adapter)
    local success, ip = pcall(socket.localIP, adapter)
    if success and ip and ip ~= "0.0.0.0" then
        return ip
    end
    return "未就绪"
end

-- 打印测试开始信息
local function test_start(adapter_name, name)
    log.info("ftp_test", string.rep("=", 40))
    log.info("ftp_test", string.format("适配器 [%s] - 测试: %s", adapter_name, name))
    log.info("ftp_test", string.rep("=", 40))
    ensure_ftp_closed()
end

-- 尝试连接指定适配器（不预先检查网卡状态，直接尝试，用于捕获错误）
local function try_connect_adapter(adapter, adapter_name, expected_supported)
    log.info("ftp_test", string.format("尝试连接适配器 [%s] (预期支持: %s)...", adapter_name, tostring(expected_supported)))
    
    -- 可选：打印网卡状态用于调试
    if TEST_CONFIG.precheck_adapter_ready then
        if not is_adapter_ready(adapter) then
            log.warn("ftp_test", string.format("适配器 [%s] 网卡未就绪 (IP: %s)", 
                      adapter_name, get_adapter_ip(adapter)))
            adapter_test_results[adapter_name] = {
                connected = false, 
                error = "网卡未就绪",
                error_type = "adapter_not_ready",
                expected_supported = expected_supported,
                actual_supported = false
            }
            -- 如果预期支持但网卡未就绪，断言失败
            if expected_supported == true then
                assert(false, string.format("适配器[%s] 预期支持但网卡未就绪!", adapter_name))
            end
            return false, "网卡未就绪", "adapter_not_ready"
        end
        log.info("ftp_test", string.format("适配器 [%s] 网卡已就绪 (IP: %s)", 
                  adapter_name, get_adapter_ip(adapter)))
    end
    
    ensure_ftp_closed()
    
    -- 直接尝试登录，捕获所有错误
    local login_success = false
    local error_msg = nil
    local error_type = nil
    
    local ok, result = pcall(function()
        return ftp.login(adapter, FTP_SERVER_CONFIG.host, FTP_SERVER_CONFIG.port, 
                         FTP_SERVER_CONFIG.username, FTP_SERVER_CONFIG.password).wait()
    end)
    
    if not ok then
        error_msg = "接口调用异常: " .. tostring(result)
        -- 判断错误类型
        local err_str = tostring(result)
        -- 关键修改：增加对返回值 -9 的判断（adapter index is invalid）
        -- 以及更全面的网卡不支持错误检测
        local is_adapter_error = err_str:find("adapter") or 
                                 err_str:find("not supported") or 
                                 err_str:find("invalid") or 
                                 err_str:find("-9") or
                                 err_str:find("create fail") or
                                 (err_str:find("返回值: -9"))
        
        if is_adapter_error then
            error_type = "adapter_not_supported"
            -- 使用 assert 验证：不支持的网卡应该报错
            if expected_supported == true then
                -- 预期支持但实际不支持，断言失败
                assert(false, string.format("适配器[%s] 预期支持但实际不支持！错误: %s", adapter_name, error_msg))
            else
                -- 预期不支持且实际不支持，断言成功（不抛出）
                log.warn("ftp_test", string.format("✗ 适配器 [%s] 网卡不支持（符合预期）: %s", adapter_name, error_msg))
            end
        elseif err_str:find("timeout") then
            error_type = "timeout"
            log.warn("ftp_test", string.format("✗ 适配器 [%s] 连接超时: %s", adapter_name, error_msg))
            if expected_supported == true then
                assert(false, string.format("适配器[%s] 预期支持但连接超时!", adapter_name))
            end
        else
            error_type = "pcall_error"
            log.warn("ftp_test", string.format("✗ 适配器 [%s] %s", adapter_name, error_msg))
            if expected_supported == true then
                assert(false, string.format("适配器[%s] 预期支持但发生异常: %s", adapter_name, error_msg))
            end
        end
        
        adapter_test_results[adapter_name] = {
            connected = false, 
            error = error_msg,
            error_type = error_type,
            expected_supported = expected_supported,
            actual_supported = (error_type ~= "adapter_not_supported")
        }
        return false, error_msg, error_type
    end
    
    login_success = (result == true)
    
    if login_success then
        -- 使用 assert 验证：如果预期不支持但实际连接成功，断言失败
        if expected_supported == false then
            assert(false, string.format("适配器[%s] 预期不支持但实际连接成功！这可能是意外的行为", adapter_name))
        end
        log.info("ftp_test", string.format("✓ 适配器 [%s] 连接成功", adapter_name))
        adapter_test_results[adapter_name] = {
            connected = true, 
            error = nil,
            error_type = nil,
            expected_supported = expected_supported,
            actual_supported = true,
            ip = get_adapter_ip(adapter)
        }
        return true, nil, nil
    else
        error_msg = "FTP登录失败，返回值: " .. tostring(result)
        error_type = "login_failed"
        log.warn("ftp_test", string.format("✗ 适配器 [%s] %s", adapter_name, error_msg))
        if expected_supported == true then
            assert(false, string.format("适配器[%s] 预期支持但FTP登录失败: %s", adapter_name, error_msg))
        end
        adapter_test_results[adapter_name] = {
            connected = false, 
            error = error_msg,
            error_type = error_type,
            expected_supported = expected_supported,
            actual_supported = true
        }
        ensure_ftp_closed()
        return false, error_msg, error_type
    end
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
        elseif result.error_type == "adapter_not_ready" then
            log.warn("ftp_test", string.format("  ? %s: 网卡未就绪 [状态未知]", name))
            failed_count = failed_count + 1
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

-- 执行测试的通用函数（支持智能网卡切换和错误捕获）
local function run_test_on_adapters(test_name, test_func)
    local test_passed = false
    local last_error = nil
    local successful_adapter = nil
    local all_adapters = get_all_adapters()
    
    log.info("ftp_test", string.format("开始测试 [%s]，共 %d 个适配器", test_name, #all_adapters))
    
    for _, adapter_info in ipairs(all_adapters) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name
        local expected_supported = adapter_info.expected_supported
        
        log.info("ftp_test", string.format("测试[%s]: 尝试适配器 [%s] (预期支持: %s)", test_name, name, tostring(expected_supported)))
        
        -- 尝试连接（会捕获所有错误，内部包含assert验证）
        local connect_ok, connect_err, error_type = try_connect_adapter(adapter, name, expected_supported)
        
        if connect_ok then
            -- 连接成功，执行具体测试
            local test_ok, test_err = safe_exec(test_func, adapter, name)
            
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
                -- 如果预期支持但测试失败，断言
                if expected_supported == true then
                    assert(false, string.format("适配器[%s] 预期支持但测试失败: %s", name, test_err))
                end
            end
        else
            -- 记录错误类型，用于后续分析
            local error_desc = ""
            if error_type == "adapter_not_supported" then
                if expected_supported == false then
                    error_desc = "网卡不支持（符合预期）"
                else
                    error_desc = "网卡不支持（不符合预期！）"
                end
            elseif error_type == "adapter_not_ready" then
                error_desc = "网卡未就绪"
            elseif error_type == "timeout" then
                error_desc = "连接超时"
            elseif error_type == "pcall_error" then
                error_desc = "接口调用异常"
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

-- FTP登录测试
function ftp_ori_test.test_ftp_login()
    local function do_login_test(adapter, name)
        test_start(name, "FTP登录测试")
        
        local login_result = ftp.login(adapter, FTP_SERVER_CONFIG.host, FTP_SERVER_CONFIG.port,
                                       FTP_SERVER_CONFIG.username, FTP_SERVER_CONFIG.password).wait()
        
        assert(login_result == true, string.format("FTP登录失败，返回值: %s", tostring(login_result)))
        
        log.info("ftp_test", string.format("适配器[%s] FTP登录测试通过", name))
        return true
    end
    
    run_test_on_adapters("FTP登录测试", do_login_test)
end

-- FTP基本命令测试
function ftp_ori_test.test_ftp_commands()
    local function do_commands_test(adapter, name)
        test_start(name, "FTP基本命令测试")
        
        -- 登录
        local login_result = ftp.login(adapter, FTP_SERVER_CONFIG.host, FTP_SERVER_CONFIG.port,
                                       FTP_SERVER_CONFIG.username, FTP_SERVER_CONFIG.password).wait()
        assert(login_result == true, string.format("FTP登录失败: %s", tostring(login_result)))
        
        -- NOOP命令测试
        local noop_result = ftp.command("NOOP").wait()
        local cleaned_noop_result = tostring(noop_result):match("^%s*(.-)%s*$"):gsub("%s+", " ")
        assert(cleaned_noop_result == "200 NOOP ok.",
            string.format("NOOP命令失败: 预期'200 NOOP ok.',实际'%s'", cleaned_noop_result))
        log.info("ftp_test", string.format("适配器[%s] NOOP命令测试通过", name))
        
        -- SYST命令测试
        local syst_result = ftp.command("SYST").wait()
        local cleaned_syst_result = tostring(syst_result):match("^%s*(.-)%s*$"):gsub("%s+", " ")
        assert(cleaned_syst_result == "215 UNIX Type: L8",
            string.format("SYST命令失败: 预期'215 UNIX Type: L8',实际'%s'", cleaned_syst_result))
        log.info("ftp_test", string.format("适配器[%s] SYST命令测试通过", name))
        
        -- TYPE I命令测试
        local type_result = ftp.command("TYPE I").wait()
        local cleaned_type_result = tostring(type_result):match("^%s*(.-)%s*$"):gsub("%s+", " ")
        assert(cleaned_type_result == "200 Switching to Binary mode.",
            string.format("TYPE I命令失败: 预期'200 Switching to Binary mode.',实际'%s'", cleaned_type_result))
        log.info("ftp_test", string.format("适配器[%s] TYPE I命令测试通过", name))
        
        -- PWD命令测试
        local pwd_result = ftp.command("PWD").wait()
        local cleaned_pwd_result = tostring(pwd_result):match("^%s*(.-)%s*$"):gsub("%s+", " ")
        assert(cleaned_pwd_result:find("257") and cleaned_pwd_result:find("/"),
            string.format("PWD命令失败: 预期包含'257'和'/',实际'%s'", cleaned_pwd_result))
        log.info("ftp_test", string.format("适配器[%s] PWD命令测试通过", name))
        
        -- MKD命令测试
        local mkd_result = ftp.command("MKD DADT").wait()
        local cleaned_mkd_result = tostring(mkd_result):match("^%s*(.-)%s*$"):gsub("%s+", " ")
        if cleaned_mkd_result:find("550") then
            ftp.command("CDUP").wait()
            ftp.command("RMD DADT").wait()
            sys.wait(100)
            mkd_result = ftp.command("MKD DADT").wait()
            cleaned_mkd_result = tostring(mkd_result):match("^%s*(.-)%s*$"):gsub("%s+", " ")
        end
        assert(tostring(cleaned_mkd_result):find("257") and tostring(cleaned_mkd_result):find("DADT"),
            string.format("MKD命令失败: 预期包含257和DADT,实际'%s'", cleaned_mkd_result))
        log.info("ftp_test", string.format("适配器[%s] MKD命令测试通过", name))
        
        -- CWD命令测试
        local cwd_result = ftp.command("CWD /DADT").wait()
        local cleaned_cwd_result = tostring(cwd_result):match("^%s*(.-)%s*$"):gsub("%s+", " ")
        assert(tostring(cleaned_cwd_result):find("250"),
            string.format("CWD命令失败: 预期250,实际'%s'", cleaned_cwd_result))
        log.info("ftp_test", string.format("适配器[%s] CWD命令测试通过", name))
        
        -- CDUP命令测试
        local cdup_result = ftp.command("CDUP").wait()
        local cleaned_cdup_result = tostring(cdup_result):match("^%s*(.-)%s*$"):gsub("%s+", " ")
        assert(tostring(cleaned_cdup_result):find("250"),
            string.format("CDUP命令失败: 预期250,实际'%s'", cleaned_cdup_result))
        log.info("ftp_test", string.format("适配器[%s] CDUP命令测试通过", name))
        
        -- RMD命令测试
        local rmd_result = ftp.command("RMD DADT").wait()
        local cleaned_rmd_result = tostring(rmd_result):match("^%s*(.-)%s*$"):gsub("%s+", " ")
        assert(cleaned_rmd_result == "250 Remove directory operation successful.",
            string.format("RMD命令失败: 预期'250...',实际'%s'", cleaned_rmd_result))
        log.info("ftp_test", string.format("适配器[%s] RMD命令测试通过", name))
        
        return true
    end
    
    run_test_on_adapters("FTP基本命令测试", do_commands_test)
end

-- FTP文件传输测试
function ftp_ori_test.test_ftp_file_transfer()
    local function do_transfer_test(adapter, name)
        test_start(name, "FTP文件传输测试")
        
        -- 登录
        local login_result = ftp.login(adapter, FTP_SERVER_CONFIG.host, FTP_SERVER_CONFIG.port,
                                       FTP_SERVER_CONFIG.username, FTP_SERVER_CONFIG.password).wait()
        assert(login_result == true, string.format("FTP登录失败: %s", tostring(login_result)))
        
        -- 创建测试文件并上传
        local test_content = "我是创建文件，文件名是bootime，即将上传ftp服务器"
        io.writeFile("/bootime.txt", test_content)
        local local_file = "/bootime.txt"
        local remote_file = "/uploaded_by_bootime.txt"
        
        local push_result = ftp.push(local_file, remote_file).wait()
        assert(push_result == true, string.format("push命令上传失败: %s", tostring(push_result)))
        log.info("ftp_test", string.format("适配器[%s] push命令上传文件测试通过", name))
        
        -- 下载文件
        local local_file_second = "/ftp_download.txt"
        local download_result = ftp.pull(local_file_second, remote_file).wait()
        assert(download_result == true, string.format("pull命令下载失败: %s", tostring(download_result)))
        log.info("ftp_test", string.format("适配器[%s] pull命令下载文件测试通过", name))
        
        -- 验证文件存在
        assert(io.exists(local_file_second) == true,
            string.format("下载文件不存在: %s", local_file_second))
        
        -- 验证文件内容
        local full_data_content = io.readFile(local_file_second)
        local full_data_size = #full_data_content
        local file_content_size = #test_content
        
        assert(full_data_size == file_content_size,
            string.format("文件大小不匹配: 预期%d,实际%d", file_content_size, full_data_size))
        
        assert(tostring(full_data_content) == test_content,
            string.format("文件内容不匹配: 预期'%s',实际'%s'", test_content, tostring(full_data_content)))
        log.info("ftp_test", string.format("适配器[%s] 文件内容验证通过", name))
        
        -- LIST命令测试
        local list_result = ftp.command("LIST " .. remote_file).wait()
        assert(list_result and #tostring(list_result) > 0,
            string.format("LIST命令失败: %s", tostring(list_result)))
        log.info("ftp_test", string.format("适配器[%s] LIST命令测试通过", name))
        
        -- DELE命令测试
        local dele_result = ftp.command("DELE /uploaded_by_bootime.txt").wait()
        local cleaned_dele_result = tostring(dele_result):match("^%s*(.-)%s*$"):gsub("%s+", " ")
        assert(cleaned_dele_result == "250 Delete operation successful.",
            string.format("DELE命令失败: 预期'250...',实际'%s'", cleaned_dele_result))
        log.info("ftp_test", string.format("适配器[%s] DELE命令测试通过", name))
        
        -- 验证文件已删除
        local local_file_third = "/ftp_download_third.txt"
        local download_result_again = ftp.pull(local_file_third, remote_file).wait()
        assert(download_result_again == false,
            "DELE删除验证失败: 文件仍然存在")
        log.info("ftp_test", string.format("适配器[%s] DELE删除验证通过", name))
        
        -- 清理本地文件
        pcall(function()
            os.remove("/bootime.txt")
            os.remove("/ftp_download.txt")
            os.remove("/ftp_download_third.txt")
        end)
        
        return true
    end
    
    run_test_on_adapters("FTP文件传输测试", do_transfer_test)
end

-- FTP debug测试
function ftp_ori_test.test_ftp_debug()
    local function do_debug_test(adapter, name)
        test_start(name, "FTP debug命令测试")
        
        local login_result = ftp.login(adapter, FTP_SERVER_CONFIG.host, FTP_SERVER_CONFIG.port,
                                       FTP_SERVER_CONFIG.username, FTP_SERVER_CONFIG.password).wait()
        assert(login_result == true, string.format("FTP登录失败: %s", tostring(login_result)))
        
        local ftp_debug_result = ftp.debug(true)
        assert(ftp_debug_result == nil,
            string.format("debug命令失败: 预期nil,实际%s", tostring(ftp_debug_result)))
        
        log.info("ftp_test", string.format("适配器[%s] debug命令测试通过", name))
        return true
    end
    
    run_test_on_adapters("FTP debug测试", do_debug_test)
end

-- FTP close测试
function ftp_ori_test.test_ftp_close()
    local function do_close_test(adapter, name)
        test_start(name, "FTP close命令测试")
        
        local login_result = ftp.login(adapter, FTP_SERVER_CONFIG.host, FTP_SERVER_CONFIG.port,
                                       FTP_SERVER_CONFIG.username, FTP_SERVER_CONFIG.password).wait()
        assert(login_result == true, string.format("FTP登录失败: %s", tostring(login_result)))
        
        local ftp_close_result = ftp.close().wait()
        local cleaned_close_result = tostring(ftp_close_result):match("^%s*(.-)%s*$"):gsub("%s+", " ")
        assert(cleaned_close_result == "221 Goodbye.",
            string.format("close命令失败: 预期'221 Goodbye.',实际'%s'", cleaned_close_result))
        
        log.info("ftp_test", string.format("适配器[%s] close命令测试通过", name))
        return true
    end
    
    run_test_on_adapters("FTP close测试", do_close_test)
end

-- 获取完整测试状态报告
function ftp_ori_test.get_test_status()
    log.info("ftp_test", "========== 完整测试状态报告 ==========")
    log.info("ftp_test", "模块: " .. device_name)
    log.info("ftp_test", "测试配置: precheck_adapter_ready=" .. tostring(TEST_CONFIG.precheck_adapter_ready))
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
        elseif result.error_type == "adapter_not_ready" then
            table.insert(unknown_adapters, name)
            log.warn("ftp_test", string.format("? 适配器[%s]: 网卡未就绪", name))
        elseif result.error then
            table.insert(unknown_adapters, name)
            log.warn("ftp_test", string.format("? 适配器[%s]: %s", name, tostring(result.error)))
        else
            table.insert(unknown_adapters, name)
            log.warn("ftp_test", string.format("? 适配器[%s]: 未测试", name))
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
function ftp_ori_test.reset_test_results()
    adapter_test_results = {}
    log.info("ftp_test", "测试结果记录已重置")
end

return ftp_ori_test