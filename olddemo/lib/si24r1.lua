--[[
@module si24r1
@summary si24r1 驱动
@version 1.0
@date    2022.06.17
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local si24r1 = require "si24r1"

sys.taskInit(function()
    spi_si24r1 = spi.setup(0,nil,0,0,8,10*1000*1000,spi.MSB,1,1)
    si24r1.init(0,pin.PB04,pin.PB01,pin.PB00)
    if si24r1.chip_check() then
        si24r1.set()
    end

    --发送示例
    -- si24r1.set_mode( si24r1.MODE_TX );		--发送模式	
    -- while 1 do
    --     sys.wait(1000)
    --     local a = si24r1.txpacket("si24r1test")
    --     print("a",a)
    -- end

    --接收示例 
    si24r1.set_mode( si24r1.MODE_RX );		--接收模式	
    while 1 do
        local i,data = si24r1.rxpacket( );		--接收字节
        print("rxbuf",i,data)
    end
end)
]]


local si24r1 = {}
local sys = require "sys"

local si24r1_device
local si24r1_spi
local si24r1_ce
local si24r1_cs
local si24r1_irq

local si24r1_cspin,si24r1_cepin,si24r1_irqpin

local LM75_ADDRESS_ADR         =   0x48

---器件所用地址
local    REPEAT_CNT          =  15		--重复次数
local    INIT_ADDR           =  string.char(0x34,0x43,0x10,0x10,0x01)

si24r1.MODE_TX = 0
si24r1.MODE_RX = 1

local    NRF_READ_REG       =   0x00	--读配置寄存器，低5位为寄存器地址
local    NRF_WRITE_REG      =   0x20	--写配置寄存器，低5位为寄存器地址
local    RD_RX_PLOAD        =   0x61	--读RX有效数据，1~32字节
local    WR_TX_PLOAD        =   0xA0	--写TX有效数据，1~32字节
local    FLUSH_TX           =   0xE1	--清除TX FIFO寄存器，发射模式下使用
local    FLUSH_RX           =   0xE2	--清除RX FIFO寄存器，接收模式下使用
local    REUSE_TX_PL        =   0xE3	--重新使用上一包数据，CE为高，数据包被不断发送
local    R_RX_PL_WID        =   0x60
local    NOP                =   0xFF	--空操作，可以用来读状态寄存器
local    W_ACK_PLOAD	    =   0xA8
local    WR_TX_PLOAD_NACK   =   0xB0

local    CONFIG             =   0x00	--配置寄存器地址，bit0:1接收模式,0发射模式;bit1:电选择;bit2:CRC模式;bit3:CRC使能;
                                        --bit4:中断MAX_RT(达到最大重发次数中断)使能;bit5:中断TX_DS使能;bit6:中断RX_DR使能	
local    EN_AA              =   0x01	--使能自动应答功能 bit0~5 对应通道0~5
local    EN_RXADDR          =   0x02	--接收地址允许 bit0~5 对应通道0~5
local    SETUP_AW           =   0x03	--设置地址宽度(所有数据通道) bit0~1: 00,3字节 01,4字节, 02,5字节
local    SETUP_RETR         =   0x04	--建立自动重发;bit0~3:自动重发计数器;bit4~7:自动重发延时 250*x+86us
local    RF_CH              =   0x05	--RF通道,bit0~6工作通道频率
local    RF_SETUP           =   0x06	--RF寄存器，bit3:传输速率( 0:1M 1:2M);bit1~2:发射功率;bit0:噪声放大器增益
local    STATUS             =   0x07	--状态寄存器;bit0:TX FIFO满标志;bit1~3:接收数据通道号(最大:6);bit4:达到最多次重发次数
                                        --bit5:数据发送完成中断;bit6:接收数据中断
local    MAX_TX  		    =   0x10	--达到最大发送次数中断
local    TX_OK   		    =   0x20	--TX发送完成中断
local    RX_OK   		    =   0x40	--接收到数据中断

