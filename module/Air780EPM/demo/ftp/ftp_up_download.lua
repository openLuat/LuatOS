--[[
@module  ftp_up_download
@summary ftp服务器上传下载文件处理应用功能模块
@version 001.000.000
@date    2025.07.29
@author  马亚丹
@usage
本文件为ftp服务器上传下载文件处理主应用功能模块，核心业务逻辑为：
1. 配置FTP客户端登录服务器的参数和文件路径
2. 封装一个重试机制，在登录失败、上传文件失败或者下载文件失败时尝试重新执行操作
3. 登录FTP服务器，通过重试机制确保登录成功
4. ftp.push上传本地文件到服务器，在本地新建文件并写入内容后上传到服务器指定路径，通过重试机制确保上传成功
5. ftp.pull从服务器下载文件，保存在本地指定路径，并读取文件长度，当长度小于指定字节时，读取文件内容，通常是设定512字节，如果文件太大，会消耗ram,通过重试机制确保上传成功
6. 主函数循环运行以下流程：登录服务器、用 ftp.command 操作 ftp 服务器目录以及文件上传下载处理后关闭服务器。

测试服务器为：
非ssl加密：
local server_ip = "121.43.224.154" -- 服务器IP
local server_port = 21 -- 服务器端口号
local server_username = "ftp_user" -- 服务器登陆用户名
local server_password = "3QujbiMG" -- 服务器登陆密码

本文件没有对外接口，直接在main.lua中require "ftp_up_download"就可以加载运行
]]



--1. 统一配置FTP参数和文件路径
local config = {
    server = {
        ip = "121.43.224.154", -- FTP服务器IP
        port = 21,             -- FTP端口
        username = "ftp_user", -- 登陆用户名
        password = "3QujbiMG", -- 登陆密码
        is_ssl = false,        -- 若需SSL，补充证书
    },
    download = {
        remote_file = "/12222.txt",      -- 服务器上要下载的文件
        local_file = "/ftp_download.txt" -- 本地保存的文件名
    },
    upload = {
        local_file = "/ftp_upload.txt",         -- 本地要上传的文件（会自动创建）
        remote_file = "/uploaded_by_luatos.txt" -- 服务器保存的文件名
    }
}


--2.定义功能函数： 重试机制封装，针对易失败操作
local function retry_operation(operation, max_retries, interval)
    local retries = 0
    while retries < max_retries do
        local result = operation()
        if result then return true end
        retries = retries + 1
        log.warn("操作失败，重试第", retries, "次")
        sys.wait(interval)
    end
    log.error("超过最大重试次数")
    return false
end

