local ftp_ori_test = {}
local device_name = rtos.bsp()

-- FTP服务器配置
local FTP_SERVER_CONFIG = {
    host = "121.43.224.154",
    port = 21,
    username = "ftp_user",
    password = "3QujbiMG"
}

local ALL_ADAPTERS = {}
if device_name == "Air8000" then
    local ssid = "luatos1234"
    local password = "12341234"
    wlan.connect(ssid, password, 1)
    -- 所有可用的网络适配器列表
    ALL_ADAPTERS = {{
        name = "默认(nil)",
        adapter = nil
    }, {
        name = "LWIP_GP",
        adapter = socket.LWIP_GP
    }, {
        name = "LWIP_STA",
        adapter = socket.LWIP_STA
    }}
elseif device_name == "Air780EPM" or device_name == "Air780EHM" then
    -- 所有可用的网络适配器列表
    ALL_ADAPTERS = {{
        name = "默认(nil)",
        adapter = nil
    }, {
        name = "LWIP_GP",
        adapter = socket.LWIP_GP
    }}
elseif device_name == "Air8101" then
    local ssid = "luatos1234"
    local password = "12341234"
    wlan.connect(ssid, password, 1)
    -- 所有可用的网络适配器列表
    ALL_ADAPTERS = {{
        name = "默认(nil)",
        adapter = nil
    }, {
        name = "LWIP_STA",
        adapter = socket.LWIP_STA
    }}
else
    -- 所有可用的网络适配器列表
    ALL_ADAPTERS = {{
        name = "默认(nil)",
        adapter = nil
    }}
end

-- 确保FTP连接已关闭
local function ensure_ftp_closed()
    pcall(function()
        ftp.close().wait()
    end)
    sys.wait(50)
end

-- 打印测试开始信息
local function test_start(adapter_name, name)
    log.info("ftp_test", string.rep("=", 40))
    log.info("ftp_test", string.format("适配器 [%s] - 测试: %s", adapter_name, name))
    log.info("ftp_test", string.rep("=", 40))
    ensure_ftp_closed()
end

-- 尝试连接指定适配器
local function try_connect_adapter(adapter, adapter_name)
    log.info("ftp_test", string.format("尝试连接适配器 [%s] ...", adapter_name))
    ensure_ftp_closed()

    local login_result = ftp.login(adapter, FTP_SERVER_CONFIG.host, FTP_SERVER_CONFIG.port, FTP_SERVER_CONFIG.username,
                             FTP_SERVER_CONFIG.password).wait()

    if login_result == true then
        log.info("ftp_test", string.format("✓ 适配器 [%s] 连接成功", adapter_name))
        return true
    end

    log.info("ftp_test", string.format("✗ 适配器 [%s] 连接失败", adapter_name))
    ensure_ftp_closed()
    return false
end

-- FTP登录测试 - 遍历所有适配器
function ftp_ori_test.test_ftp_login()
    for _, adapter_info in ipairs(ALL_ADAPTERS) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name

        -- 先尝试连接
        if try_connect_adapter(adapter, name) then
            test_start(name, "FTP登录测试")

            local login_result = ftp.login(adapter, FTP_SERVER_CONFIG.host, FTP_SERVER_CONFIG.port,
                                     FTP_SERVER_CONFIG.username, FTP_SERVER_CONFIG.password).wait()

            if login_result ~= true then
                log.info("FTP登录失败")
                return
            end
            assert(login_result == true, string.format(
                "适配器[%s] FTP登录测试失败: 预期结果true,实际结果%s", name, tostring(login_result)))
            log.info("ftp_test", string.format("适配器[%s] FTP登录测试通过", name))
        else
            log.info("ftp_test", string.format("适配器[%s] 连接失败，跳过登录测试", name))
        end

        sys.wait(100)
    end
end