local    OBSERVE_TX         =   0x08	--发送检测寄存器,bit7~4:数据包丢失计数器;bit3~0:重发计数器
local    CD                 =   0x09	--载波检测寄存器,bit0:载波检测
local    RX_ADDR_P0         =   0x0A	--数据通道0接收地址，最大长度5个字节，低字节在前
local    RX_ADDR_P1         =   0x0B	--数据通道1接收地址，最大长度5个字节，低字节在前
local    RX_ADDR_P2         =   0x0C	--数据通道2接收地址，最低字节可设置，高字节，必须同RX_ADDR_P1[39:8]相等
local    RX_ADDR_P3         =   0x0D	--数据通道3接收地址，最低字节可设置，高字节，必须同RX_ADDR_P1[39:8]相等
local    RX_ADDR_P4         =   0x0E	--数据通道4接收地址，最低字节可设置，高字节，必须同RX_ADDR_P1[39:8]相等
local    RX_ADDR_P5         =   0x0F	--数据通道5接收地址，最低字节可设置，高字节，必须同RX_ADDR_P1[39:8]相等
local    TX_ADDR            =   0x10	--发送地址(低字节在前),ShockBurstTM模式下，RX_ADDR_P0与地址相等
local    RX_PW_P0           =   0x11	--接收数据通道0有效数据宽度(1~32字节),设置为0则非法
local    RX_PW_P1           =   0x12	--接收数据通道1有效数据宽度(1~32字节),设置为0则非法
local    RX_PW_P2           =   0x13	--接收数据通道2有效数据宽度(1~32字节),设置为0则非法
local    RX_PW_P3           =   0x14	--接收数据通道3有效数据宽度(1~32字节),设置为0则非法
local    RX_PW_P4           =   0x15	--接收数据通道4有效数据宽度(1~32字节),设置为0则非法
local    RX_PW_P5           =   0x16	--接收数据通道5有效数据宽度(1~32字节),设置为0则非法
local    NRF_FIFO_STATUS    =   0x17	--FIFO状态寄存器;bit0:RX FIFO寄存器空标志;bit1:RX FIFO满标志;bit2~3保留
                                        --bit4:TX FIFO 空标志;bit5:TX FIFO满标志;bit6:1,循环发送上一数据包.0,不循环								
local    DYNPD			    =   0x1C
local    FEATRUE			=   0x1D

local    MASK_RX_DR   	    =   6 
local    MASK_TX_DS   	    =   5 
local    MASK_MAX_RT  	    =   4 
local    EN_CRC       	    =   3 
local    CRCO         	    =   2 
local    PWR_UP       	    =   1 
local    PRIM_RX      	    =   0 

local    ENAA_P5      	    =   5 
local    ENAA_P4      	    =   4 
local    ENAA_P3      	    =   3 
local    ENAA_P2      	    =   2 
local    ENAA_P1      	    =   1 
local    ENAA_P0      	    =   0 

local    ERX_P5       	    =   5 
local    ERX_P4       	    =   4 
local    ERX_P3       	    =   3 
local    ERX_P2      	    =   2 
local    ERX_P1       	    =   1 
local    ERX_P0       	    =   0 

local    AW_RERSERVED 	    =   0x0 
local    AW_3BYTES    	    =   0x1
local    AW_4BYTES    	    =   0x2
local    AW_5BYTES    	    =   0x3

local    ARD_250US    	    =   (0x00<<4)
local    ARD_500US    	    =   (0x01<<4)
local    ARD_750US    	    =   (0x02<<4)
local    ARD_1000US   	    =   (0x03<<4)
local    ARD_2000US   	    =   (0x07<<4)
local    ARD_4000US   	    =   (0x0F<<4)
local    ARC_DISABLE   	    =   0x00
local    ARC_15        	    =   0x0F

local    CONT_WAVE     	    =   7 
local    RF_DR_LOW     	    =   5 
local    PLL_LOCK      	    =   4 
local    RF_DR_HIGH    	    =   3 
-- bit2-bit1:
local    PWR_18DB  		    =   (0x00<<1)
local    PWR_12DB  		    =   (0x01<<1)
local    PWR_6DB   		    =   (0x02<<1)
local    PWR_0DB   		    =   (0x03<<1)

local    RX_DR         	    =   6 
local    TX_DS         	    =   5 
local    MAX_RT        	    =   4 
-- for bit3-bit1, 
local    TX_FULL_0     	    =   0 

