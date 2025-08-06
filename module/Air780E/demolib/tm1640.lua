--[[
@module tm1640
@summary tm1640 数码管和LED驱动芯片
@version 1.0
@date    2023.08.29
@author  lulipro
@usage
--注意:
--1、tm1640驱动的数码管应该选用共阴数码管
--2、tm1640也可以驱动LED，如果是LED，则应该将LED连接成共阴数码管内部相同的电路
--3、AIR101官方核心板，底层为LuatOS-SoC_V0017_AIR101.soc，经测试此脚本库的串行时钟频率为20KHz
-- 用法实例：
local tm1640 = require("tm1640")

sys.taskInit(function ()
    --共阴段码表，0~9的数字
    local NUM_TABLE_AX = {
        [0]=0x3f,[1]=0x06,[2]=0x5b,[3]=0x4f,[4]=0x66,
        [5]=0x6d,[6]=0x7d,[7]=0x07,[8]=0x7f,[9]=0x6f
    };   

    tm1640.init(pin.PB06,pin.PB07)  --clk,dat
    
    while 1 do
        for i = 0, 9, 1 do
            tm1640.setBright(tm1640.BRIGHT1)
            for grid = tm1640.GRID1, tm1640.GRID16, 1 do
                tm1640.sendDisplayData(grid,NUM_TABLE_AX[i])
            end
            sys.wait(200)
            tm1640.setBright(tm1640.BRIGHT3)
            sys.wait(200)
            tm1640.setBright(tm1640.BRIGHT5)
            sys.wait(200)
            tm1640.setBright(tm1640.BRIGHT8)
            sys.wait(200)
        end

        sys.wait(1000)

        tm1640.setBright(tm1640.BRIGHT5)
        for i = 0, 9, 1 do
            tm1640.clear()
            for grid = tm1640.GRID1, tm1640.GRID16, 1 do
                tm1640.sendDisplayData(grid,NUM_TABLE_AX[i])
                sys.wait(100)
            end
        end
    end
end)
]]
local tm1640 = {}

local sys = require "sys"

--数码管位选常量定义
tm1640.GRID1 = 0
tm1640.GRID2 = 1
tm1640.GRID3 = 2
tm1640.GRID4 = 3
tm1640.GRID5 = 4
tm1640.GRID6 = 5
tm1640.GRID7 = 6
tm1640.GRID8 = 7
tm1640.GRID9 = 8
tm1640.GRID10 = 9
tm1640.GRID11 = 10
tm1640.GRID12 = 11
tm1640.GRID13 = 12
tm1640.GRID14 = 13
tm1640.GRID15 = 14
tm1640.GRID16 = 15

--八级亮度常量定义
tm1640.BRIGHT1 = 0
tm1640.BRIGHT2 = 1
tm1640.BRIGHT3 = 2
tm1640.BRIGHT4 = 3
tm1640.BRIGHT5 = 4
tm1640.BRIGHT6 = 5
tm1640.BRIGHT7 = 6
tm1640.BRIGHT8 = 7

local is_display_on = 1                --显示开关标志变量
local bright        = tm1640.BRIGHT5   --亮度级别变量

local TM1640_CLK    --驱动时钟线的引脚
local TM1640_DAT    --驱动数据线的引脚


--串行通信起始条件
local function tm1640_strat()
    TM1640_CLK(1)
    TM1640_DAT(1)
    TM1640_DAT(0)
    TM1640_CLK(0)
end
--串行通信结束条件
local function tm1640_stop()
    TM1640_CLK(0)
    TM1640_DAT(0)
    TM1640_CLK(1)
    TM1640_DAT(1)
end

--串行发送一个字节，LSB First
local function tm1640_writeByte(data)
  if data~=nil then--防止未接入数码管或者测试时接线不稳定，传来空数据导致程序运行异常
    for i = 0, 7, 1 do
        local mbit = (data&0x01~=0) and 1 or 0
        TM1640_DAT(mbit)
        TM1640_CLK(1)
        data = data>>1
        TM1640_CLK(0)
        --data = data>>1 将这句话放在上面是为了尽量让时钟接近50%占空比
    end
  end
end



--[[
向TM1640的一个指定的位(grid)对应的显存发送指定的段数据进行显示
@api tm1640.sendDisplayData(grid,seg_data)
@number grid，定义位选参数，取值为tm1640.GRID1~tm1640.GRID16
@number seg_data，定义段数据参数
@usage
tm1640.sendDisplayData(tm1640.GRID1,0xff)
]]
function tm1640.sendDisplayData(grid,seg_data)
    if (grid >= tm1640.GRID1) and (grid <= tm1640.GRID16) then
        tm1640_strat()
        tm1640_writeByte(0xc0|grid)
        tm1640_writeByte(seg_data)
        tm1640_stop()
    end
end

--[[
清除TM1640的所有位(grid)对应的显存数据，即全部刷写为0
@api tm1640.clear()
@usage
tm1640.clear()
]]
function tm1640.clear()
    for i = tm1640.GRID1, tm1640.GRID16, 1 do
        tm1640.sendDisplayData(i,0)
    end
end

--[[
打开TM1640的显示，此操作不影响显存中的数据
@api tm1640.open()
@usage
tm1640.open()
]]
function tm1640.open()
    is_display_on=1
    tm1640_strat()
    tm1640_writeByte(0x80|(is_display_on<<3)|(bright))
    tm1640_stop()
end

--[[
关闭TM1640的显示，此操作不影响显存中的数据
@api tm1640.close()
@usage
tm1640.close()
]]
function tm1640.close()
    is_display_on=0
    tm1640_strat()
    tm1640_writeByte(0x80|(is_display_on<<3)|(bright))
    tm1640_stop()
end

--[[
设置TM1640的显示亮度，此操作不影响显存中的数据
@api tm1640.setBright(bri)
@number 亮度参数，取值为tm1640.BRIGHT1~tm1640.BRIGHT8
@usage
tm1640.setBright(tm1640.BRIGHT8)
]]
function tm1640.setBright(bri)
    if bri>tm1640.BRIGHT8 then bri = tm1640.BRIGHT8 end
    if bri<tm1640.BRIGHT1 then bri = tm1640.BRIGHT1 end

    bright = bri
    tm1640_strat()
    tm1640_writeByte(0x80|(is_display_on<<3)|(bright))
    tm1640_stop()
end


--[[
TM1640的初始化
@api tm1640.init(clk,dat,bri)
@number clk，定义了时钟线驱动引脚
@number dat，定义了数据线驱动引脚
@number bri，初始亮度参数，可取的值为tm1640.BRIGHT1~tm1640.BRIGHT8。可选，默认值为tm1640.BRIGHT5。
@usage
tm1640.init(pin.PB06,pin.PB07)
tm1640.init(pin.PB06,pin.PB07,tm1640.BRIGHT8)
]]
function tm1640.init(clk,dat,bri)
    TM1640_CLK = gpio.setup(clk, 1)
    TM1640_DAT = gpio.setup(dat, 1)

    --设置为固定地址模式
    tm1640_strat()
    tm1640_writeByte(0x44)
    tm1640_stop()

    --如果设置了初始亮度
    if bri then
        if bri>tm1640.BRIGHT8 then bri = tm1640.BRIGHT8 end
        if bri<tm1640.BRIGHT1 then bri = tm1640.BRIGHT1 end
        bright = bri
    end

    tm1640.open()  --打开显示
    tm1640.clear() --清除显存数据
end


return tm1640