-- FTP基本命令测试 - 遍历所有适配器
function ftp_ori_test.test_ftp_commands()
    for _, adapter_info in ipairs(ALL_ADAPTERS) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name

        -- 先尝试连接
        if try_connect_adapter(adapter, name) then
            test_start(name, "FTP基本命令测试")
            local login_result = ftp.login(adapter, FTP_SERVER_CONFIG.host, FTP_SERVER_CONFIG.port,
                                     FTP_SERVER_CONFIG.username, FTP_SERVER_CONFIG.password).wait()
            if login_result ~= true then
                log.info("FTP登录失败")
                return
            end
            -- NOOP命令测试
            local noop_result = ftp.command("NOOP").wait()
            local cleaned_noop_result = tostring(noop_result)
            cleaned_noop_result = cleaned_noop_result:match("^%s*(.-)%s*$")
            cleaned_noop_result = cleaned_noop_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            assert(cleaned_noop_result == "200 NOOP ok.",
                string.format("适配器[%s] NOOP命令测试失败: 预期结果'200 NOOP ok.',实际结果'%s'", name,
                    cleaned_noop_result))
            log.info("ftp_test", string.format("适配器[%s] NOOP命令测试通过", name))

            -- SYST命令测试
            local syst_result = ftp.command("SYST").wait()
            local cleaned_syst_result = tostring(syst_result)
            cleaned_syst_result = cleaned_syst_result:match("^%s*(.-)%s*$")
            cleaned_syst_result = cleaned_syst_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            assert(cleaned_syst_result == "215 UNIX Type: L8",
                string.format("适配器[%s] SYST命令测试失败: 预期结果'215 UNIX Type: L8',实际结果%s",
                    name, cleaned_syst_result))
            log.info("ftp_test", string.format("适配器[%s] SYST命令测试通过", name))

            -- TYPE I命令测试
            local type_result = ftp.command("TYPE I").wait()
            local cleaned_type_result = tostring(type_result)
            cleaned_type_result = cleaned_type_result:match("^%s*(.-)%s*$")
            cleaned_type_result = cleaned_type_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            assert(cleaned_type_result == "200 Switching to Binary mode.",
                string.format(
                    "适配器[%s] TYPE I命令测试失败: 预期结果'200 Switching to Binary mode.',实际结果%s",
                    name, cleaned_type_result))
            log.info("ftp_test", string.format("适配器[%s] TYPE I命令测试通过", name))

            -- PWD命令测试
            local pwm_result = ftp.command("PWD").wait()
            local cleaned_pwm_result = tostring(pwm_result)
            cleaned_pwm_result = cleaned_pwm_result:match("^%s*(.-)%s*$")
            cleaned_pwm_result = cleaned_pwm_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            assert(cleaned_pwm_result:find("257") and cleaned_pwm_result:find("/"), string.format(
                "适配器[%s] PWD命令测试失败: 预期包含'257'和'/',实际结果'%s'", name,
                cleaned_pwm_result))
            log.info("ftp_test", string.format("适配器[%s] PWD命令测试通过", name))

            -- MKD命令测试
            local mkd_result = ftp.command("MKD DADT").wait()
            local cleaned_mkd_result = tostring(mkd_result)
            cleaned_mkd_result = cleaned_mkd_result:match("^%s*(.-)%s*$")
            cleaned_mkd_result = cleaned_mkd_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            if cleaned_mkd_result:find("550") and cleaned_mkd_result:find("Create directory operation failed") then
                ftp.command("CDUP").wait()
                ftp.command("RMD DADT").wait()
                sys.wait(100)
                mkd_result = ftp.command("MKD DADT").wait()
                cleaned_mkd_result = tostring(mkd_result)
                cleaned_mkd_result = cleaned_mkd_result:match("^%s*(.-)%s*$")
                cleaned_mkd_result = cleaned_mkd_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            end
            assert(tostring(cleaned_mkd_result):find("257") ~= nil and tostring(cleaned_mkd_result):find("DADT") ~= nil,
                string.format("适配器[%s] MKD DADT命令测试失败: 预期包含257和DADT,实际结果%s", name,
                    cleaned_mkd_result))
            log.info("ftp_test", string.format("适配器[%s] MKD DADT命令测试通过", name))

            -- CWD命令测试
            local cwd_result = ftp.command("CWD /DADT").wait()
            local cleaned_cwd_result = tostring(cwd_result)
            cleaned_cwd_result = cleaned_cwd_result:match("^%s*(.-)%s*$")
            cleaned_cwd_result = cleaned_cwd_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            assert(tostring(cleaned_cwd_result):find("250") ~= nil,
                string.format("适配器[%s] CWD命令测试失败: 预期250成功响应,实际结果%s", name,
                    tostring(cleaned_cwd_result)))
            log.info("ftp_test", string.format("适配器[%s] CWD /DADT命令测试通过", name))

            -- CDUP命令测试
            local cdup_result = ftp.command("CDUP").wait()
            local cleaned_cdup_result = tostring(cdup_result)
            cleaned_cdup_result = cleaned_cdup_result:match("^%s*(.-)%s*$")
            cleaned_cdup_result = cleaned_cdup_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            assert(tostring(cleaned_cdup_result):find("250") ~= nil,
                string.format(
                    "适配器[%s] CDUP命令测试失败: 预期250 Directory successfully changed,实际结果%s",
                    name, tostring(cleaned_cdup_result)))
            log.info("ftp_test", string.format("适配器[%s] CDUP命令测试通过", name))

            -- RMD命令测试
            local rmd_result = ftp.command("RMD DADT").wait()
            local cleaned_rmd_result = tostring(rmd_result)
            cleaned_rmd_result = cleaned_rmd_result:match("^%s*(.-)%s*$")
            cleaned_rmd_result = cleaned_rmd_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            assert(cleaned_rmd_result == "250 Remove directory operation successful.", string.format(
                "适配器[%s] RMD DADT命令返回值测试失败: 预期'250 Remove directory operation successful.',实际结果%s",
                name, tostring(cleaned_rmd_result)))
            log.info("ftp_test", string.format("适配器[%s] RMD DADT命令返回值测试通过", name))

            -- 再次MKD测试
            local mkd_result_second = ftp.command("MKD DADT").wait()
            local cleaned_mkd_result_second = tostring(mkd_result_second)
            cleaned_mkd_result_second = cleaned_mkd_result_second:match("^%s*(.-)%s*$")
            cleaned_mkd_result_second = cleaned_mkd_result_second:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            assert(tostring(cleaned_mkd_result):find("257") ~= nil and tostring(cleaned_mkd_result):find("DADT") ~= nil,
                string.format(
                    "适配器[%s] RMD DADT命令删除后再次创建文件夹测试失败: 预期包含257和DADT,实际结果%s",
                    name, cleaned_mkd_result))
            log.info("ftp_test",
                string.format("适配器[%s] RMD DADT命令删除后再次创建文件夹测试通过", name))
        else
            log.info("ftp_test", string.format("适配器[%s] 连接失败，跳过基本命令测试", name))
        end

        sys.wait(100)
    end
