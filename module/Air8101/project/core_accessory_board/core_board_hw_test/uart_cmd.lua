--[[
本功能模块的业务逻辑为：
1、Air8101初始化UART1，波特率115200，数据位8，停止位1，无奇偶校验位，无流控；
2、PC上的串口工具（例如SSCOM）配置为相同参数；
3、Air8101接收PC上串口工具发送过来的测试指令（以回车换行两个字符结尾）；
3、根据测试指令测试Air8101核心板硬件功能；
   (1) 接收到GPIO$id\r\n时，开始测试GPIO$id，$id表示具体的GPIO ID，例如测试GPIO2时，指令为GPIO2\r\n；
       核心板接收到这种指令时，会返回"GPIO$id test starts, 1s high level, 1s low level, please check with a multimeter or oscilloscope"给PC串口工具；
       同时会将对应的GPIO配置为输出，每隔一秒切换一次输出的高低电平；
       通过万用表或者示波器观察电压即可，高电平在3V左右，低电平在0V左右表示正常；
       这条测试指令本意是测试可以用作GPIO的引脚，一共56个，分以下几种情况测试：
       <1> GPIO0和GPIO1，这2个GPIO不能测试，因为这两个GPIO和UART1复用，我们已经使用了UART1来收发测试指令，只要和PC串口工具的通信正常，就表示这两个硬件引脚功能正常；
       <2> GPIO2到GPIO9、GPIO12到GPIO55，PC串口工具发送测试指令后，使用万用表测试对应管脚的电平，高电平持续1秒，在3V左右，低电平持续1秒，在0V左右；
       <3> GPIO10和GPIO11，默认做UART0使用，不能测试GPIO功能，只要通过Luatools观察日志输出正常，并且通过Luatools上的重启模块按钮可以重启Air8101，就表示这两个硬件引脚功能正常；
]]


--测试使用UART1
local UART_ID = 1

local read_buf = ""

local function write(s)
    uart.write(UART_ID, s.."\r\n")
end

--解析UART1收到的测试指令
local function proc(item)
    log.info("uart_cmd.proc",item)
    --如果测试指令字符串以GPIO开头
    if item:match("^GPIO") then
        --解析出来GPIO的ID，注意这里的ID是string格式
        local gpio_id = item:match("^GPIO(%d+)\r")
        if not gpio_id then
            write("cmd format error, no GPIO ID!!!")
        else
            --将gpio_id由string格式转换为number格式
            --方便后续可以和数字直接比较
            gpio_id = tonumber(gpio_id)

            --GPIO0和GPIO1，这2个GPIO不能测试，因为这两个GPIO和UART1复用，我们已经使用了UART1来收发测试指令，只要和PC串口工具的通信正常，就表示这两个硬件引脚功能正常；
            --GPIO10和GPIO11，默认做UART0使用，不能测试GPIO功能，只要通过Luatools观察日志输出正常，并且通过Luatools上的重启模块按钮可以重启Air8101，就表示这两个硬件引脚功能正常；
            if gpio_id==0 or gpio_id==1 or gpio_id==10 or gpio_id==11 then
                --返回提示信息给PC串口工具
                write("GPIO"..gpio_id.." need not test!!!")
            --GPIO2到GPIO9、GPIO12、GPIO14到GPIO55，PC串口工具发送测试指令后，使用万用表测试对应管脚的电平，高电平持续1秒，在3V左右，低电平持续1秒，在0V左右；
            elseif gpio_id>=2 and gpio_id<=55 then
                --发布GPIO测试消息，gpio_test.lua收到消息后，会执行GPIO测试动作
                sys.publish("GPIO_TEST_IND", gpio_id)
                --返回提示信息给PC串口工具
                write("GPIO"..gpio_id.." test starts, 1s high level, 1s low level, please check with a multimeter or oscilloscope")
            else
                --返回提示信息给PC串口工具
                write("GPIO"..gpio_id.." doesn't exist, input error!!!")
            end
        end
    --非法的测试指令
    else
        write("cmd format invalid!!!")
    end
end



--UART1的数据接收中断处理函数，UART1接收到数据时，会执行此函数
local function read()
    local s
    while true do
        --非阻塞读取UART1接收到的数据，最长读取128字节
        s = uart.read(UART_ID, 128)
        log.info("uart_cmd.read", s)
        --如果没有读到数据，直接退出
        if not s or string.len(s) == 0 then break end
        --将读到的数据拼接到read_buf缓冲区中
        read_buf = read_buf..s
    end

    --如果在read_buf缓冲区中找到了\r字符
    --表示read_buf中至少有一条完整的测试指令
    if read_buf:match("\r") then
        --执行proc函数处理这条测试指令
        proc(read_buf)
        --清空read_buf缓冲区
        read_buf = ""
    end
end



--初始化UART1，波特率115200，数据位8，停止位1
uart.setup(UART_ID, 115200, 8, 1)
--注册UART1的数据接收中断处理函数，UART1接收到数据时，会执行read函数
uart.on(UART_ID,"receive",read)


