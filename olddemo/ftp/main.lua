-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ftpdemo"
VERSION = "1.0.0"

--[[
本demo需要ftp库, 大部分能联网的设备都具有这个库
ftp也是内置库, 无需require
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用ftp库需要下列语句]]
_G.sysplus = require("sysplus")

local server_ip = "121.43.224.154" -- 服务器IP
local server_port = 21 -- 服务器端口号
local server_username = "ftp_user" -- 服务器登陆用户名
local server_password = "3QujbiMG" -- 服务器登陆密码

local is_ssl = false -- 非ssl加密连接
-- local is_ssl =true --如果是不带证书的加密打开这句话

-- local ssl_encrypt = {
--     server_cert = "/luadb/server_cert.cert",--服务器ca证书数据
--     client_cert = "/luadb/client_cert.cert",--客户端证书数据
--     client_key = "/luadb/client_key",-- 客户端私钥加密数据
--     client_password = "naovswoivbfpfvjwpojv[pawjb[dsfjb]]"--客户端私钥口令数据
-- }

-- local is_ssl = ssl_encrypt --如果是带证书的加密，请将上述ssl_encrypt内的文件名换成自己的

-- 这里使用模块唯一ID来生成文件名，避免多个模块使用同一ftp服务器时文件名冲突
local self_id = mcu.unique_id():toHex()
local local_name = "/ram/" .. self_id .. ".txt" -- 模块内部文件名及其路径
local remote_name = "/" .. self_id .. "_srv.txt" -- 服务器上的文件名及其路径

sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持
        local ssid = "luatos1234"
        local password = "12341234"
        log.info("wifi", ssid, password)
        wlan.init()
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
    elseif mobile then
        -- Air780E/Air600E系列
        -- mobile.simid(2)
        -- LED = gpio.setup(27, 0, gpio.PULLUP)
        -- device_id = mobile.imei()
    end
    sys.waitUntil("IP_READY") -- 死等到联网成功
    log.info("联网成功")
    -- 联网成功后发布联网成功的消息
    sys.publish("net_ready")
end)

