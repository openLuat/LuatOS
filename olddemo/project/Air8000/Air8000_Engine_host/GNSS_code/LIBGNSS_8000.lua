mcu.hardfault(0)    --死机后停机，一般用于调试状态

--上电就打开GPIO25 GNSS电源开
local agpio4 = gpio.setup(24,0)
local gnss_vdd = gpio.setup(25,0)
local gps_uart_id = 2 -- 根据实际设备选取不同的uartid
uart.setup(gps_uart_id, 115200)

--打开或者关闭GNSS的函数，传1打开，传0关闭
local function gnss_power(tag)
    if tag ==1 or tag ==0 then
        log.info("打开 or 关闭GNSS电源",tag)

        agpio4(tag)
        sys.wait(100)
        gnss_vdd(tag)
    else
        log.info("传参错误")
        
    end
end

sys.taskInit(function()

    log.info("GPS", "start")
    gnss_power(1)
    -- 绑定uart,底层自动处理GNSS数据
    -- 第二个参数是转发到虚拟UART, 方便上位机分析
    libgnss.bind(gps_uart_id, uart.VUART_0)
 
    sys.wait(200) -- GPNSS芯片启动需要时间
    -- 调试日志,可选
    libgnss.debug(true)
end)

