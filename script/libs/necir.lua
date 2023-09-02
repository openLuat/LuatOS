--[[
@module necir
@summary necir NEC协议红外接收
@version 3.0
@date    2023.09.02
@author  lulipro
@usage
--注意:
--由于本库基于标准四线SPI接口实现，所以虽然只用到了MISO引脚，但是其他3个SPI相关引脚无法作为其他用途
--除非执行necir.close()后，中断引脚和SPI都将完全释放，可以用于其他用途
--实现了NEC红外数据接收，发送请使用LuatOS底层固件自带的ir.sendNEC()函数
--硬件模块：VS1838及其兼容的一体化接收头
--接线示意图：
--
--支持单IO模式，即仅使用一个SPI_MISO引脚，此时necir.init的irq_pin参数必须是SPI_MISO所在引脚
--  ____________________              ____________________
-- |                    |    单IO    |                    |
-- |           SPI_MISO |------------| OUT                |
-- | Air10x             |            |       VS1838       |
-- |                    |            |     一体化接收头    |
-- |                    |            |                    |
-- |____________________|            |____________________| 
--
--双IO模式，即单独用另一个IO做中断检测。单IO和双IO没有功能差异，具体如何选择取决于实际情况
-- ***一般情况下没必要用双IO模式***
--  ____________________              ____________________
-- |                    |    双IO    |                    |
-- |           SPI_MISO |------------| OUT                |
-- | Air10x             |   |        |       VS1838       |
-- |           IRQ_GPIO |---         |     一体化接收头    |
-- |                    |            |                    |
-- |____________________|            |____________________| 

--用法实例：
local necir = require("necir")

local function my_ir_cb(frameTab)
    log.info('get ir msg','addr=',frameTab[1],'data=',frameTab[3])
end

sys.taskInit(function()
    necir.init(spi.SPI_0,pin.PB03,my_ir_cb)

    while 1 do
        sys.wait(1000)
    end
end)

]]

local necir = {}

local sys = require "sys"

local NECIR_IRQ_PIN               --上升沿中断检测引脚
local NECIR_SPI_ID                --使用的SPI接口的ID
local NECIR_SPI_BAUDRATE       = (14222*4)           --SPI时钟频率，单位HZ
local NECIR_SPI_RECV_BUFF_LEN  = (32+192+192) + (2*4)--SPI接收数据的长度  

local recvBuff              --SPI接收数据缓冲区
local recvNECFrame={}       --依次存储：地址码，地址码取反，数据码，数据码取反

local recvCallback          --NEC报文接收成功后的用户回调函数
local isRecvTaskRun         --接收任务是否需要继续运行的标志

--[[
==============实现原理================================================
NEC协议中无论是引导信号，逻辑0还是逻辑1，都由若干个562.5us的周期组成。
例如
  引导信号: 16个562.5us的低电平+8个562.5us的高电平组成  
  逻 辑 1 ：1个562.5us的低电平+3个562.5us的高电平组成 
  逻 辑 0 ：1个562.5us的低电平+1个562.5us的高电平组成

采样定理告诉我们，一切数字信号，都可以通过高倍速采样还原。
我们使用SPI的MISO引脚对红外接收管的输出进行采样。
我们使用4个SPI字节去采样一个562.5us的红外信号周期，因此SPI的时钟频率设置为 (14222*4) Hz
则
  引导信号: 16*4个0x00 + 8*4个0xff组成
  逻 辑 1 ：1*4个0x00 + 3*4个0xff组成，共16字节
  逻 辑 0 ：1*4个0x00 + 1*4个0xff组成 ，共8字节

NEC的引导信号由一段低电平+一段高电平组成，为了降低采样深度，避免空间占用，我们选择从后面的高电平
产生的上升沿开始进行SPI接收采样。

确定采样深度。NEC协议中，地址码和数据码都是连续传输2次，连续的2个字节是相互取反的关系，
因此这2个字节的总的传输时间是固定，因为前一个字节的某个位是1，则必定后一个字节对应位是0，
则总传输时间就是 = （逻辑1传输时间+逻辑0传输时间）* 8，
则（地址码+ 地址码取反） 和 （数据码+数据码取反）的采样深度都是 (16+8)*8 = 192字节。
引导码高电平部分则是8*4字节，由于LuatOS中断响应存在一定延迟，我们还要继续多采样几个字节
才能保证采集完整个NEC报文，这里我选择多采样2*4个字节，即多采样2个562.5us的红外信号周期，
延迟1ms内都是可以接受的。这样我们就确定了SPI的总传输字节数= 32 + 192 + 192 + 2*4。
单次SPI采样耗时不到60ms。

重点来了，考虑到LuatOS中断响应存在一定延迟，导致SPI接收的信号与实际输出的信号存在一定的
滞后导致字节错位。因此对接收到的SPI字节数据 依次向后 采用16字节长度的窗口切出子串，
对这个子串进行模式匹配，来确定当前片段对应是NEC的逻辑1还是逻辑0。
即：
  在当前位置开始的后面的16个字节形成的子串中，如果存在连续的9个0xff，
  则认为当前位置是逻辑1，否则认为是逻辑0。
  为什什么是9个，考虑下面的情形：
        
逻辑1: 0x00 0x00 0x00 0x00  0xff 0xff 0xff 0xff ... 0xff 
       [     4  个       ]  [         12 个            ]
                           
逻辑0: 0x00 0x00 0x00 0x00  0xff 0xff 0xff 0xff  0x00 0x00 0x00 0x00 0xff 0xff 0xff 0xff
       [     4  个       ]  [       4 个      ]  [    下一个逻辑位（部分）               ]

可以发现，如果是逻辑0，则连续的16个字节窗口中最多出现4个连续的0xff，因此可以作为区分。
lua中的string.find()可以方便的实现字符串模式匹配，因此代码实现很简单。
]]


