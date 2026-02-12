local ftp_ori_test = {}

-- FTP服务器配置
local FTP_CONFIG = {
    adapter = nil,
    host = "121.43.224.154",
    port = 21,
    username = "ftp_user",
    password = "3QujbiMG"
}

-- 确保FTP连接已关闭
local function ensure_ftp_closed()
    pcall(function()
        ftp.close().wait()
    end)
    sys.wait(50)
end

-- 打印测试开始信息
local function test_start(name)
    log.info("ftp_test", string.rep("=", 40))
    log.info("ftp_test", "测试:", name)
    log.info("ftp_test", string.rep("=", 40))
    ensure_ftp_closed()
end

-- FTP登录测试
function ftp_ori_test.test_ftp_login()
    test_start("FTP登录测试")

    local login_result = ftp.login(FTP_CONFIG.adapter, FTP_CONFIG.host, FTP_CONFIG.port, FTP_CONFIG.username,
                             FTP_CONFIG.password).wait()

    assert(login_result == true, string.format("FTP登录测试失败: 预期结果true,实际结果%s", login_result))
    log.info("ftp_test", "FTP登录测试通过")
end

-- FTP基本命令测试
function ftp_ori_test.test_ftp_commands()
    test_start("开始测试FTP基本命令测试")

    local login_result = ftp.login(FTP_CONFIG.adapter, FTP_CONFIG.host, FTP_CONFIG.port, FTP_CONFIG.username,
                             FTP_CONFIG.password).wait()

    if login_result ~= true then
        log.info("FTP登录失败")
    end

    local noop_result = ftp.command("NOOP").wait()
    -- 先清理字符串
    local cleaned_noop_result = tostring(noop_result)
    cleaned_noop_result = cleaned_noop_result:match("^%s*(.-)%s*$")
    cleaned_noop_result = cleaned_noop_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    assert(cleaned_noop_result == "200 NOOP ok.",
        string.format("NOOP命令测试失败: 预期结果'200 NOOP ok.',实际结果'%s'", cleaned_noop_result))
    log.info("ftp_test", "NOOP命令测试通过")

    local syst_result = ftp.command("SYST").wait()
    -- 先清理字符串
    local cleaned_syst_result = tostring(syst_result)
    cleaned_syst_result = cleaned_syst_result:match("^%s*(.-)%s*$")
    cleaned_syst_result = cleaned_syst_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    assert(cleaned_syst_result == "215 UNIX Type: L8",
        string.format("SYST命令测试失败: 预期结果'215 UNIX Type: L8',实际结果%s", cleaned_syst_result))
    log.info("ftp_test", "SYST命令测试通过")

    local type_result = ftp.command("TYPE I").wait()
    -- 先清理字符串
    local cleaned_type_result = tostring(type_result)
    cleaned_type_result = cleaned_type_result:match("^%s*(.-)%s*$")
    cleaned_type_result = cleaned_type_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    assert(cleaned_type_result == "200 Switching to Binary mode.",
        string.format("TYPE I命令测试失败: 预期结果'200 Switching to Binary mode.',实际结果%s",
            cleaned_type_result))
    log.info("ftp_test", "TYPE I命令测试通过")

    local pwm_result = ftp.command("PWD").wait()
    -- 先清理字符串
    local cleaned_pwm_result = tostring(pwm_result)
    cleaned_pwm_result = cleaned_pwm_result:match("^%s*(.-)%s*$")
    cleaned_pwm_result = cleaned_pwm_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    assert(cleaned_pwm_result:find("257") and cleaned_pwm_result:find("/"),
        string.format("PWD命令测试失败: 预期包含'257'和'/',实际结果'%s'", cleaned_pwm_result))
    log.info("ftp_test", "PWD命令测试通过")

    local mkd_result = ftp.command("MKD DADT").wait()
    -- 先清理字符串
    local cleaned_mkd_result = tostring(mkd_result)
    cleaned_mkd_result = cleaned_mkd_result:match("^%s*(.-)%s*$")
    cleaned_mkd_result = cleaned_mkd_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    if cleaned_mkd_result:find("550") and cleaned_mkd_result:find("Create directory operation failed") then
        ftp.command("CDUP").wait()
        ftp.command("RMD DADT").wait()
        sys.wait(100)
        mkd_result = ftp.command("MKD DADT").wait()
        -- 先清理字符串
        cleaned_mkd_result = tostring(mkd_result)
        cleaned_mkd_result = cleaned_mkd_result:match("^%s*(.-)%s*$")
        cleaned_mkd_result = cleaned_mkd_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    end
    assert(tostring(cleaned_mkd_result):find("257") ~= nil and tostring(cleaned_mkd_result):find("DADT") ~= nil,
        string.format("MKD QWER命令测试失败: 预期包含257和DADT,实际结果%s", cleaned_mkd_result))
    log.info("ftp_test", "MKD DADT命令测试通过")

    local cwd_result = ftp.command("CWD /DADT").wait()
    -- 先清理字符串
    local cleaned_cwd_result = tostring(cwd_result)
    cleaned_cwd_result = cleaned_cwd_result:match("^%s*(.-)%s*$")
    cleaned_cwd_result = cleaned_cwd_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    assert(tostring(cleaned_cwd_result):find("250") ~= nil,
        string.format("CWD 命令测试失败: 预期250成功响应,实际结果%s", tostring(cleaned_cwd_result)))
    log.info("ftp_test", "CWD /DADT命令测试通过")

    local cdup_result = ftp.command("CDUP").wait()
    -- 先清理字符串
    local cleaned_cdup_result = tostring(cdup_result)
    cleaned_cdup_result = cleaned_cdup_result:match("^%s*(.-)%s*$")
    cleaned_cdup_result = cleaned_cdup_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    assert(tostring(cleaned_cdup_result):find("250") ~= nil,
        string.format("CDUP命令测试失败: 预期250 Directory successfully changed,实际结果%s",
            tostring(cleaned_cdup_result)))
    log.info("ftp_test", "CDUP命令测试通过")

    local rmd_result = ftp.command("RMD DADT").wait()
    -- 先清理字符串
    local cleaned_rmd_result = tostring(rmd_result)
    cleaned_rmd_result = cleaned_rmd_result:match("^%s*(.-)%s*$")
    cleaned_rmd_result = cleaned_rmd_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    assert(cleaned_rmd_result == "250 Remove directory operation successful.",
        string.format(
            "RMD DADT命令返回值测试失败: 预期'250 Remove directory operation successful.',实际结果%s",
            tostring(cleaned_rmd_result)))
    log.info("ftp_test", "RMD DADT命令返回值测试通过")

    local mkd_result_second = ftp.command("MKD DADT").wait()
    -- 先清理字符串
    local cleaned_mkd_result_second = tostring(mkd_result_second)
    cleaned_mkd_result_second = cleaned_mkd_result_second:match("^%s*(.-)%s*$")
    cleaned_mkd_result_second = cleaned_mkd_result_second:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    assert(tostring(cleaned_mkd_result):find("257") ~= nil and tostring(cleaned_mkd_result):find("DADT") ~= nil,
        string.format("RMD DADT命令删除后再次创建文件夹测试失败: 预期包含257和DADT,实际结果%s",
            cleaned_mkd_result))
    log.info("ftp_test", "RMD DADT命令删除后再次创建文件夹测试通过")

    io.writeFile("/bootime.txt", "我是创建文件，文件名是bootime，即将上传ftp服务器")
    local local_file = "/bootime.txt"
    local remote_file = "/uploaded_by_bootime.txt"
    local push_result = ftp.push(local_file, remote_file).wait()
    assert(push_result == true, string.format(
        "push命令上传" .. local_file .. "文件返回值测试失败: 预期true,实际结果%s", push_result))
    log.info("ftp_test", "push命令上传" .. local_file .. "文件测试返回值通过")

    local local_file_second = "/ftp_download.txt"
    local remote_file = "/uploaded_by_bootime.txt"
    local download_result = ftp.pull(local_file_second, remote_file).wait()
    assert(download_result == true,
        string.format("pull命令下载" .. remote_file .. "文件返回值测试失败: 预期true,实际结果%s",
            download_result))
    log.info("ftp_test", "pull命令下载" .. remote_file .. "文件返回值测试返回值通过")

    local exists_file_result = io.exists(local_file_second)
    assert(exists_file_result == true,
        string.format("pull命令下载" .. remote_file .. "文件存在测试失败: 预期true,实际结果%s",
            exists_file_result))
    log.info("ftp_test", "pull命令下载" .. remote_file .. "文件存在测试通过")

    local full_data = io.readFile(local_file_second)
    local file_content = "我是创建文件，文件名是bootime，即将上传ftp服务器"
    assert(tostring(full_data) == file_content, string.format(
        "pull命令下载和push命令上传" .. remote_file ..
            "文件内容一致性测试失败: 预期%s,实际结果%s", file_content, full_data))
    log.info("ftp_test", "pull命令下载" .. remote_file .. "文件内容一致性测试通过")

    local list_result = ftp.command("LIST " .. remote_file).wait()
    assert(list_result and #tostring(list_result) > 0,
        string.format("LIST打印" .. remote_file .. "目录测试失败: 预期含有%s,实际结果%s", remote_file,
            list_result))
    log.info("ftp_test", "LIST打印" .. remote_file .. "目录测试通过")

    local dele_result = ftp.command("DELE /uploaded_by_bootime.txt").wait()
    -- 先清理字符串
    local cleaned_dele_result = tostring(dele_result)
    cleaned_dele_result = cleaned_dele_result:match("^%s*(.-)%s*$")
    cleaned_dele_result = cleaned_dele_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    assert(cleaned_dele_result == "250 Delete operation successful.",
        string.format("DELE命令返回值测试失败: 预期'250 Delete operation successful.',实际结果%s",
            tostring(cleaned_dele_result)))
    log.info("ftp_test", "DELE命令返回值测试通过")

    local local_file_third = "/ftp_download_third.txt"
    local remote_file = "/uploaded_by_bootime.txt"
    local download_result = ftp.pull(local_file_third, remote_file).wait()
    assert(download_result == false,
        string.format("DELE命令删除" .. remote_file .. "文件返回值测试失败: 预期false,实际结果%s",
            download_result))
    log.info("ftp_test", "DELE命令删除" .. remote_file .. "文件返回值测试通过")
