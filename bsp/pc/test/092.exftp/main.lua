--[[
@module  exftp测试程序
@summary exftp库功能测试
@version 1.0
@date    2025.12.28
@usage
测试exftp库的所有功能，包括：
1. 创建FTP客户端
2. 匿名登录
3. 路径切换
4. 文件上传
5. 文件下载
6. 关闭连接
]]

_G.sys = require("sys")
require "sysplus"
-- 加载exftp库
local exftp = require "exftp"

-- FTP服务器配置
local FTP_CONFIG = {
    host = "192.168.1.119",
    port = 21,
    username = "anonymous",
    password = "",
}

-- 测试文件配置
local TEST_FILES = {
    upload = {
        local_path = "/samples-master.zip",
        remote_path = "/samples-master.zip",
    },
    download = {
        remote_path = "/smalldownload.txt",
        local_path = "/smalldownload.txt",
    }
}

-- -- 等待网络就绪
-- local function wait_network_ready()
--     log.info("等待网络就绪...")
--     while not socket.adapter(socket.dft()) do
--         log.warn("等待IP_READY", socket.dft())
--         sys.waitUntil("IP_READY", 1000)
--     end
--     log.info("网络已就绪", socket.dft())
-- end

-- 主测试函数
local function exftp_test_task()
    log.info("exftp功能测试")

    -- 等待网络就绪
    sys.waitUntil("IP_READY")

    -- 检查上传文件是否存在（文件应该已经存在于目录中）
    local file_size = io.fileSize(TEST_FILES.upload.local_path)
    if not file_size then
        log.error("上传文件不存在", TEST_FILES.upload.local_path)
        return
    end

    -- 1. 创建FTP客户端
    log.info("=====================创建FTP客户端==============================")
    log.info("1. 创建FTP客户端")
    log.info("服务器", FTP_CONFIG.host, "端口", FTP_CONFIG.port)

    -- 使用默认适配器
    local ftpc = exftp.create(nil, FTP_CONFIG.host, FTP_CONFIG.port)
    if not ftpc then
        log.error("创建FTP客户端失败")
        return
    end
    log.info("FTP客户端创建成功")

    -- -- 可选：开启调试
    -- ftpc:debug(true)

    -- 2. 登录
    log.info("=====================登录=============================")
    if not ftpc:auth(FTP_CONFIG.username, FTP_CONFIG.password) then
        log.error("登录失败")
        ftpc:close()
        return
    end
    log.info("登录成功")

    -- 3. 路径切换功能
    log.info("=====================路径切换功能=============================")
    -- 获取当前目录
    local ok, current_dir = ftpc:pwd()
    if ok then
        log.info("当前目录", current_dir)
    else
        log.warn("获取当前目录失败", current_dir)
    end

    -- 切换到/test目录
    log.info("切换到 /test 目录")
    if ftpc:chdir("/test") then
        log.info("切换目录成功")

        -- 再次获取当前目录
        ok, current_dir = ftpc:pwd()
        if ok then
            log.info("当前目录", current_dir)
        end

        -- 返回上一级
        if ftpc:cdup() then
            log.info("返回上一级目录成功")
        end
    else
        log.warn("切换目录失败")
    end

    -- 4. 文件上传
    log.info("=====================文件上传=============================")
    log.info("本地文件", TEST_FILES.upload.local_path)
    log.info("远程文件", TEST_FILES.upload.remote_path)

    local ok = ftpc:upload(
        TEST_FILES.upload.local_path,
        TEST_FILES.upload.remote_path,
        {
            timeout = 30 * 1000,  -- 30秒超时
            -- buffer_size = n * 1024
        }
    )

    if ok then
        log.info("文件上传成功")
    else
        log.error("文件上传失败")
    end

    -- 5. 文件下载
    log.info("=====================文件下载=============================")
    log.info("远程文件", TEST_FILES.download.remote_path)
    log.info("本地文件", TEST_FILES.download.local_path)

    ok = ftpc:download(
        TEST_FILES.download.remote_path,
        TEST_FILES.download.local_path,
        {
            timeout = 30 * 1000  -- 30秒超时
        }
    )

    if ok then
        log.info("文件下载成功")

        -- 读取下载的文件内容（如果文件较小）
        local fd = io.open(TEST_FILES.download.local_path, "r")
        if fd then
            local file_size = io.fileSize(TEST_FILES.download.local_path)
            fd:close()
            log.info("下载文件大小", file_size, "字节")
        end
    else
        log.error("文件下载失败")
    end

    -- 6. 关闭连接
    log.info("=====================关闭连接=============================")
    ftpc:close()
    log.info("FTP连接已关闭")
    log.info("测试完成！")
end

-- 启动测试任务
sys.taskInit(exftp_test_task)

-- 运行系统
sys.run()

