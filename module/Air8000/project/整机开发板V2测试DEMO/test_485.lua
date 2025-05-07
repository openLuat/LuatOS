
--[[
1.本demo可直接在Air8000整机开发板上运行，如有需要请luat.taobao.com 购买
2.演示485如何使用
3. 使用了如下管脚
[16, "UART1_TX", " PIN16脚,做UART1_TX用, 用于控制485"],
[17, "UART1_TX", " PIN17脚,做UART1_TX用, 用于控制485"],
[83, "GPIO16", " PIN83脚, 用于 485使能"],
[82, "GPIO17", " PIN82脚, 485 方向控制"],
4.程序运行逻辑为
4.1 启动后, 会每隔2秒向外输出“test data”
2. 程序会持续接受485 数据
]]
local taskName = "task_485"
local uartid = 1        -- 根据实际设备选取不同的uartid,整机开发板使用的是串口1
local uart485Pin = 17   -- 用于控制485接收和发送的使能GPIO(gpio17)

local function  setup_gpio()
    gpio.setup(16, 1)        --打开电源(开发板485供电脚是gpio16，用开发板测试需要开机初始化拉高gpio16)
    uart.setup(uartid, 9600, 8, 1, uart.NONE, uart.LSB, 1024, uart485Pin, 0, 2000)  -- 初始化485 的串口和485 的方向控制
end

local function receive(id, len)
    local s = ""
    repeat
        s = uart.read(id, 128)
        if #s > 0 then -- #s 是取字符串的长度
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            log.info("uart1", "receive", id, #s, s)
            -- log.info("uart", "receive", id, #s, s:toHex()) --如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
        end
    until s == ""
end

local function uart_485_task()
    setup_gpio()    --  初始化485
    uart.on(uartid,"receive",receive)    -- 初始化回调函数
    -- 循环两秒向串口发一次数据
    while true do
        sys.wait(2000)
        uart.write(uartid, "test data.")
    end
end


sysplus.taskInitEx(uart_485_task, taskName)   



