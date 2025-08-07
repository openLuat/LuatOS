--[[
@module necir
@summary necir NEC协议红外接收
@version 3.5
@date    2023.09.03
@author  lulipro
@usage
--注意:
--1、本库在Air101和Air103测试通过，Air105由于SPI传输帧与帧之间存在间隔因此暂不支持。
--2、本库实现了NEC红外数据接收，发送请使用LuatOS底层固件自带的ir.sendNEC()函数。
--3、由于本库基于标准四线SPI接口实现，所以虽然只用到了MISO引脚，但是其他3个SPI相关引脚在使用期间
--  无法作为其他用途，除非执行necir.close()并等待necir.isClosed()为true后，SPI将完全释放，才可以用于其他用途。
--硬件模块：VS1838及其兼容的一体化接收头
--接线示意图：
--1、支持单IO模式，即仅使用一个SPI_MISO引脚，此时necir.init的irq_pin参数必须是SPI_MISO所在引脚。
--2、支持多从机，如果SPI总线上需要挂接其他从设备，为了在不使用红外通信期间，避免VS1838干扰总线的MISO，则可以用
--  一个NMOS（例如AO3400）控制VS1838的电源地，如下所示，GPIO充当VS1838的片选信号，当GPIO输出低
--  则禁用VS1838，此时VS1838不工作，其OUT引脚为高阻，不会干扰MISO；当GPIO输出高，则启用VS1838，
--  此时其OUT引脚会输出红外通信信号到单片机。由于一般的SPI从机片选逻辑为低使能，因此这样可以用
--  同一个片选GPIO来控制VS1838以及另一个SPI从机，因为片选逻辑是相反的。配合necir库的necir.close()
--  和necir.isClosed()可以最大化的复用SPI接口，避免SPI的独占而浪费。
--  ____________________                ____________________
-- |                    |    单IO      |                    |
-- |           SPI_MISO |--------------| OUT                |
-- | Air10x             |              |       VS1838       |
-- |                    |              |     一体化接收头    |
-- |               GPIO |----      ----| GND                |
-- |____________________|   |      |   |____________________| 
--                          |      |
--                          |  ____|________ 
--                          | |    D        |
--                          --| G      NMOS | 
--                            |____S________|
--                                 |
--                                GND
--用法实例：演示用同一个SPI接口驱动VS1838和W25QXX
--用法实例：
local necir = require("necir")

--定义用户回调函数
local function my_ir_cb(frameTab)
    log.info('get ir msg','addr=',frameTab[1],frameTab[2],'data=',frameTab[3])
end

sys.taskInit(function()
    local CS = gpio.setup(pin.PA07,0)  --VS1838(NMOS控制其GND)与W25QXX共用的片选引脚
    necir.init(spi.SPI_0,pin.PB03,my_ir_cb)

    while 1 do
        --===============================
        log.info('------necir start------')
        CS(1)     --使能VS1838
        necir.start()  --开启necir数据接收过程
        sys.wait(10000)
        log.info('necir request to close')
        necir.close()   --请求关闭necir
        while not (necir.isClosed()) do
            sys.wait(200)
        end
        CS(0)    --除能VS1838
        log.info('necir closed')
        sys.wait(1000)

        --===============================
        log.info('------setup to read w25qxx chip id------')
        spi.setup(spi.SPI_0,nil,
            0,--CPHA
            0,--CPOL
            8,--数据宽度
            100000,--频率
            spi.MSB,--高低位顺序  
            spi.master,--主模式
            spi.full--全双工
        )
        --读取W25QXX chi id，0XEF15,表示芯片型号为W25Q32，0XEF16,表示芯片型号为W25Q64
        CS(0)   --片选W25QXX
        spi.send(spi.SPI_0,string.char(0x90)..string.char(0x00)..string.char(0x00)..string.char(0x00))
        local chip_id = spi.recv(spi.SPI_0,2)
        log.info('w25qxx id=',chip_id:toHex())
        CS(1)   --取消片选W25QXX
        sys.wait(1000)
    end
end)
]]

