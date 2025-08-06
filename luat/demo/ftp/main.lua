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

local is_ssl = flase -- 非ssl加密连接
-- local is_ssl =true --如果是不带证书的加密打开这句话

-- local ssl_encrypt = {
--     server_cert = "/luadb/server_cert.cert",--服务器ca证书数据
--     client_cert = "/luadb/client_cert.cert",--客户端证书数据
--     client_key = "/luadb/client_key",-- 客户端私钥加密数据
--     client_password = "naovswoivbfpfvjwpojv[pawjb[dsfjb]]"--客户端私钥口令数据
-- }

-- local is_ssl = ssl_encrypt --如果是带证书的加密，请将上述ssl_encrypt内的文件名换成自己的

local local_name = "/123.txt" -- 模块内部文件名及其路径
local remote_name = "/12222.txt" -- 服务器上的文件名及其路径

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
    while true do
        sys.wait(1000)
        log.info("ftp 启动")

        log.info("登陆FTP服务器",
            ftp.login(nil, server_ip, server_port, server_username, server_password, is_ssl).wait())

        log.info("空操作，防止连接断掉", ftp.command("NOOP").wait())
        log.info("报告远程系统的操作系统类型", ftp.command("SYST").wait())

        log.info("指定文件类型", ftp.command("TYPE I").wait())
        log.info("显示当前工作目录名", ftp.command("PWD").wait())
        log.info("创建一个目录 目录名为QWER", ftp.command("MKD QWER").wait())
        log.info("改变当前工作目录为QWER", ftp.command("CWD /QWER").wait())

        log.info("返回上一层目录", ftp.command("CDUP").wait())
        log.info("删除名为QWER的目录", ftp.command("RMD QWER").wait())

        log.info("获取当前工作目录下的文件名列表", ftp.command("LIST").wait())

        log.info("在本地创建一个文件", "文件名及其目录为" .. local_name)
        io.writeFile(local_name, "23noianfdiasfhnpqw39fhawe;fuibnnpw3fheaios;fna;osfhisao;fadsfl")
        --[[如果下载失败，部分服务器可能会直接断开本次连接，如果遇到下述打印
            net_lwip_tcp_err_cb 662:adapter 1 socket 20 not closing, but error -14
            是正常的，此处打印服务器主动断开客户端时会出现
        ]]
        log.info("下载服务器上的" .. remote_name, ftp.pull(remote_name, remote_name).wait())

        local f = io.open(remote_name, "r") -- 只读的方式打开服务器上下载的文件
        if f then
            local data = f:read("*a")
            f:close()
            log.info("ftp", "下载的文件" .. remote_name .. "内容是", data)
        else
            log.info("fs", "打开下载的文件失败")
        end
        sys.wait(1000) -- 等一秒 防止删除失败
        log.info("删除FTP服务器当前目录下的" .. remote_name, ftp.command("DELE " .. remote_name).wait())
        sys.wait(1000) -- 等一秒 防止覆盖失败
        log.info("上传本地的" .. local_name, "到服务器上并且更名为" .. remote_name,
            ftp.push(local_name, remote_name).wait())
        sys.wait(1000) -- 等一秒 防止关闭失败
        log.info("关闭本次和服务器之间链接", ftp.close().wait())
        log.info("meminfo", rtos.meminfo("sys"))
        sys.wait(15000)
    end
end

sys.taskInit(ftp_test)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
