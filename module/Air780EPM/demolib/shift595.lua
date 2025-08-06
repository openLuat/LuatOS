--[[
@module shift595
@summary shift595 74HC595芯片
@version 1.0
@date    2023.08.30
@author  lulipro
@usage
--注意:
--1、初始化时必须提供sclk移位时钟引脚和dat数据引脚，rclk根据应用需求可选
--2、AIR101官方核心板，底层为LuatOS-SoC_V0017_AIR101.soc，经测试此脚本库的串行时钟频率为18KHz
--用法实例：
--硬件模块：双595驱动的共阳极4位数码管
local shift595 = require("shift595")
sys.taskInit(function() 

    shift595.init(pin.PB08,pin.PB09,pin.PB10)  -- sclk,dat,rclk
    
    while 1 do
        local wei = 1
        for i = 0, 3, 1 do
            shift595.out(0x82,shift595.MSB)--发送段数据 ，然后是位选数据
            shift595.out(wei,shift595.MSB)--发送段数据 ，然后是位选数据
            shift595.latch() --锁存
            wei = wei<<1
            sys.wait(500)
        end
        sys.wait(1000)
    end
end
)
]]

local shift595 = {}

local sys = require "sys"

shift595.MSB=0     --字节串行输出时先发送最高位
shift595.LSB=1     --字节串行输出时先发送最低位

local SHIFT595_SCLK     --串行移位时钟引脚
local SHIFT595_DAT      --串行数据引脚
local SHIFT595_RCLK     --锁存信号时钟引脚


--[[
75hc595芯片初始化
@api shift595.init(sclk,dat,rclk)
@number sclk,定义驱动595串行时钟信号的引脚
@number dat,定义驱动595串行数据的引脚
@number rclk,定义驱动595锁存信号的引脚，可选
@usage
shift595.init(pin.PB08,pin.PB09,pin.PB10)  -- sclk,dat,rclk
]]
function shift595.init(sclk,dat,rclk)
    SHIFT595_SCLK = gpio.setup(sclk, 1)
    SHIFT595_DAT  = gpio.setup(dat, 1)
    
    if rclk then
        SHIFT595_RCLK = gpio.setup(rclk, 1)
    else
        SHIFT595_RCLK = nil
    end
end


--[[
串行输出一个字节到74hc595芯片的移位寄存器中
@api shift595.out(dat,endian)
@number dat,发送的字节数据
@number endian,指定发送字节数据时的大小端模式，有shift595.MSB和shift595.LSB两种参数可选。默认shift595.MSB
@usage
shift595.out(0x82,shift595.MSB)
shift595.out(0x82)  --默认shift595.MSB，与上面等价
]]
function shift595.out(dat,endian)
    local mbit
    for i = 0, 7, 1 do
        SHIFT595_SCLK(0)
        if endian == shift595.LSB then
            mbit = ((dat>>i)&0x01~=0) and 1 or 0
        else
            mbit = ((dat<<i)&0x80~=0) and 1 or 0
        end
        SHIFT595_DAT(mbit)
        SHIFT595_SCLK(1)
    end
end


--[[
给74hc595芯片的RCLK线一个高脉冲，使得移位寄存器中的数据转移到锁存器中，当OE使能时，数据就输出到QA~QH引脚上。如果初始化时没用到rclk引脚则此函数调用无效。
@api shift595.latch()
@usage
shift595.latch()
]]
function shift595.latch()
    if SHIFT595_RCLK then
        SHIFT595_RCLK(0)
        SHIFT595_RCLK(1)
    end
end

return shift595