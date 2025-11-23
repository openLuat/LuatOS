
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "utf8demo"
VERSION = "1.0.0"

--[[
本demo需要http库, 大部分能联网的设备都具有这个库
http也是内置库, 无需require
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")


sys.taskInit(function()
    local str = "已答复撒旦法大法师发大水发生大发打撒"
    log.info("字节长度", #str) -- 字节长度
    log.info("字符长度", utf8.len(str)) -- 字符长度
    -- 逐个字符打印
    for p, c in utf8.codes(str) do
        log.info("字符", p, string.format("0x%04X", c))
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