--从收到的SPI数据中解析出NEC报文
local function parseRecvData()
    local fs,fe
    local si

    --数据重新初始化
    recvNECFrame[1] = 0
    recvNECFrame[2] = 0
    recvNECFrame[3] = 0
    recvNECFrame[4] = 0

    --尝试找到第一个不是255出现的位置，用于跳过引导信号字节，这部分最多32字节
    si=28
    while si < 35 do
        if 255 ~= string.byte(string.sub(recvBuff,si,si)) then
            break
        end
        si = si + 1
    end
    
    --遍历整个收到的SPI数据进行NEC数据解析还原
    while si<NECIR_SPI_RECV_BUFF_LEN do

        for k = 1, 4, 1 do  --解析出NEC报文的4个字节
            for i = 0, 7, 1 do  --每个字节8位
                --在当前位置开始的后面的16个字节中，如果存在连续的9个0xff的值，
                --则认为当前位置是逻辑1
                fs,fe = string.find(
                    string.sub(recvBuff,si,si+16-1),
                    '\xff\xff\xff\xff\xff\xff\xff\xff\xff'
                )
                if fs and fe then --找到这种模式
                    --这个bit为1(NEC协议大小端为LSB First)
                    recvNECFrame[k] = (recvNECFrame[k] | (1<<i))
                    si = si + 16
                else  --没找到这种模式
                    --这个bit为0
                    si = si + 8
                end
            end  --每个字节8位
        end --解析出NEC报文的4个字节

        break  --成功解析出4个字节后跳出循环

    end --遍历整个收到的SPI数据

    --对收到的红外数据进行校验并调用 用户回调函数
    if (recvNECFrame[1]+recvNECFrame[2] == 255 ) and
        (recvNECFrame[3]+recvNECFrame[4] == 255) then
        --log.info('DataValid,go CallBack')
        if recvCallback then recvCallback(recvNECFrame) end
    end

    --log.info('necir',recvNECFrame[1],recvNECFrame[2],recvNECFrame[3],recvNECFrame[4])
end


--检测引导产生的上升沿的的中断函数
local function irq_func()
    gpio.close(NECIR_IRQ_PIN)  --关闭GPIO功能，防止中断反复触发
    spi.setup(NECIR_SPI_ID,nil,0,0,8,NECIR_SPI_BAUDRATE,spi.MSB,spi.master,1)--重新打开SPI接口

    recvBuff =  spi.recv(NECIR_SPI_ID, NECIR_SPI_RECV_BUFF_LEN) --通过SPI接收红外接收头输出的解调数据
    sys.publish('NECIR_SPI_DONE')  --发布消息，让任务对收到的SPI数据分析处理
end


local function recvTaskFunc()
    
    while isRecvTaskRun do
        
        spi.close(NECIR_SPI_ID)  --关闭SPI接口在，这样才能把MISO空出来做中断检测
        gpio.setup(NECIR_IRQ_PIN,irq_func,gpio.PULLUP ,gpio.RISING)--打开GPIO中断检测功能

        local result, _ = sys.waitUntil('NECIR_SPI_DONE',1000)
        if result then  --SPI完成采集，开始解析数据
            parseRecvData()
        end
        sys.wait(200)
    end

    --任务结束时做清理工作
    gpio.close(NECIR_IRQ_PIN)  --关闭GPIO功能
    spi.close(NECIR_SPI_ID)   --关闭SPI接口
    --log.info('necir recv task close')
end


--[[
necir初始化，开启数据接收任务
@api necir.init(spi_id,irq_pin,recv_cb)
@number spi_id,使用的SPI接口的ID
@number irq_pin,使用的中断引脚，这个引脚可以是SPI的MISO引脚（单IO模式）
@function recv_cb,红外数据接收完成后的回调函数，回调函数有1个table类型参数，分别存储了地址码，地址码取反，数据码，数据码取反
@usage
local function my_ir_cb(frameTab)
    log.info('get ir msg','addr=',frameTab[1],'data=',frameTab[3])
end

necir.init(spi.SPI_0,pin.PB03,my_ir_cb)
]]
function necir.init(spi_id,irq_pin,recv_cb)
    NECIR_SPI_ID     = spi_id
    NECIR_IRQ_PIN    = irq_pin
    recvCallback     = recv_cb

    --启动红外数据接收任务
    isRecvTaskRun      = true
    sys.taskInit(recvTaskFunc)
end

--[[
关闭necir数据接收过程。如需再次开启，则需要再次调用necir.init(spi_id,irq_pin,recv_cb)
@api necir.close()
@usage
necir.close()
]]
function necir.close()
    isRecvTaskRun = false
end


return necir