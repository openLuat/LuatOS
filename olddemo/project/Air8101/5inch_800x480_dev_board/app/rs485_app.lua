--[[
    gpio12方向
    gpio29供电使能
    gpio30/31 uart2
]]

local uartid = 2        -- 根据实际设备选取不同的uartid
local uart485Pin = 12   -- 用于控制485接收和发送的使能引脚

gpio.setup(29, 1)

--初始化
uart.setup(uartid, 9600, 8, 1, uart.NONE, uart.LSB, 1024, uart485Pin, 0, 2000)

-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid, "receive", function(id, len)
    local s = ""
    repeat
        s = uart.read(id, 128)
        if #s > 0 then -- #s 是取字符串的长度
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            log.info("uart", "receive", id, #s, s)

            -- uart.write(uartid, s)

            --以下两行代码是因为内核固件有bug，没办法自动切换；
            --所以不得已
            -- timer.mdelay(200)
            -- gpio.setup(uart485Pin, 0)

            -- log.info("uart", "receive", id, #s, s:toHex()) --如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
        end
    until s == ""
end)



sys.taskInit(function()
    -- 循环两秒向串口发一次数据
    while true do
        sys.wait(2000)
        uart.write(uartid, "test data.")
    end
end)
