
_G.sys = require("sys")

sys.taskInit(function()
    while 1 do
        -- 仅64bit固件测试效果有效
        local a = 123.1234567890123456
        local b = 223.1234567890123456
        local data = pack.pack(">dd", a, b)
        log.info("打包后", data:toHex())

        -- 3FF3C0CA428C1D2B3FF3CD13FCEA526B
        -- 解包
        local next, c, d = pack.unpack(data, ">dd")
        log.info("解包后", string.format("%.12f %.12f", c, d))

        -- 再次打包
        local data2 = pack.pack(">dd", a, b)
        log.info("打包后", data2:toHex())

        log.info("json测试", json.encode({a=a, b=b}, "7f"))

        local next, e = pack.unpack(string.fromHex("41423775CEB8E676"), ">d")
        log.info("解包后", string.format("%.15f", e))
        log.info("解包后", e)

        sys.wait(100000)
    end

end)

sys.run()
