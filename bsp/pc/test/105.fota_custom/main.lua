_G.sys = require("sys")

sys.taskInit(function()
    -- 测试libfota自定义url
    local libfota = require "libfota"

    libfota.request(nil, "http://httpbin.air32.cn:123/abc.bin")
end)

sys.run()