end

-- FTP文件传输测试 - 遍历所有适配器
function ftp_ori_test.test_ftp_file_transfer()
    for _, adapter_info in ipairs(ALL_ADAPTERS) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name

        -- 先尝试连接
        if try_connect_adapter(adapter, name) then
            test_start(name, "FTP文件传输测试")
            local login_result = ftp.login(adapter, FTP_SERVER_CONFIG.host, FTP_SERVER_CONFIG.port,
                                     FTP_SERVER_CONFIG.username, FTP_SERVER_CONFIG.password).wait()
            if login_result ~= true then
                log.info("FTP登录失败")
                return
            end
            -- 创建测试文件并上传
            io.writeFile("/bootime.txt", "我是创建文件，文件名是bootime，即将上传ftp服务器")
            local local_file = "/bootime.txt"
            local remote_file = "/uploaded_by_bootime.txt"
            local push_result = ftp.push(local_file, remote_file).wait()
            assert(push_result == true,
                string.format("适配器[%s] push命令上传文件返回值测试失败: 预期true,实际结果%s",
                    name, tostring(push_result)))
            log.info("ftp_test", string.format("适配器[%s] push命令上传文件测试返回值通过", name))

            -- 下载文件
            local local_file_second = "/ftp_download.txt"
            local download_result = ftp.pull(local_file_second, remote_file).wait()
            assert(download_result == true,
                string.format("适配器[%s] pull命令下载文件返回值测试失败: 预期true,实际结果%s",
                    name, tostring(download_result)))
            log.info("ftp_test", string.format("适配器[%s] pull命令下载文件返回值测试通过", name))

            -- 验证文件存在
            local exists_file_result = io.exists(local_file_second)
            assert(exists_file_result == true,
                string.format("适配器[%s] pull命令下载文件存在测试失败: 预期true,实际结果%s", name,
                    tostring(exists_file_result)))
            log.info("ftp_test", string.format("适配器[%s] pull命令下载文件存在测试通过", name))

            -- 验证文件内容大小
            local full_data_content = io.readFile(local_file_second)
            local full_data_size = #full_data_content
            local file_content = "我是创建文件，文件名是bootime，即将上传ftp服务器"
            local file_content_size = #file_content
            assert(full_data_size == file_content_size,
                string.format("适配器[%s] 文件内容大小测试失败: 预期%s,实际结果%s", name,
                    file_content_size, full_data_size))
            log.info("ftp_test", string.format("适配器[%s] 文件内容大小测试通过", name))

            -- 验证文件内容一致性
            local full_data = io.readFile(local_file_second)
            assert(tostring(full_data) == file_content,
                string.format("适配器[%s] 文件内容一致性测试失败: 预期%s,实际结果%s", name,
                    file_content, tostring(full_data)))
            log.info("ftp_test", string.format("适配器[%s] 文件内容一致性测试通过", name))

            -- LIST命令测试
            local list_result = ftp.command("LIST " .. remote_file).wait()
            assert(list_result and #tostring(list_result) > 0,
                string.format("适配器[%s] LIST打印目录测试失败: 预期含有%s,实际结果%s", name,
                    remote_file, tostring(list_result)))
            log.info("ftp_test", string.format("适配器[%s] LIST打印目录测试通过", name))

            -- DELE命令测试
            local dele_result = ftp.command("DELE /uploaded_by_bootime.txt").wait()
            local cleaned_dele_result = tostring(dele_result)
            cleaned_dele_result = cleaned_dele_result:match("^%s*(.-)%s*$")
            cleaned_dele_result = cleaned_dele_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            assert(cleaned_dele_result == "250 Delete operation successful.",
                string.format(
                    "适配器[%s] DELE命令返回值测试失败: 预期'250 Delete operation successful.',实际结果%s",
                    name, tostring(cleaned_dele_result)))
            log.info("ftp_test", string.format("适配器[%s] DELE命令返回值测试通过", name))

            -- 验证文件已删除
            local local_file_third = "/ftp_download_third.txt"
            local download_result_again = ftp.pull(local_file_third, remote_file).wait()
            assert(download_result_again == false,
                string.format("适配器[%s] DELE命令删除文件验证测试失败: 预期false,实际结果%s",
                    name, tostring(download_result_again)))
            log.info("ftp_test", string.format("适配器[%s] DELE命令删除文件验证测试通过", name))

            -- 清理本地文件
            pcall(function()
                os.remove("/bootime.txt")
                os.remove("/ftp_download.txt")
                os.remove("/ftp_download_third.txt")
            end)
        else
            log.info("ftp_test", string.format("适配器[%s] 连接失败，跳过文件传输测试", name))
        end
        sys.wait(100)
    end