local    RPD           	    =   0 

local    TX_REUSE      	    =   6 
local    TX_FULL_1     	    =   5 
local    TX_EMPTY      	    =   4 
-- bit3-bit2, reserved, only '00'
local    RX_FULL       	    =   1 
local    RX_EMPTY      	    =   0 

local    DPL_P5        	    =   5 
local    DPL_P4        	    =   4 
local    DPL_P3        	    =   3 
local    DPL_P2        	    =   2 
local    DPL_P1        	    =   1 
local    DPL_P0        	    =   0 

local    EN_DPL        	    =   2 
local    EN_ACK_PAY    	    =   1 
local    EN_DYN_ACK    	    =   0 
local    IRQ_ALL            =   ( (1<<RX_DR) | (1<<TX_DS) | (1<<MAX_RT) )

local check_string = string.char(0X11, 0X22, 0X33, 0X44, 0X55)

local function write_reg(address, value)
    si24r1_cs(0)
    if value then
        spi.send(si24r1_spi,string.char(NRF_WRITE_REG|address).. value)
    else
        spi.send(si24r1_spi,string.char(NRF_WRITE_REG|address))
    end
    si24r1_cs(1)
end

local function read_reg(address,len)
    si24r1_cs(0)
    spi.send(si24r1_spi, string.char(NRF_READ_REG|address))
    local val = spi.recv(si24r1_spi,len or 1)
    si24r1_cs(1)
    return val
end

--[[
si24r1 器件检测
@api si24r1.chip_check()
@return bool   成功返回true
@usage
if si24r1.chip_check() then
    si24r1.set()
end
]]
function si24r1.chip_check()
    write_reg(TX_ADDR, check_string)
    local recv_string = read_reg(TX_ADDR,5)
    if recv_string == check_string then
        return true
    end
    log.info("si24r1","Can't find si24r1 device")
    return false
end

local function read_status_register()
    return read_reg(NRF_READ_REG + STATUS);
end

local function clear_iqr_flag(IRQ_Source)
    local btmp = 0;
    IRQ_Source = IRQ_Source & ( 1 << RX_DR ) | ( 1 << TX_DS ) | ( 1 << MAX_RT );	--中断标志处理
    btmp = read_status_register():byte(1);			--读状态寄存器
    write_reg(NRF_WRITE_REG + STATUS)
    write_reg(IRQ_Source | btmp)
    return ( read_status_register():byte(1))			--返回状态寄存器状态
end

local function set_txaddr( pAddr )
    write_reg( TX_ADDR, pAddr)	--写地址
end

local function set_rxaddr( PipeNum,pAddr )
    write_reg( RX_ADDR_P0 + PipeNum, pAddr)	--写地址
end

--[[
si24r1 设置模式
@api si24r1.set_mode( Mode )
@number Mode si24r1.MODE_TX si24r1.MODE_RX
@usage
si24r1.set_mode( si24r1.MODE_TX )
]]
function si24r1.set_mode( Mode )
    local controlreg = 0;
	controlreg = read_reg( CONFIG ):byte(1);
    if ( Mode == si24r1.MODE_TX ) then       
		controlreg =controlreg & ~( 1<< PRIM_RX );
    elseif ( Mode == si24r1.MODE_RX ) then 
		controlreg = controlreg|( 1<< PRIM_RX ); 
	end
    write_reg( CONFIG, string.char(controlreg) );
end

--[[
si24r1 发送
@api si24r1.txpacket(buff)
@string buff 
@return number 0x20:发送成功 0x10:达到最大发送次数中断 0xff:发送失败
@usage
local a = si24r1.txpacket("si24r1test")
]]
function si24r1.txpacket(buff)
    local l_Status = 0
    local l_RxLength = 0
    local l_10MsTimes = 0
    
    spi.send(si24r1_spi,string.char(FLUSH_TX))
    si24r1_ce(0)
    write_reg(WR_TX_PLOAD, buff)
    si24r1_ce(1)

	while( 0 ~= si24r1_irq())do
		sys.wait(10)
        if( 50 == l_10MsTimes )then		
            si24r1.init(si24r1_spi,si24r1_cspin,si24r1_cepin,si24r1_irqpin)
            si24r1.set()
			si24r1.set_mode( si24r1.MODE_TX )
			break;
        end
        l_10MsTimes = l_10MsTimes+1
	end
    l_Status = read_reg( STATUS )		--读状态寄存器
	write_reg( STATUS,l_Status )		--清中断标志

	if( l_Status:byte(1) & MAX_TX )~=0then	--接收到数据
		write_reg( FLUSH_TX,string.char(0xff) )				--清除TX FIFO
		return MAX_TX
    end

    if( l_Status:byte(1) & TX_OK ~=0 )~=0then	--接收到数据
		return TX_OK
    end
	return 0xFF
