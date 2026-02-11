local ftp_ori_test = {}

-- FTP服务器配置
local FTP_CONFIG = {
    adapter = nil,
    host = "121.43.224.154",
    port = 21,
    username = "ftp_user",
    password = "3QujbiMG"
}

-- ========== 工具函数 ==========

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


    log.info("ftp_test", "测试NOOP命令...")
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
    log.info("pwm打印", pwm_result)
    -- 先清理字符串
    local cleaned_pwm_result = tostring(pwm_result)
    cleaned_pwm_result = cleaned_pwm_result:match("^%s*(.-)%s*$")
    cleaned_pwm_result = cleaned_pwm_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    assert(cleaned_pwm_result:find("257") and cleaned_pwm_result:find("/"),
        string.format("PWD命令测试失败: 预期包含'257'和'/',实际结果'%s'", cleaned_pwm_result))
    log.info("ftp_test", "PWD命令测试通过")


    local mkd_result = ftp.command("MKD DADT").wait()
    log.info("MKD DADT打印", mkd_result)
    -- 先清理字符串
    local cleaned_mkd_result = tostring(mkd_result)
    cleaned_mkd_result = cleaned_mkd_result:match("^%s*(.-)%s*$")
    cleaned_mkd_result = cleaned_mkd_result:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    assert(cleaned_mkd_result:find("257") and cleaned_mkd_result:find("DADT"),
        string.format("MKD QWER命令测试失败: 预期包含257和DADT,实际结果%s", cleaned_mkd_result))
    log.info("ftp_test", "MKD DADT命令测试通过")

    local cwd_result = ftp.command("CWD /DADT").wait()
    log.info("CWD /QWER打印", cwd_result)

    local cdup_result = ftp.command("CDUP").wait()
    log.info("CDUP打印", cdup_result)

    local rmd_result = ftp.command("RMD DADT").wait()
    log.info("RMD QWER打印", rmd_result)

    local dele_result = ftp.command("DELE /12222.txt").wait()
    log.info("DELE打印", dele_result)

    local list_result = ftp.command("LIST").wait()
    log.info("LIST打印", list_result)

end
return ftp_ori_test