end

-- FTP debug测试 - 遍历所有适配器
function ftp_ori_test.test_ftp_debug()
    for _, adapter_info in ipairs(ALL_ADAPTERS) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name

        -- 先尝试连接
        if try_connect_adapter(adapter, name) then
            test_start(name, "FTP debug命令测试")
            local login_result = ftp.login(adapter, FTP_SERVER_CONFIG.host, FTP_SERVER_CONFIG.port,
                                     FTP_SERVER_CONFIG.username, FTP_SERVER_CONFIG.password).wait()
            if login_result ~= true then
                log.info("FTP登录失败")
                return
            end
            local ftp_debug_result = ftp.debug(true)
            assert(ftp_debug_result == nil,
                string.format("适配器[%s] debug命令使用测试失败: 预期nil", name))
            log.info("ftp_test", string.format("适配器[%s] debug命令使用成功测试通过", name))
        else
            log.info("ftp_test", string.format("适配器[%s] 连接失败，跳过debug测试", name))
        end

        sys.wait(100)
    end
end

-- FTP close测试 - 遍历所有适配器
function ftp_ori_test.test_ftp_close()
    for _, adapter_info in ipairs(ALL_ADAPTERS) do
        local adapter = adapter_info.adapter
        local name = adapter_info.name

        -- 先尝试连接
        if try_connect_adapter(adapter, name) then
            test_start(name, "FTP close命令测试")
            local login_result = ftp.login(adapter, FTP_SERVER_CONFIG.host, FTP_SERVER_CONFIG.port,
                                     FTP_SERVER_CONFIG.username, FTP_SERVER_CONFIG.password).wait()
            if login_result ~= true then
                log.info("FTP登录失败")
                return
            end
            local ftp_close_result = ftp.close().wait()
            local cleaned_close_result = tostring(ftp_close_result)
            cleaned_close_result = cleaned_close_result:match("^%s*(.-)%s*$")
            cleaned_close_result = cleaned_close_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
            assert(tostring(cleaned_close_result) == "221 Goodbye.",
                string.format("适配器[%s] close命令返回值测试失败: 预期'221 Goodbye.',实际%s", name,
                    cleaned_close_result))
            log.info("ftp_test", string.format("适配器[%s] close命令返回值测试通过", name))
        else
            log.info("ftp_test", string.format("适配器[%s] 连接失败，跳过close测试", name))
        end

        sys.wait(100)
    end
end

return ftp_ori_test
