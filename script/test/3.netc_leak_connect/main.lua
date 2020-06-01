
local sys = require "sys"

-- 如果是wifi,那就连一下wifi咯
if wlan ~= nil then
    wlan.connect("uiotabc", "12345678")
end

local tcount = 0        -- 当前测试完成数
local testcount = 10000 -- 总测试次数
sys.taskInit(function()
    -- 做个大的循环
    while tcount < testcount do
        while not socket.isReady() then sys.waitUntil("NET_READY", 1000) end
        local netc = socket.tcp()
        netc:host("wwww.baidu.com")
        netc:port(80)
        netc:on("connect", function(id, re)
            if re == 0 then
                netc:send("GET / HTTP/1.0\r\n\r\n")
            end
        end)
        netc:on("recv", function(id, data)
            log.info("netc", "data recv", data)
        end)
        if netc:start() == 0 then
            while netc:closed() == 0 then sys.waitUntil("NETC_END_" .. s:id(), 1000) end
        end
        netc:close()
        sys.wait(1000) -- 等待1秒后继续测试
    end
end)

sys.run()
