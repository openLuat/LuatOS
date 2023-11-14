--[[
    @module  vl53L1
    @summary vl53L1模块-激光测距传感器 
    @version 1.0
    @date    2023.11.14
    @author  Dozingfiretruck
    @usage

    引脚配置：
    GY_53L1           MCU
    VCC               3V3
    GND               GND
    RX                TX
    TX                RX

    测量说明：
    测量范围：5-4000mm(可选择短、中、长测量模式)
    单次测量：测量一次后需要重新发送单次输出距离数据指令


    --注意:因使用了sys.wait()所有api需要在协程中使用
    --注意:因注册了串口接收中断回调，所以数据在接收回调函数处理

    -- 用法实例
    GY_53L1=require"GY_53L1"
    local uart2=2
    sys.taskInit(function()
        sys.wait(2000)
        --初始化
        GY_53L1.setup(uart2)
        --设置模式，不设置为默认模式
        GY_53L1.Set_Mode(uart2,GY_53L1.measuring_short)
        while true do
            sys.wait(1000)
        end
    end)
]]

GY_53L1={}

--数据包table
local recv_data={}
--数据帧
recv_data.data=0
--帧头1
recv_data.head1=0
--帧头2
recv_data.head2=0
--本帧数据类型
recv_data.type=0
--数据量
recv_data.amount=0
--数据高8位
recv_data.hight=0
--数据低八位
recv_data.low=0
--测量模式
recv_data.mode=0
--校验和
recv_data.check_sum=0
--距离
local range=0

-----------------------------------------------可选择测量模式---------------------------------------------------

--默认模式连续输出、中距离、测量时间110ms、波特率9600

--输出模式设置指令：
GY_53L1.out_mode_coiled=string.char(0xA5,0x45,0xEA)   ---------------连续输出距离数据---1
--[[若设置为查询指令，则发一次指令测量一次]]
GY_53L1.out_mode_query=string.char(0xA5,0x15,0xBA)    ---------------单次输出距离数据---2


--保存配置指令：
GY_53L1.save=string.char(0xA5,0x25,0xCA)              ---------------掉电保存当前配置;包括波特率（重新上电起效）、测量模
                                         ---------------式、测量时间、输出模式设置
--测量模式设置指令：
GY_53L1.measuring_short=string.char(0xA5,0x51,0xF6)    ---------------短距离测量模式---1
GY_53L1.measuring_middle=string.char(0xA5,0x52,0xF7)   ---------------中距离测量模式（默认）---2
GY_53L1.measuring_long=string.char(0xA5,0x53,0xF8)     ---------------长距离测量模式---3
--测量时间设置指令：
GY_53L1.measuring_time_1=string.char(0xA5,0x61,0x06)   ---------------测量时间 110ms（默认）---1
GY_53L1.measuring_time_2=string.char(0xA5,0x62,0x07)   ---------------测量时间 200ms ---2
GY_53L1.measuring_time_3=string.char(0xA5,0x63,0x08)   ---------------测量时间 300ms ---3
GY_53L1.measuring_time_4=string.char(0xA5,0x64,0x09)   ---------------测量时间 55ms ---4
--波特率配置：
GY_53L1.ste_baut_1=string.char(0xA5,0xAE,0x53)         ---------------9600（默认）---1
GY_53L1.ste_baut_1=string.char(0xA5,0xAF,0x54)         ---------------115200---2

--例：
-- uart.write(2,measuring_short)  设置工作模式为短距离
-----------------------------------------------可选择测量模式---------------------------------------------------

--[[
    @id uart id
    @mode 可以是可选择模式中任意一个指令
]]
function GY_53L1.Set_Mode(id,mode)
    uart.write(id,mode)
end

--[[
    @ret -1 fail
]]
local function data_dispose(str)  
    recv_data.head1=string.byte(str,1)
    recv_data.head2=string.byte(str,2)
    recv_data.type=string.byte(str,3)
    recv_data.amount=string.byte(str,4)
    recv_data.hight=string.byte(str,5)
    recv_data.low=string.byte(str,6)
    recv_data.mode=string.byte(str,7)
    recv_data.check_sum=string.byte(str,8)

    if recv_data.head1 ~= 0x5A then
        log.info('帧头错误')
        return -1
    end
    --校验和计算
    local sum=recv_data.head1+recv_data.head2+recv_data.type+ recv_data.amount+recv_data.hight+recv_data.low+recv_data.mode
    sum=sum & 0xff
    if sum ==recv_data.check_sum then
        --输出距离值
        range=(recv_data.hight<<8)|recv_data.low
        log.info("距离:mm",range,"测量模式:",recv_data.mode & 0x03,"测量时间:",(recv_data.mode>>2) & 0x03)

    else
        log.info('校验错误')
        return -1
    end
end

--初始化uart
local function uart_init(id)
    -- 初始化
    local result = uart.setup(id, 9600, 8, 1)
    --设置工作模式
    -- 收取数据会触发回调, 这里的"receive" 是固定值
    uart.on(id, "receive", function(id, len)
        local s = ""
        repeat
            -- 如果是air302, len不可信, 传1024
            -- s = uart.read(id, 1024)
            s = uart.read(id, len)
            if #s > 0 then -- #s 是取字符串的长度
                -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
                -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
                --log.info("uart", "receive", id, #s, s)
                data_dispose(s)
            end
            if #s == len then
                break
            end
        until s == ""
    end)

end
--@id uart id
function  GY_53L1.setup(id)
    --初始化
    uart_init(id)    
end

return GY_53L1