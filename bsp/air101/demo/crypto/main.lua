
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "cryptodemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")


sys.timerLoopStart(function()
    --sys.wait(3000) -- 开机后展示crypto功能

    -- MD5,输出结果已经hex编码
    log.info("md5", crypto.md5("abc"))
    log.info("hmac_md5", crypto.hmac_md5("abc", "1234567890"))

    -- SHA1,输出结果已经hex编码
    log.info("sha1", crypto.sha1("abc"))
    log.info("hmac_sha1", crypto.hmac_sha1("abc", "1234567890"))

    -- SHA256,输出结果已经hex编码
    log.info("sha256", crypto.sha256("abc"))
    log.info("hmac_sha256", crypto.hmac_sha256("abc", "1234567890"))

    -- SHA512,输出结果已经hex编码
    log.info("sha512", crypto.sha512("abc"))
    log.info("hmac_sha512", crypto.hmac_sha512("abc", "1234567890"))


end, 2000)

sys.taskInit(function()
    wdt.init(15000)
    sys.timerLoopStart(wdt.feed, 10000)
    while 1 do
        sys.wait(500)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