local necir = {}

local sys = require "sys"

local NECIR_IRQ_PIN               --上升沿中断检测引脚
local NECIR_SPI_ID                --使用的SPI接口的ID
local NECIR_SPI_BAUDRATE       = (14222*4)        --SPI时钟频率，单位HZ
local NECIR_SPI_RECV_BUFF_LEN  = (32+192+192)     --SPI接收数据的长度  

local recvBuff              --SPI接收数据缓冲区
local recvNECFrame={}       --依次存储：地址码，地址码取反，数据码，数据码取反

local recvCallback          --NEC报文接收成功后的用户回调函数
local isNeedTaskFlag        --接收任务是否需要运行的标志
local isClosedFlag          --necir是否已经完全关闭的标志
--[[
==============实现原理================================================
NEC协议中无论是引导信号，逻辑0还是逻辑1，都由若干个562.5us的周期组成。
例如
  引导信号: 16个562.5us的低电平+8个562.5us的高电平组成  
  逻 辑 1 ：1个562.5us的低电平+3个562.5us的高电平组成 
  逻 辑 0 ：1个562.5us的低电平+1个562.5us的高电平组成

采样定理告诉我们，一切数字信号，都可以通过高倍速采样还原。
我们使用SPI的MISO引脚对红外接收管的输出进行【连续采样】。
我们使用4个SPI字节去采样一个562.5us的红外信号周期，因此SPI的时钟频率设置为 (14222*4) Hz
则
  引导信号: 16*4个0x00 + 8*4个0xff组成
  逻 辑 1 ：1*4个0x00 + 3*4个0xff组成，共16字节
  逻 辑 0 ：1*4个0x00 + 1*4个0xff组成 ，共8字节

NEC的引导信号由一段低电平+一段高电平组成，为了降低采样深度，避免空间占用，我们选择
从后面的高电平产生的上升沿开始进行SPI接收采样 而不是从第一个下降沿就开始。

确定采样深度。NEC协议中，地址码和数据码都是连续传输2次，连续的2个字节是相互取反的关系，
因此这2个字节的总的传输时间是固定，因为前一个字节的某个位是1，则必定后一个字节对应位是0，
则总传输时间就是 = （逻辑1传输时间+逻辑0传输时间）* 8，
则（地址码+ 地址码取反） 和 （数据码+数据码取反）的采样深度都是 (16+8)*8 = 192字节。
引导码高电平部分则是8*4字节。这样我们就确定了SPI的总传输字节数= 32 + 192 + 192=416字节。

理想情况下中断检测到引导码产生的上升沿就会立刻开始SPI数据采集，这样SPI传输 416 字节
能刚好采集引导码的4.5ms高电平加后面的4字节数据，但由于LuatOS中断响应存在一定延迟，导致真正开始
SPI采集会在引导码上升沿开始后的若干个毫秒延迟后才开始，经过测试一般延迟在1ms以内，但具体延迟取决于
LuatOS的行为，只要这个延迟能让SPI采集到完整的引导码后面的4字节数据就都是可以接受的，即延迟不能超过
4.5ms，一般这个情况是能满足的。

本方法需要的SPI频率为56888Hz，而Air101和Air103的SPI频率 = 40MHz/(2*(div_REG+1))，
则div_REG = 350即可实现。如果芯片的SPI无法配置频率也将不支持此方案。

考虑到LuatOS中断响应存在一定延迟，导致SPI接收的信号与实际输出的信号存在一定的
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

    --尝试找到第一个不是0xff出现的位置，用于跳过引导信号字节，这部分最多32字节
    si=1
    while si <= 32+5 do
        if 0xff ~= string.byte(string.sub(recvBuff,si,si)) then
            break
        end
        si = si + 1
    end
    
    --32+5个0xff后依然没有出现地址数据，属于不正常的信号，直接退出
    if 0xff == string.byte(string.sub(recvBuff,si,si)) then
        return
    end

    --遍历引导信号后续的信号，整个收到的SPI数据进行NEC数据解析还原
    while si<=NECIR_SPI_RECV_BUFF_LEN do

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
    --有的遥控的2个地址字节不是相互取反的关系，因此这里不对地址码校验
    if ((recvNECFrame[3]+recvNECFrame[4]) == 255) then
        --log.info('necir','DataValid,go CallBack')
        if recvCallback then recvCallback(recvNECFrame) end
    end
    --log.info('necir',recvNECFrame[1],recvNECFrame[2],recvNECFrame[3],recvNECFrame[4])
end


--检测引导产生的上升沿的的中断函数
local function irq_func()    
    gpio.close(NECIR_IRQ_PIN)  --关闭GPIO功能，防止中断反复触发
    spi.setup(NECIR_SPI_ID,nil,0,0,8,NECIR_SPI_BAUDRATE,spi.MSB,spi.master,spi.full)--重新打开SPI接口
    
    recvBuff =  spi.recv(NECIR_SPI_ID, NECIR_SPI_RECV_BUFF_LEN) --通过SPI接收红外接收头输出的解调数据
    sys.publish('NECIR_SPI_DONE')  --发布消息，让任务对收到的SPI数据分析处理
end


local function recvTaskFunc()

    while true do
        sys.waitUntil('NECIR_START',5000)

        while isNeedTaskFlag do
            spi.close(NECIR_SPI_ID)  --关闭SPI接口在，这样才能把MISO空出来做中断检测
            gpio.setup(NECIR_IRQ_PIN,irq_func,gpio.PULLUP ,gpio.RISING)--打开GPIO中断检测功能
    
            local result, _ = sys.waitUntil('NECIR_SPI_DONE',1000)
            if result then  --SPI完成采集，开始解析数据
                parseRecvData()
            end
        end
        --关闭接收过程时做清理工作
        if not isClosedFlag then
            gpio.close(NECIR_IRQ_PIN)  --关闭GPIO功能
            spi.close(NECIR_SPI_ID)   --关闭SPI接口
            isClosedFlag = true
            --log.info('necir','recv task closed')
        end
    end --task main loop
end

--[[
necir初始化
@api necir.init(spi_id,irq_pin,recv_cb)
@number spi_id,使用的SPI接口的ID
@number irq_pin,使用的中断引脚，在单IO模式下这个引脚必须是SPI的MISO引脚
@function recv_cb,红外数据接收完成后的回调函数，回调函数有1个table类型参数，分别存储了地址码，地址码取反，数据码，数据码取反
@usage
local function my_ir_cb(frameTab)
    log.info('get ir msg','addr=',frameTab[1],frameTab[2],'data=',frameTab[3])
end

necir.init(spi.SPI_0,pin.PB03,my_ir_cb)
]]
function necir.init(spi_id,irq_pin,recv_cb)
    NECIR_SPI_ID     = spi_id
    NECIR_IRQ_PIN    = irq_pin
    recvCallback     = recv_cb

    isNeedTaskFlag = false      --接收任务是否需要运行的标志
    isClosedFlag   = true       --necir是否已经完全关闭的标志
    --启动红外数据接收任务
    sys.taskInit(recvTaskFunc)
end

--[[
开启necir数据接收过程
@api necir.start()
@usage
necir.start()
]]
function necir.start()
    isNeedTaskFlag     = true
    isClosedFlag       = false
    sys.publish('NECIR_START')
end

--[[
请求关闭necir数据接收过程。此函数执行后并不能保证立刻关闭，具体是否已经关闭需要使用necir.isClosed()来查询。
@api necir.close()
@usage
necir.close()
]]
function necir.close()
    isNeedTaskFlag = false
end

--[[
判断necir是否已经完全关闭，关闭后所使用的SPI接口将释放，可以复用为其他功能。如需再次开启，则需要再次调用necir.start()
@api necir.isClosed()
@return bool   关闭成功返回true
@usage
necir.isClosed()
]]
function necir.isClosed()
    return isClosedFlag
end

return necir