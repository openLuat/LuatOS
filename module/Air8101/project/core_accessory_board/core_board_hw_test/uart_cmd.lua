--[[
本功能模块的业务逻辑为：
1、以115200波特率初始化UART1，可以和PC上的串口工具进行数据通信；
2、接收PC上串口工具发送过来的测试指令（以回车换行两个字符结尾）；
3、根据测试指令测试Air8101核心板硬件功能；
   (1) 接收到GPIO$id\r\n时，开始测试GPIO$id，$id表示具体的GPIO ID，例如2，测试GPIO2时，指令为GPIO2\r\n；
       核心板接收到这种指令时，会将对应的GPIO配置为输出，每隔一秒切换一次输出的高低电平，；
       过万用表或者示波器观察电压即可，高电平在3V左右，低电平在0V左右表示正常；
]]


--测试使用UART1
local UART_ID = 1

local read_buf = ""

local function write(s)
    uart.write(UART_ID, s.."\r\n")
end

local function proc(item)
    log.info("uart_cmd.proc",item)
    if item:match("^GPIO") then
        local gpio_id = item:match("^GPIO(%d+)\r")
        if not gpio_id then
            write("cmd format error, no GPIO ID!!!")
        else
            sys.publish("GPIO_TEST_IND", tonumber(gpio_id))
            write("GPIO"..gpio_id.." test starts, 1s high level, 1s low level, please check with a multimeter or oscilloscope")
        end
    end
end


local function read()
    local s
    while true do        
        s = uart.read(UART_ID, 128)
        log.info("uart_cmd.read", s)
        if not s or string.len(s) == 0 then break end
        read_buf = read_buf..s
    end
    if read_buf:match("\r") then
        proc(read_buf)
        read_buf = ""
    end
end



--初始化UART1，波特率115200，数据位8，停止位1
uart.setup(UART_ID, 115200, 8, 1)
--注册UART1的数据接收中断处理函数，UART1接收到数据时，会执行read函数
uart.on(UART_ID,"receive",read)