end

--[[
si24r1 接收
@api si24r1.rxpacket()
@return number len,buff 长度 数据
@usage
local i,data = si24r1.rxpacket()		--接收字节
print("rxbuf",i,data)
]]
function si24r1.rxpacket()
	local l_Status = 0
    local l_RxLength = 0
    local l_100MsTimes = 0

    spi.send(si24r1_spi,string.char(FLUSH_RX))
	
	while( 0 ~= si24r1_irq())do
		sys.wait( 100 )
		if( 30 == l_100MsTimes )then		--3s没接收过数据，重新初始化模块
            si24r1.init(si24r1_spi,si24r1_cspin,si24r1_cepin,si24r1_irqpin)
            si24r1.set()
			si24r1.set_mode( si24r1.MODE_RX )
			break;
        end
        l_100MsTimes = l_100MsTimes+1
	end
	l_Status = read_reg( STATUS )		--读状态寄存器
	write_reg( STATUS,l_Status )		--清中断标志
	if( l_Status:byte(1) & RX_OK ~=0 )~=0then	--接收到数据
		l_RxLength = read_reg( R_RX_PL_WID )		--读取接收到的数据个数
		local rxbuf = read_reg( RD_RX_PLOAD,l_RxLength:byte(1) )	--接收到数据 
		write_reg( FLUSH_RX,string.char(0xff) )				--清除RX FIFO
		return l_RxLength:byte(1),rxbuf
    end
	return 0;				--没有收到数据	
end

--[[
si24r1 配置参数
@api si24r1.set()
@usage
si24r1.set()
]]
function si24r1.set()
    si24r1_ce(1)
    clear_iqr_flag(IRQ_ALL)

    write_reg( DYNPD, string.char( 1 << 0 ) )	--使能通道1动态数据长度
    write_reg( FEATRUE, string.char(0x07) )
    write_reg( DYNPD )
    write_reg( FEATRUE )

    write_reg( CONFIG,string.char(( 1 << EN_CRC ) |   ( 1 << PWR_UP )) )
    write_reg( EN_AA, string.char( 1 << ENAA_P0 ) )   		--通道0自动应答
    write_reg( EN_RXADDR, string.char( 1 << ERX_P0 ) )		--通道0接收
    write_reg( SETUP_AW, string.char(AW_5BYTES) )     			--地址宽度 5个字节
    write_reg( SETUP_RETR, string.char(ARD_4000US | ( REPEAT_CNT & 0x0F )) )         	--重复等待时间 250us
    write_reg( RF_CH, string.char(60) )             			--初始化通道
    write_reg( RF_SETUP, string.char(0x26) )

    set_txaddr( INIT_ADDR)                      --设置TX地址
    set_rxaddr( 0, INIT_ADDR)                   --设置RX地址
end

--[[
si24r1 初始化
@api si24r1.init(spi_id,cs,ce,irq)
@number spi_id spi_id
@return bool   成功返回true
@usage
lm75_data.init(0)
]]
function si24r1.init(spi_id,cs,ce,irq)
    -- si24r1_device = spi_device
    si24r1_spi = spi_id
    si24r1_cspin = cs
    si24r1_cepin = ce
    si24r1_irqpin = irq

    si24r1_cs = gpio.setup(si24r1_cspin, 0, gpio.PULLUP) 
    si24r1_cs(1)
    si24r1_irq= gpio.setup(si24r1_irqpin, nil,gpio.PULLUP)
    si24r1_ce= gpio.setup(si24r1_cepin, 0)
    si24r1_ce(0)
end

return si24r1