end

-- FTP debug 测试
function ftp_ori_test.test_ftp_debug()
    test_start("开始测试debug命令测试")

    local login_result = ftp.login(FTP_CONFIG.adapter, FTP_CONFIG.host, FTP_CONFIG.port, FTP_CONFIG.username,
                             FTP_CONFIG.password).wait()

    if login_result ~= true then
        log.info("FTP登录失败")
    end

    local ftp_debug_result = ftp.debug(true)
    assert(ftp_debug_result == nil, string.format("debug命令使用测试失败: 预期nil"))
    log.info("ftp_test", "debug命令使用成功测试通过")
end

-- FTP close 测试
function ftp_ori_test.test_ftp_close()
    test_start("开始测试close命令测试")

    local login_result = ftp.login(FTP_CONFIG.adapter, FTP_CONFIG.host, FTP_CONFIG.port, FTP_CONFIG.username,
                             FTP_CONFIG.password).wait()

    if login_result ~= true then
        log.info("FTP登录失败")
    end

    local ftp_close_result = ftp.close().wait()
    -- 先清理字符串
    local cleaned_close_result = tostring(ftp_close_result)
    cleaned_close_result = cleaned_close_result:match("^%s*(.-)%s*$")
    cleaned_close_result = cleaned_close_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    assert(tostring(cleaned_close_result) == "221 Goodbye.",
        string.format("close命令返回值测试失败: 预期'221 Goodbye.',实际%s", cleaned_close_result))
    log.info("ftp_test", "close命令返回值测试通过")

end

return ftp_ori_test
