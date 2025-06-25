--[[
本文件为测试应用功能模块，用来测试其他功能模块的外部接口；
仅调试需要，项目量产时不需要；
]]


-- 模拟四个socket client从server收到了数据，然后publish消息"RECV_DATA_FROM_SERVER"
sys.taskInit(function()
    local cnt = 0

    while true do
        cnt = cnt+1

        sys.wait(1000)
        sys.publish("RECV_DATA_FROM_SERVER", "recv from tcp server: ", cnt)

        sys.wait(1000)
        sys.publish("RECV_DATA_FROM_SERVER", "recv from udp server: ", cnt)

        sys.wait(1000)
        sys.publish("RECV_DATA_FROM_SERVER", "recv from tcp ssl server: ", cnt)

        sys.wait(1000)
        sys.publish("RECV_DATA_FROM_SERVER", "recv from tcp ssl ca server: ", cnt)
    end

end)

-- 模拟订阅处理串口应用功能模块和定时器应用功能模块的"SEND_DATA_REQ"消息
sys.subscribe("SEND_DATA_REQ", function(tag, data)
    log.info("test_app.SEND_DATA_REQ", "send from "..tag..": "..data)
end)
