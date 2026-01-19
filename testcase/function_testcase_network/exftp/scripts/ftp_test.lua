local ftp_test = {}

-- -- 获取LuatOS版本信息
-- local luatos_version, luatos_version_num = rtos.get_version()
-- log.info("LuatOS version: " .. luatos_version, "version number: " .. luatos_version_num)

-- 加载exftp库
local exftp = require "exftp"

-- FTP服务器配置
local FTP_CONFIG = {
    host = "121.43.224.154",
    port = 21,
    username = "ftp_user",
    password = "3QujbiMG",
}

-- 获取唯一ID作为文件名后缀
if mobile then
    file_suffix = mobile.imei()
elseif wlan then
    file_suffix = wlan.getMac(nil, true)
else
    file_suffix = mcu.unique_id()
end

-- 测试文件配置
local TEST_FILES = {
    upload = {
        local_path = "/luadb/test_upload.txt",
        remote_path = "/test_upload_" .. file_suffix .. ".txt",
    },
    download = {
        remote_path = "/downloaded_by_ftp.txt",
        local_path = "/downloaded_by_ftp.txt",
    },
    directory = {
        test_path = "/ftp_folder",
    }
}

-- 等待网络就绪的辅助函数
local function wait_network_ready()
    -- 注意：网络初始化现在由testrunner统一处理
    -- 这里保留函数是为了保持代码结构，但实际上网络已经就绪
    log.info("ftp_test", "检查网络状态...")
end

-- 创建和配置FTP客户端的辅助函数
local function create_ftp_client()
    local ftpc = exftp.create(nil, FTP_CONFIG.host, FTP_CONFIG.port)
    if not ftpc then
        error("创建FTP客户端失败")
    end
    -- 可选：开启调试
    -- ftpc:debug(true)
    return ftpc
end

-- FTP客户端连接和认证的辅助函数
local function connect_and_auth(ftpc)
    if not ftpc:auth(FTP_CONFIG.username, FTP_CONFIG.password) then
        error("FTP登录失败")
    end
end

-- 测试1: FTP客户端创建
function ftp_test.test_ftp_client_creation()
    log.info("ftp_test", "开始FTP客户端创建测试")

    -- 创建FTP客户端
    local ftpc = create_ftp_client()
    assert(ftpc, "FTP客户端创建失败")

    -- 关闭连接
    ftpc:close()

    log.info("ftp_test", "FTP客户端创建测试通过")
end

-- 测试2: FTP登录认证
function ftp_test.test_ftp_authentication()
    log.info("ftp_test", "开始FTP登录认证测试")

    -- 创建FTP客户端
    local ftpc = create_ftp_client()
    assert(ftpc, "FTP客户端创建失败")

    -- 登录认证
    connect_and_auth(ftpc)

    -- 关闭连接
    ftpc:close()

    log.info("ftp_test", "FTP登录认证测试通过")
end

-- 测试3: FTP目录操作
function ftp_test.test_ftp_directory_operations()
    log.info("ftp_test", "开始FTP目录操作测试")

    -- 创建FTP客户端并登录
    local ftpc = create_ftp_client()
    connect_and_auth(ftpc)

    -- 获取当前目录
    local ok, current_dir = ftpc:pwd()
    assert(ok, "获取当前目录失败: " .. tostring(current_dir))
    assert(current_dir, "当前目录为空")

    -- 切换到测试目录（如果存在）
    local chdir_ok = ftpc:chdir(TEST_FILES.directory.test_path)
    if chdir_ok then
        log.info("ftp_test", "成功切换到" .. TEST_FILES.directory.test_path .. "目录")

        -- 再次获取当前目录确认切换成功
        ok, current_dir = ftpc:pwd()
        assert(ok, "切换目录后获取当前目录失败")
        -- 提取目录名（去掉开头的/）用于验证
        local dir_name = TEST_FILES.directory.test_path:gsub("^/", "")
        assert(string.find(current_dir, dir_name), "目录切换验证失败")

        -- 返回上一级目录
        local cdup_ok = ftpc:cdup()
        assert(cdup_ok, "返回上一级目录失败")
    else
        log.info("ftp_test", TEST_FILES.directory.test_path .. "目录不存在，跳过目录切换测试")
    end

    -- 关闭连接
    ftpc:close()

    log.info("ftp_test", "FTP目录操作测试通过")
end

-- 测试4: FTP文件上传
function ftp_test.test_ftp_file_upload()
    log.info("ftp_test", "开始FTP文件上传测试")

    -- 检查上传文件是否存在
    local file_size = io.fileSize(TEST_FILES.upload.local_path)
    assert(file_size, "上传文件不存在: " .. TEST_FILES.upload.local_path)
    assert(file_size > 0, "上传文件为空")

    -- 创建FTP客户端并登录
    local ftpc = create_ftp_client()
    connect_and_auth(ftpc)

    -- 执行文件上传
    local upload_ok = ftpc:upload(
        TEST_FILES.upload.local_path,
        TEST_FILES.upload.remote_path,
        {
            timeout = 60 * 1000,  -- 60秒超时
        }
    )

    assert(upload_ok, "文件上传失败")

    -- 关闭连接
    ftpc:close()

    log.info("ftp_test", "FTP文件上传测试通过")
end

-- 测试5: FTP文件下载
function ftp_test.test_ftp_file_download()
    log.info("ftp_test", "开始FTP文件下载测试")

    -- 创建FTP客户端并登录
    local ftpc = create_ftp_client()
    connect_and_auth(ftpc)

    -- 执行文件下载
    local download_ok = ftpc:download(
        TEST_FILES.download.remote_path,
        TEST_FILES.download.local_path,
        {
            timeout = 30 * 1000  -- 30秒超时
        }
    )

    assert(download_ok, "文件下载失败")

    -- 验证下载的文件
    local downloaded_size = io.fileSize(TEST_FILES.download.local_path)
    assert(downloaded_size, "下载文件不存在")
    assert(downloaded_size > 0, "下载文件为空")

    -- 关闭连接
    ftpc:close()

    log.info("ftp_test", "FTP文件下载测试通过")
end


return ftp_test

