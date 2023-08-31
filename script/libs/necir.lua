--[[
@module necir
@summary necir NEC协议红外通信
@version 1.0
@date    2023.08.30
@author  lulipro
@usage
--注意:
1、由于本库基于标准四线SPI接口实现，所以虽然只用到了MISO引脚，但是其他3个SPI相关引脚无法作为其他用途
2、TODO：暂未实现红外数据发送功能

--用法实例
--硬件模块：VS1838及其兼容的一体化接收头
--接线示意图
 ____________________              ____________________
|                    |            |                    |
|           SPI_MISO |------------| OUT                |
| Air10x             |   |        |       VS1838       |
|           IRQ_GPIO |---         |     一体化接收头    |
|                    |            |                    |
|____________________|            |____________________| 

local necir = require("necir")

--定义数据处理回调函数
local function my_ir_cb(address,data)
    local led = gpio.setup(pin.PB08,0)
    log.info('get ir msg','addr=',address,'data=',data)
    if data == 70 then led(0) end
    if data == 21 then led(1) end
end

sys.taskInit(function()
    necir.init(0,pin.PA_00,my_ir_cb)
    while 1 do
        sys.wait(200)
        necir.recv()
    end
end)

]]

local necir = {}

local sys = require "sys"

local NECIR_IRQ_PIN               --下降沿中断检测引脚
local NECIR_SPI_ID                --使用的SPI接口的ID
local NECIR_SPI_BAUDRATE = 14222  --SPI时钟频率，单位HZ

local recvBuff                    --SPI接收数据缓冲区
local RECV_BUFF_LEN = 16+8+48+48  --SPI接收数据的长度

local addressP               --地址码
local addressN               --地址码取反
local dataP                  --数据码
local dataN                  --数据码取反

local recv_callback          --数据接收完成后的用户回调函数

