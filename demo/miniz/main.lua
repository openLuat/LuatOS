
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "minizdemo"
VERSION = "1.0.0"

sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()
    sys.wait(1000)
    -- 压缩过的字符串, 为了方便演示, 这里用了base64编码
    -- 大部分MCU设备的内存都比较小, miniz.compress 通常在服务器端完成,这里就不演示了
    -- miniz能解压标准zlib数据流
    local b64str = "eAEFQIGNwyAMXOUm+E2+OzjhCCiOjYyhyvbVR7K7IR0l+iau8G82eIW5jXVoPzF5pse/B8FaPXLiWTNxEMsKI+WmIR0l+iayEY2i2V4UbqqPh5bwimyEuY11aD8xeaYHxAquvom6VDFUXqQjG1Fek6efCFfCK0b0LUnQMjiCxhUT05GNL75dFUWCSMcjN3EE5c4Wvq42/36R41fa"
    local str = b64str:fromBase64()

    local dstr = miniz.uncompress(str)
    -- 压缩过的数据长度 156
    -- 解压后的数据长度,即原始数据的长度 235
    log.info("miniz", "compressed", #str, "uncompressed", #dstr)
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
