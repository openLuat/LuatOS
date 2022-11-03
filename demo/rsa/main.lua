
--- 模块功能：rsa示例
-- @module rsa
-- @author wendal
-- @release 2022.11.03

--[[
提醒: 本demo需要用到公钥和私钥, demo目录中的公钥私钥文件是演示用的, 实际使用请自行生成

生成公钥私钥, 可使用openssl命令, 或者找个网页生成. 2048 是RSA位数, 最高支持4096,但不推荐,因为很慢.

openssl genrsa -out privkey.pem 2048
openssl rsa -in privkey.pem -pubout -out public.pem


-- 下载脚本和资源到设备时, 务必加上本目录下的两个 pem 文件, 否则本demo无法运行.
]]

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "rsademo"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

-- 因为这是通用demo, air101/air103跑满速才不至于太慢-_-
if rtos.bsp() == "AIR101" or rtos.bsp() == "AIR103" then
    if mcu then
        mcu.setClk(240)
    end
end

sys.taskInit(function()
    -- 为了日志能正常显示出来, 这里特意延时2秒, 实际使用中不需要
    sys.wait(2000)

    -- 检查是否带rsa库, 没有就提醒一下吧
    if not rsa then
        log.warn("main", "this demo need rsa lib!!!")
        return
    end

    -- 读取公钥并马上加密数据
    local res = rsa.encrypt((io.readFile("/luadb/public.pem")), "abc")
    -- 打印结果
    log.info("rsa", "encrypt", res and #res or 0, res and res:toHex() or "")

    -- 下面是解密, 通常不会在设备端进行, 这里主要是演示用法, 会很慢
    if res then
        -- 读取私钥, 然后解码数据
        local dst = rsa.decrypt((io.readFile("/luadb/privkey.pem")), res, "")
        log.info("rsa", "decrypt", dst and #dst or 0, dst and dst:toHex() or "")
    end

    -- 演示签名和验签
    local hash = crypto.sha1("1234567890"):fromHex()
    -- 签名通常很慢, 通常是服务器做
    local sig = rsa.sign((io.readFile("/luadb/privkey.pem")), rsa.MD_SHA1, hash, "")
    log.info("rsa", "sign", sig and #sig or 0, sig and sig:toHex() or "")
    if sig then
        -- 验签是很快的
        local ret = rsa.verify((io.readFile("/luadb/public.pem")), rsa.MD_SHA1, hash, sig)
        log.info("rsa", "verify", ret)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