--[[操作ftp的函数，因为用了sys.wait，请在task内调用
本函数每隔15S就会进行一次登陆到主动断开的操作，
如果您不需要断开 或者只需要单次，请修改本函数中的while true do逻辑
]]
local function ftp_test()
    sys.waitUntil("net_ready") -- 死等到联网成功
    local result = false
    local adapter = nil -- 自动选择网络适配器
    ftp.debug(true) -- 打开调试开关, 可以看到和服务器交互的明文命令和返回值
    while true do
        sys.wait(1000)
        log.info("ftp 启动")

        log.info("登陆FTP服务器", server_ip, server_port, server_username, server_password, is_ssl)
        result = ftp.login(adapter, server_ip, server_port, server_username, server_password, is_ssl).wait()
        log.info("ftp 登陆结果", result)


        log.info("空操作，防止连接断掉", ftp.command("NOOP").wait())
        log.info("报告远程系统的操作系统类型", ftp.command("SYST").wait())

        -- TYPE A: ASCII模式传输, TYPE I: 二进制模式传输, 必须指定
        log.info("指定文件类型", ftp.command("TYPE I").wait())

        -- 显示当前工作目录名, 非必须的操作
        log.info("显示当前工作目录名", ftp.command("PWD").wait())

        -- 演示创建和删除目录, 非必须的操作
        log.info("创建一个目录 目录名为QWER", ftp.command("MKD QWER").wait())
        log.info("改变当前工作目录为QWER", ftp.command("CWD /QWER").wait())

        log.info("返回上一层目录", ftp.command("CDUP").wait())
        log.info("删除名为QWER的目录", ftp.command("RMD QWER").wait())

        -- 演示获取当前工作目录下的文件列表, 非必须的操作
        log.info("获取当前工作目录下的文件名列表", ftp.command("LIST").wait())
        
        -- 生成至少51KB的测试数据 (52KB = 53248字节)
        local target_size = 52*1024
        local test_data = ""
        
        -- 使用循环生成足够大的数据
        log.info("开始生成测试数据，目标大小:", target_size, "字节")
        while #test_data < target_size do
            -- 每次生成1KB的随机数据，直到达到目标大小
            local chunk_size = math.min(1024, target_size - #test_data)
            local chunk = crypto.trng(chunk_size)
            test_data = test_data .. chunk
            -- log.info("已生成数据:", #test_data, "/", target_size, "字节")
        end
        
        log.info("测试数据生成完成，总大小:", #test_data, "字节")
        
        -- 把数据写到本地目录
        log.info("在本地创建一个文件", "文件名及其目录为" .. local_name)
        io.writeFile(local_name, test_data)
        log.info("本地文件大小", #test_data, "字节")
        log.info("本地文件大小(KB)", #test_data / 1024, "KB")
        
        -- 把文件上传到服务器去
        log.info("上传本地的" .. local_name, "到服务器上并且更名为" .. remote_name)
        result = ftp.push(local_name, remote_name).wait()
        log.info("上传结果是", result)

        -- 打印一下服务器当前目录下的文件列表
        log.info("获取当前工作目录下的文件名列表", ftp.command("LIST").wait())

        -- 从服务器上下载刚才上传的文件
        log.info("下载服务器上的" .. remote_name, "存放在" .. remote_name)
        result = ftp.pull(remote_name, remote_name).wait()
        log.info("下载结果是", result)

        -- 检查下载的文件大小
        local downloaded_data = io.readFile(remote_name)
        if downloaded_data then
            log.info("下载文件实际大小", #downloaded_data, "字节")
            log.info("下载文件实际大小(KB)", #downloaded_data / 1024, "KB")
            log.info("期望文件大小", #test_data, "字节")
            log.info("期望文件大小(KB)", #test_data / 1024, "KB")
            
            if #downloaded_data ~= #test_data then
                log.warn("警告：下载文件大小与期望大小不一致！")
                log.warn("期望大小:", #test_data, "字节 (", #test_data / 1024, "KB)")
                log.warn("实际大小:", #downloaded_data, "字节 (", #downloaded_data / 1024, "KB)")
                log.warn("大小差异:", #test_data - #downloaded_data, "字节")
            end
        else
            log.error("无法读取下载的文件")
        end

        -- 比较一下上传和下载的数据是否一致
        local downloaded_data = io.readFile(remote_name)
        if downloaded_data and downloaded_data == test_data then
            log.info("上传和下载的数据一致性验证通过")
        else
            log.error("上传和下载的数据一致性验证失败")
            if downloaded_data then
                log.info("原始数据长度:", #test_data, "字节 (", #test_data / 1024, "KB)")
                log.info("下载数据长度:", #downloaded_data, "字节 (", #downloaded_data / 1024, "KB)")
            else
                log.error("无法读取下载的数据")
            end
        end

        -- 删除服务器上的测试文件
        sys.wait(1000) -- 等一秒 防止删除失败
        log.info("删除FTP服务器当前目录下的" .. remote_name)
        result = ftp.command("DELE " .. remote_name).wait()
        log.info("删除结果是", result)

        -- 结束测试，关闭和服务器的连接
        sys.wait(1000) -- 等一秒 防止关闭失败
        log.info("关闭本次和服务器之间链接")
        result = ftp.close().wait()
        log.info("ftp 结束", result)

        -- 把本地的临时文件都删掉
        log.info("删除本地的临时文件", local_name, remote_name)
        os.remove(local_name)
        os.remove(remote_name)

        -- 最后, 打印一下内存状态
        log.info("打印内存状态")
        log.info("meminfo", "lua", rtos.meminfo("lua"))
        log.info("meminfo", "sys", rtos.meminfo("sys"))


        -- 等15秒, 继续下一轮测试
        log.info("等待15秒，继续下一轮测试")
        sys.wait(15000)
    end
end

sys.taskInit(ftp_test)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