--3.定义功能函数： 登录FTP服务器（带重试）
local function ftp_login()
    --查看网卡适配器的联网状态是否IP_READY,true表示已经准备好可以联网了,false暂时不可以联网
    while not socket.adapter(socket.dft()) do
        log.warn("ftp_login", "wait IP_READY", socket.dft())
        -- 在此处阻塞等待默认网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        -- 因为当使用exnetif.set_priority_order配置多个网卡连接外网的优先级时，会隐式的修改默认使用的网卡
        -- 当exnetif.set_priority_order的调用时序和此处的socket.adapter(socket.dft())判断时序有可能不匹配
        -- 此处的1秒，能够保证，即使时序不匹配，也能1秒钟退出阻塞状态，再去判断socket.adapter(socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    -- 检测到了IP_READY消息，设置默认网络适配器编号
    log.info("ftp_login", "recv IP_READY", socket.dft())

    --登录FTP服务器核心函数
    local function ftp_login_result()
        local login_result = ftp.login(
            nil,
            config.server.ip,
            config.server.port,
            config.server.username,
            config.server.password,
            config.server.is_ssl
        ).wait()
        if login_result then
            log.info("FTP登录成功")
            return true
        end
        log.error("FTP登录失败")
        return false
    end

    -- 如果登录失败，最多重试登录3次，间隔3秒，可按需修改
    return retry_operation(ftp_login_result, 3, 3000)
end

--4.定义功能函数： 上传文件到服务器（带重试）
local function ftp_upload_file()
    -- 确保本地文件创建成功
    -- 要写入文件的内容，按需求修改
    local upload_content = "Luatos FTP上传测试数据 "
    local file, err = io.open(config.upload.local_file, "w")
    if not file then
        log.error("创建本地文件失败:", err)
        return false
    end
    --写入内容到文件
    file:write(upload_content)
    file:close()

    --打印创建文件的结果
    log.info("本地文件" .. config.upload.local_file .. "创建成功，" .. "并写入文件内容:", upload_content)

    -- 上传文件核心函数
    local function ftp_upload_result()
        log.info("开始上传文件:" .. config.upload.local_file)
        -- ftp.push参数：本地文件路径 → 服务器文件路径
        local upload_ok = ftp.push(
            config.upload.local_file,
            config.upload.remote_file
        ).wait()
        if upload_ok then
            log.info("本地文件上传成功，保存在服务器路径:", config.upload.remote_file)
            return true
        end
        log.error("文件上传失败")
        return false
    end

    -- 如果上传失败，最多重试上传3次，间隔2秒，可按需修改
    return retry_operation(ftp_upload_result, 3, 2000)
end

--5.定义功能函数： 下载文件到本地（带重试）
local function ftp_download_file()
    local function ftp_download_result()
        log.info(" 开始下载文件:" .. config.download.remote_file)
        -- ftp.pull参数：  本地文件路径→服务器文件路径
        local download_ok = ftp.pull(
            config.download.local_file,
            config.download.remote_file
        ).wait()
        if not download_ok then
            log.error("文件下载失败")
            return false
        end

        --检查下载结果
        local file = io.open(config.download.local_file, "r")
        if not file then
            log.error("下载文件本地打开失败！重新下载")
            return false
        end

        local fsize = io.fileSize(config.download.local_file)
        if not fsize then
            log.error("读取文件大小失败,重新下载")
            file:close()
            return false
        end
        log.info("服务器上文件" .. config.download.remote_file .. "下载成功，保存在本地路径:", config.download.local_file, "大小:", fsize,
            "字节")

        if fsize and fsize <= 512 then
            local content = file:read("*a")
            file:close()
            log.info("下载文件内容长度小于512字节，内容是:", content)
            return true
        end
        -- 执行完操作后,一定要关掉文件
        file:close()
        return true
    end

    -- 如果下载失败，最多重试10次，间隔2秒,可按需修改
    return retry_operation(ftp_download_result, 10, 2000)
end


--6.定义功能函数： 功能测试主函数
local function ftp_main_task()
    while true do
        -- 步骤1：登录FTP服务器
        if not ftp_login() then
            log.error("登录失败，退出流程")
            --退出前关闭连接，释放资源
            ftp.close().wait()
            return
        end


        -- 执行FTP命令并检查结果
        log.info("空操作，防止连接断掉", ftp.command("NOOP").wait())
        log.info("报告远程系统的操作系统类型", ftp.command("SYST").wait())
        log.info("指定文件类型", ftp.command("TYPE I").wait())
        log.info("显示当前工作目录名", ftp.command("PWD").wait())
        log.info("创建一个目录 目录名为QWER", ftp.command("MKD QWER").wait())
        log.info("改变当前工作目录为QWER", ftp.command("CWD /QWER").wait())
        log.info("返回上一层目录", ftp.command("CDUP").wait())
        log.info("获取当前工作目录下的文件名列表", ftp.command("LIST").wait())

        -- 步骤2：上传文件
        if not ftp_upload_file() then
            log.error("上传失败，继续执行下载") -- 不中断流程
        end


        -- 步骤3：下载文件
        if not ftp_download_file() then
            log.error("下载失败")
        end

        -- 步骤4：清理操作（可选）,清理之前创建的目录
        log.info("删除测试目录QWER", ftp.command("RMD QWER").wait())

        -- 步骤5：关闭连接
        local close_result = ftp.close().wait()
        log.info("FTP连接关闭结果:", close_result)

        --步骤6：获取内存信息
        local meminfo_result = rtos.meminfo("sys")
        log.info("meminfo内存信息", rtos.meminfo("sys"))
        --循环执行，每1分钟执行一次
        sys.wait(1 * 60 * 1000)
    end
end

-- 启动主任务
sys.taskInit(ftp_main_task)