--[[
==============实现原理================================================    
可以发现，NEC协议中无论是引导信号，逻辑0还是逻辑1，都是由若干个562.5us的周期组成的。
例如
  引导信号: 16个562.5us的低电平+8个562.5us的高电平组成  
  逻 辑  1：1个562.5us的低电平+3个562.5us的高电平组成 
  逻 辑  0：1个562.5us的低电平+1个562.5us的高电平组成

因此我们使用14222Hz的SPI去读取，即每个收到的SPI字节就是占用562.5us。
则
  引导信号: 16个0x00 + 8个0xff组成
  逻 辑  1：1个0x00 + 3个0xff组成
  逻 辑  0：1个0x00 + 1个0xff组成

考虑到LuatOS中断响应存在一定延迟，导致SPI接收的信号与实际输出的信号存在一定的滞后，
因此对接收到的SPI字节数据进行中间bit采样而非判断整个字节。
即：
  如果字节的中间一位是0，则认为整个字节对应的信号都是低电平
  如果字节的中间一位是1，则认为整个字节对应的信号都是高电平
本库对每个字节使用bit4作为采样点，因此需要将收到的字节对0x10进行按位与运算。


       采样点1     采样点2    采样点3     不关心
          |          |          |
逻辑1: 0000_0000  1111_1111  1111_1111  1111_1111

                            [    下一个逻辑位    ]   
逻辑0: 0000_0000  1111_1111  0000_0000  XXXX_XXXX

如果这个3个采样点满足：0,1,1的规则，则认为收到的是逻辑1，否则为逻辑0。
]]
local function irq_func()
    gpio.setup(NECIR_IRQ_PIN,nil,gpio.PULLUP)  --将中断引脚改为普通输入模式，防止反复触发中断
    recvBuff =  spi.recv(NECIR_SPI_ID, RECV_BUFF_LEN) --通过SPI接收红外接收头输出的解调数据
    
    local sample_byte1
    local sample_byte2
    local sample_byte3
    local si = 16+8 +1  --跳过引导码信号字节

    --数据重新初始化
    addressP = 0
    addressN = 0
    dataP    = 0
    dataN    = 0

    --解析出地址码
    for i = 0, 7, 1 do
        sample_byte1 = string.byte(string.sub(recvBuff,si,si))
        sample_byte2 = string.byte(string.sub(recvBuff,si+1,si+1))
        sample_byte3 = string.byte(string.sub(recvBuff,si+1+1,si+1+1))

        if (sample_byte1) and (sample_byte1&0x10 == 0) and
            (sample_byte2) and (sample_byte2&0x10 ~= 0) and
            (sample_byte3) and (sample_byte3&0x10 ~= 0)
        then
            --这个bit为1(NEC协议为LSB First)
            addressP = (addressP | (1<<i))
            si = si + 4
        else
            --这个bit为0
            si = si + 2
        end
    end

    --解析出地址码取反
    for i = 0, 7, 1 do
        sample_byte1 = string.byte(string.sub(recvBuff,si,si))
        sample_byte2 = string.byte(string.sub(recvBuff,si+1,si+1))
        sample_byte3 = string.byte(string.sub(recvBuff,si+1+1,si+1+1))

        if (sample_byte1) and (sample_byte1&0x10 == 0) and
            (sample_byte2) and (sample_byte2&0x10 ~= 0) and
            (sample_byte3) and (sample_byte3&0x10 ~= 0 ) 
        then
            --这个bit为1(NEC协议为LSB First)
            addressN = (addressN | (1<<i))
            si = si + 4
        else
            --这个bit为0
            si = si + 2
        end
    end
    
    --解析出数据码
    for i = 0, 7, 1 do
        sample_byte1 = string.byte(string.sub(recvBuff,si,si))
        sample_byte2 = string.byte(string.sub(recvBuff,si+1,si+1))
        sample_byte3 = string.byte(string.sub(recvBuff,si+1+1,si+1+1))

        if (sample_byte1) and (sample_byte1&0x10 == 0) and
            (sample_byte2) and (sample_byte2&0x10 ~= 0) and
            (sample_byte3) and (sample_byte3&0x10 ~= 0 ) 
        then
            --这个bit为1(NEC协议为LSB First)
            dataP = (dataP | (1<<i))
            si = si + 4
        else
            --这个bit为0
            si = si + 2
        end
    end
    
    --解析出数据码取反
    for i = 0, 7, 1 do
        sample_byte1 = string.byte(string.sub(recvBuff,si,si))
        sample_byte2 = string.byte(string.sub(recvBuff,si+1,si+1))
        sample_byte3 = string.byte(string.sub(recvBuff,si+1+1,si+1+1))

        if (sample_byte1) and (sample_byte1&0x10 == 0) and
            (sample_byte2) and (sample_byte2&0x10 ~= 0) and
            (sample_byte3) and (sample_byte3&0x10 ~= 0 ) 
        then
            --这个bit为1(NEC协议为LSB First)
            dataN = (dataN | (1<<i))
            si = si + 4
        else
            --这个bit为0
            si = si + 2
        end
    end

    --对收到的红外数据进行校验并调用 用户回调函数处理
    if (addressP+addressN == 255 ) and (dataP+dataN == 255) then
        --log.info('DataValid,go CallBack')
        if recv_callback then recv_callback(addressP,dataP) end
    end
    --log.info(recvBuff:toHex())
    --log.info('necir',addressP,addressN,dataP,dataN)
end


--[[
necir初始化
@api necir.init(spi_id,irq_pin,recv_cb)
@number spi_id,使用的SPI接口的ID
@number irq_pin,使用的中断引脚
@function recv_cb,红外数据接收完成后的回调函数，回调函数有2个参数，第一个参数是收到的地址码，第二个参数是收到的数据码
@usage
local function my_ir_cb(address,data)
    local led = gpio.setup(pin.PB08,0)
    log.info('get ir msg','addr=',address,'data=',data)
    if data == 70 then led(0) end
    if data == 21 then led(1) end
end

necir.init(0,pin.PA_00,my_ir_cb)
]]
function necir.init(spi_id,irq_pin,recv_cb)
    NECIR_SPI_ID     = spi_id
    NECIR_IRQ_PIN    = irq_pin
    recv_callback    = recv_cb
    --spi接口初始化
    spi.setup(NECIR_SPI_ID, nil, 0,0 , 8, NECIR_SPI_BAUDRATE, spi.MSB, spi.master, 1)
end


--[[
开启一次红外数据接收过程
@api necir.recv()
@usage
necir.recv()
]]
function necir.recv()
    --将引脚设置输入下降沿中断模式，检测引导码产生的下降沿
    gpio.setup(NECIR_IRQ_PIN,irq_func,gpio.PULLUP,gpio.FALLING)
end


return necir