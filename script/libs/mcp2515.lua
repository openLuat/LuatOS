--[[
@module mcp2515
@summary mcp2515 CAN协议控制器驱动
@version 1.0
@date    2022.07.08
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local mcp2515 = require "mcp2515"

-- mcp2515    mcu
-- csk      spi_sck
-- si       spi_mosi
-- so       spi_miso
-- cs       spi_cs
-- int      gpio

sys.subscribe("mcp2515", function(len,buff,config)
    print("mcp2515", len,buff:byte(1,len))
    for k, v in pairs(config) do
        print(k,v)
    end
end)

sys.taskInit(function()
    local mcp2515_spi= 0
    local mcp2515_cs= pin.PB04
    local mcp2515_int= pin.PB01
    spi_mcp2515 = spi.setup(mcp2515_spi,nil,0,0,8,10*1000*1000,spi.MSB,1,0)
    mcp2515.init(mcp2515_spi,mcp2515_cs,mcp2515_int,mcp2515.CAN_500Kbps)

    mcp2515.send_buffer({id = 0x7FF,ide = false,rtr = false},0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07)--标准帧,数据帧
    mcp2515.send_buffer({id = 0x1FFFFFE6,ide = true,rtr = false},0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07)--扩展帧,数据帧
    mcp2515.send_buffer({id = 0x7FF,ide = false,rtr = true},0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07)--标准帧,远程帧
    mcp2515.send_buffer({id = 0x1FFFFFE6,ide = true,rtr = true},0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07)--扩展帧,远程帧

end)
]]

local mcp2515 = {}
local sys = require "sys"

-- SPI 指令集
mcp2515.RESET         =     0xC0
mcp2515.READ          =     0x03
mcp2515.RD_RX_BUFF    =     0x90
mcp2515.RD_RXB0SIDH   =     0x90
mcp2515.RD_RXB0D0     =     0x92
mcp2515.RD_RXB1SIDH   =     0x94
mcp2515.RD_RXB1D0     =     0x96
mcp2515.WRITE         =     0x02
mcp2515.LOAD_TX       =     0X40  
mcp2515.LOAD_TXB0SIDH =     0X40
mcp2515.LOAD_TXB0D0   =     0X41
mcp2515.LOAD_TXB1SIDH =     0X42
mcp2515.LOAD_TXB1D0   =     0X43
mcp2515.LOAD_TXB2SIDH =     0X44
mcp2515.LOAD_TXB2D0   =     0X45
mcp2515.RTS           =     0x80
mcp2515.RTS_TXB0      =     0x81
mcp2515.RTS_TXB1      =     0x82
mcp2515.RTS_TXB2      =     0x84
mcp2515.RD_STATUS     =     0xA0
mcp2515.RX_STATUS     =     0xB0
mcp2515.BIT_MODIFY    =     0x05  
-- Configuration Registers
mcp2515.CANSTAT         = 0x0E
mcp2515.CANCTRL         = 0x0F
mcp2515.BFPCTRL         = 0x0C
mcp2515.TEC             = 0x1C
mcp2515.REC             = 0x1D
mcp2515.CNF3            = 0x28
mcp2515.CNF2            = 0x29
mcp2515.CNF1            = 0x2A
mcp2515.CANINTE         = 0x2B
mcp2515.CANINTF         = 0x2C
mcp2515.EFLG            = 0x2D
mcp2515.TXRTSCTRL       = 0x0D
--  Recieve Filters
mcp2515.RXF0SIDH        = 0x00
mcp2515.RXF0SIDL        = 0x01
mcp2515.RXF0EID8        = 0x02
mcp2515.RXF0EID0        = 0x03
mcp2515.RXF1SIDH        = 0x04
mcp2515.RXF1SIDL        = 0x05
mcp2515.RXF1EID8        = 0x06
mcp2515.RXF1EID0        = 0x07
mcp2515.RXF2SIDH        = 0x08
mcp2515.RXF2SIDL        = 0x09
mcp2515.RXF2EID8        = 0x0A
mcp2515.RXF2EID0        = 0x0B
mcp2515.RXF3SIDH        = 0x10
mcp2515.RXF3SIDL        = 0x11
mcp2515.RXF3EID8        = 0x12
mcp2515.RXF3EID0        = 0x13
mcp2515.RXF4SIDH        = 0x14
mcp2515.RXF4SIDL        = 0x15
mcp2515.RXF4EID8        = 0x16
mcp2515.RXF4EID0        = 0x17
mcp2515.RXF5SIDH        = 0x18
mcp2515.RXF5SIDL        = 0x19
mcp2515.RXF5EID8        = 0x1A
mcp2515.RXF5EID0        = 0x1B
-- CNF1
mcp2515.SJW_1TQ         = 0x40
mcp2515.SJW_2TQ         = 0x80
mcp2515.SJW_3TQ         = 0x90
mcp2515.SJW_4TQ         = 0xC0
-- CNF2 
mcp2515.BTLMODE_CNF3    = 0x80
mcp2515.BTLMODE_PH1_IPT = 0x00
mcp2515.SMPL_3X         = 0x40
mcp2515.SMPL_1X         = 0x00
mcp2515.PHSEG1_8TQ      = 0x38
mcp2515.PHSEG1_7TQ      = 0x30
mcp2515.PHSEG1_6TQ      = 0x28
mcp2515.PHSEG1_5TQ      = 0x20
mcp2515.PHSEG1_4TQ      = 0x18
mcp2515.PHSEG1_3TQ      = 0x10
mcp2515.PHSEG1_2TQ      = 0x08
mcp2515.PHSEG1_1TQ      = 0x00
mcp2515.PRSEG_8TQ       = 0x07
mcp2515.PRSEG_7TQ       = 0x06
mcp2515.PRSEG_6TQ       = 0x05
mcp2515.PRSEG_5TQ       = 0x04
mcp2515.PRSEG_4TQ       = 0x03
mcp2515.PRSEG_3TQ       = 0x02
mcp2515.PRSEG_2TQ       = 0x01
mcp2515.PRSEG_1TQ       = 0x00
-- CNF3
mcp2515.PHSEG2_8TQ      = 0x07
mcp2515.PHSEG2_7TQ      = 0x06
mcp2515.PHSEG2_6TQ      = 0x05
mcp2515.PHSEG2_5TQ      = 0x04
mcp2515.PHSEG2_4TQ      = 0x03
mcp2515.PHSEG2_3TQ      = 0x02
mcp2515.PHSEG2_2TQ      = 0x01
mcp2515.PHSEG2_1TQ      = 0x00
mcp2515.SOF_ENABLED     = 0x80
mcp2515.WAKFIL_ENABLED  = 0x40
mcp2515.WAKFIL_DISABLED = 0x00
mcp2515.CAN_10Kbps    =   0x31
mcp2515.CAN_25Kbps	=   0x13
mcp2515.CAN_50Kbps	=   0x09
mcp2515.CAN_100Kbps	=   0x04
mcp2515.CAN_125Kbps	=   0x03
mcp2515.CAN_250Kbps	=   0x01
mcp2515.CAN_500Kbps   =   0x00
-- CANINTE
mcp2515.RX0IE_ENABLED   = 0x01
mcp2515.RX0IE_DISABLED  = 0x00
mcp2515.RX1IE_ENABLED   = 0x02
mcp2515.RX1IE_DISABLED  = 0x00
mcp2515.G_RXIE_ENABLED  = 0x03
mcp2515.G_RXIE_DISABLED = 0x00
mcp2515.TX0IE_ENABLED   = 0x04
mcp2515.TX0IE_DISABLED  = 0x00
mcp2515.TX1IE_ENABLED   = 0x08
mcp2515.TX2IE_DISABLED  = 0x00
mcp2515.TX2IE_ENABLED   = 0x10
mcp2515.TX2IE_DISABLED  = 0x00
mcp2515.G_TXIE_ENABLED  = 0x1C
mcp2515.G_TXIE_DISABLED = 0x00
mcp2515.ERRIE_ENABLED   = 0x20
mcp2515.ERRIE_DISABLED  = 0x00
mcp2515.WAKIE_ENABLED   = 0x40
mcp2515.WAKIE_DISABLED  = 0x00
mcp2515.IVRE_ENABLED    = 0x80
mcp2515.IVRE_DISABLED   = 0x00
-- CANINTF
mcp2515.RX0IF_SET       = 0x01
mcp2515.RX0IF_RESET     = 0x00
mcp2515.RX1IF_SET       = 0x02
mcp2515.RX1IF_RESET     = 0x00
mcp2515.TX0IF_SET       = 0x04
mcp2515.TX0IF_RESET     = 0x00
mcp2515.TX1IF_SET       = 0x08
mcp2515.TX2IF_RESET     = 0x00
mcp2515.TX2IF_SET       = 0x10
mcp2515.TX2IF_RESET     = 0x00
mcp2515.ERRIF_SET       = 0x20
mcp2515.ERRIF_RESET     = 0x00
mcp2515.WAKIF_SET       = 0x40
mcp2515.WAKIF_RESET     = 0x00
mcp2515.IVRF_SET        = 0x80
mcp2515.IVRF_RESET      = 0x00
-- CANCTRL 
mcp2515.REQOP_CONFIG    = 0x80--配置模式
mcp2515.REQOP_LISTEN    = 0x60--监听模式
mcp2515.REQOP_LOOPBACK  = 0x40--回环模式 测试用
mcp2515.REQOP_SLEEP     = 0x20--睡眠模式
mcp2515.REQOP_NORMAL    = 0x00--正常模式
mcp2515.ABORT           = 0x10
mcp2515.OSM_ENABLED     = 0x08
mcp2515.CLKOUT_ENABLED  = 0x04
mcp2515.CLKOUT_DISABLED = 0x00
mcp2515.CLKOUT_PRE_8    = 0x03
mcp2515.CLKOUT_PRE_4    = 0x02
mcp2515.CLKOUT_PRE_2    = 0x01
mcp2515.CLKOUT_PRE_1    = 0x00
-- RXBnCTRL
mcp2515.RXM_RCV_ALL     = 0x60
mcp2515.RXM_VALID_EXT   = 0x40
mcp2515.RXM_VALID_STD   = 0x20
mcp2515.RXM_VALID_ALL   = 0x00
mcp2515.RXRTR_REMOTE    = 0x08
mcp2515.RXRTR_NO_REMOTE = 0x00
mcp2515.BUKT_ROLLOVER   = 0x04
mcp2515.BUKT_NO_ROLLOVER =    0x00
mcp2515.FILHIT0_FLTR_1  = 0x01
mcp2515.FILHIT0_FLTR_0  = 0x00
mcp2515.FILHIT1_FLTR_5  = 0x05
mcp2515.FILHIT1_FLTR_4  = 0x04
mcp2515.FILHIT1_FLTR_3  = 0x03
mcp2515.FILHIT1_FLTR_2  = 0x02
mcp2515.FILHIT1_FLTR_1  = 0x01
mcp2515.FILHIT1_FLTR_0  = 0x00
-- TXBnCTRL
mcp2515.TXREQ_SET       = 0x08
mcp2515.TXREQ_CLEAR     = 0x00
mcp2515.TXP_HIGHEST     = 0x03
mcp2515.TXP_INTER_HIGH  = 0x02
mcp2515.TXP_INTER_LOW   = 0x01
mcp2515.TXP_LOWEST      = 0x00

mcp2515.DLC_0          =  0x00
mcp2515.DLC_1          =  0x01
mcp2515.DLC_2          =  0x02
mcp2515.DLC_3          =  0x03
mcp2515.DLC_4          =  0x04
mcp2515.DLC_5          =  0x05
mcp2515.DLC_6          =  0x06
mcp2515.DLC_7          =  0x07    
mcp2515.DLC_8          =  0x08
-- Receive Masks
mcp2515.RXM0SIDH        = 0x20
mcp2515.RXM0SIDL        = 0x21
mcp2515.RXM0EID8        = 0x22
mcp2515.RXM0EID0        = 0x23
mcp2515.RXM1SIDH        = 0x24
mcp2515.RXM1SIDL        = 0x25
mcp2515.RXM1EID8        = 0x26
mcp2515.RXM1EID0        = 0x27
-- Tx Buffer 0
mcp2515.TXB0CTRL        = 0x30
mcp2515.TXB0SIDH        = 0x31
mcp2515.TXB0SIDL        = 0x32
mcp2515.TXB0EID8        = 0x33
mcp2515.TXB0EID0        = 0x34
mcp2515.TXB0DLC         = 0x35
mcp2515.TXB0D0          = 0x36
mcp2515.TXB0D1          = 0x37
mcp2515.TXB0D2          = 0x38
mcp2515.TXB0D3          = 0x39
mcp2515.TXB0D4          = 0x3A
mcp2515.TXB0D5          = 0x3B
mcp2515.TXB0D6          = 0x3C
mcp2515.TXB0D7          = 0x3D
-- Tx Buffer 1
mcp2515.TXB1CTRL        = 0x40
mcp2515.TXB1SIDH        = 0x41
mcp2515.TXB1SIDL        = 0x42
mcp2515.TXB1EID8        = 0x43
mcp2515.TXB1EID0        = 0x44
mcp2515.TXB1DLC         = 0x45
mcp2515.TXB1D0          = 0x46
mcp2515.TXB1D1          = 0x47
mcp2515.TXB1D2          = 0x48
mcp2515.TXB1D3          = 0x49
mcp2515.TXB1D4          = 0x4A
mcp2515.TXB1D5          = 0x4B
mcp2515.TXB1D6          = 0x4C
mcp2515.TXB1D7          = 0x4D
-- Tx Buffer 2
mcp2515.TXB2CTRL        = 0x50
mcp2515.TXB2SIDH        = 0x51
mcp2515.TXB2SIDL        = 0x52
mcp2515.TXB2EID8        = 0x53
mcp2515.TXB2EID0        = 0x54
mcp2515.TXB2DLC         = 0x55
mcp2515.TXB2D0          = 0x56
mcp2515.TXB2D1          = 0x57
mcp2515.TXB2D2          = 0x58
mcp2515.TXB2D3          = 0x59
mcp2515.TXB2D4          = 0x5A
mcp2515.TXB2D5          = 0x5B
mcp2515.TXB2D6          = 0x5C
mcp2515.TXB2D7          = 0x5D
-- Rx Buffer 0
mcp2515.RXB0CTRL        = 0x60
mcp2515.RXB0SIDH        = 0x61
mcp2515.RXB0SIDL        = 0x62
mcp2515.RXB0EID8        = 0x63
mcp2515.RXB0EID0        = 0x64
mcp2515.RXB0DLC         = 0x65
mcp2515.RXB0D0          = 0x66
mcp2515.RXB0D1          = 0x67
mcp2515.RXB0D2          = 0x68
mcp2515.RXB0D3          = 0x69
mcp2515.RXB0D4          = 0x6A
mcp2515.RXB0D5          = 0x6B
mcp2515.RXB0D6          = 0x6C
mcp2515.RXB0D7          = 0x6D
-- Rx Buffer 1
mcp2515.RXB1CTRL        = 0x70
mcp2515.RXB1SIDH        = 0x71
mcp2515.RXB1SIDL        = 0x72
mcp2515.RXB1EID8        = 0x73
mcp2515.RXB1EID0        = 0x74
mcp2515.RXB1DLC         = 0x75
mcp2515.RXB1D0          = 0x76
mcp2515.RXB1D1          = 0x77
mcp2515.RXB1D2          = 0x78
mcp2515.RXB1D3          = 0x79
mcp2515.RXB1D4          = 0x7A
mcp2515.RXB1D5          = 0x7B
mcp2515.RXB1D6          = 0x7C
mcp2515.RXB1D7          = 0x7D


function mcp2515.write(addr,...)
    mcp2515.cs(0)
    spi.send(mcp2515.spi, string.char(mcp2515.WRITE,addr,...))
	mcp2515.cs(1)
end

function mcp2515.read(addr,len)
    mcp2515.cs(0)
    spi.send(mcp2515.spi, string.char(mcp2515.READ,addr))
    local val = spi.recv(mcp2515.spi,len or 1)
	mcp2515.cs(1)
    if val then
        return string.byte(val,1,len)
    end
end

--[[ 
mcp2515 复位
@api mcp2515.reset()
@usage
mcp2515.reset()
]]
function mcp2515.reset()
    mcp2515.cs(0)
    spi.send(mcp2515.spi, string.char(mcp2515.RESET))
	mcp2515.cs(1)
end

--[[ 
mcp2515 数据发送
@api mcp2515.send_buffer(config,...)
@table config 接收数据参数 id:报文ID ide:是否为扩展帧 rtr:是否为远程帧
@number ... 发送数据 数据个数不可大于8
@usage
mcp2515.send_buffer({id = 0x7FF,ide = false,rtr = false},0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07)--标准帧,数据帧
mcp2515.send_buffer({id = 0x1FFFFFE6,ide = true,rtr = false},0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07)--扩展帧,数据帧
mcp2515.send_buffer({id = 0x7FF,ide = false,rtr = true},0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07)--标准帧,远程帧
mcp2515.send_buffer({id = 0x1FFFFFE6,ide = true,rtr = true},0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07)--扩展帧,远程帧
]]
function mcp2515.send_buffer(config,...)
    if config.ide then
        mcp2515.write(mcp2515.TXB0SIDH,(config.id>>21)&0xFF)-- 发送缓冲器0标准标识符高位
        mcp2515.write(mcp2515.TXB0SIDL,((config.id>>16)&0x03)|0x08|((config.id>>13)&0xE0))-- 发送缓冲器0标准标识符低位与缓冲器0标拓展识符最高两位(第3位为发送拓展标识符使能位)
        mcp2515.write(mcp2515.TXB0EID8,(config.id>>8)&0xFF)-- 发送缓冲器0标拓展识符高位
        mcp2515.write(mcp2515.TXB0EID0,config.id&0xFF)-- 发送缓冲器0标拓展识符低位
    else
        mcp2515.write(mcp2515.TXB0SIDH,(config.id>>3)&0xFF)-- 发送缓冲器0标准标识符高位
        mcp2515.write(mcp2515.TXB0SIDL,(config.id&0x07)<<5)-- 发送缓冲器0标准标识符低位
    end
    if select("#",...)>8 then
        log.error("mcp2515","send_buffer")
        return
    end
    local delay = 0
    while mcp2515.read(mcp2515.TXB0CTRL)&0x08 ~=0 and delay<5 do
        sys.wait(10)
        delay = delay+1
    end
    mcp2515.write(mcp2515.TXB0D0,...)--将待发送的数据写入发送缓冲寄存器
    if config.rtr then
        mcp2515.write(mcp2515.TXB0DLC,select("#",...)|0x40)--将本帧待发送的数据长度写入发送缓冲器0的发送长度寄存器
    else
        mcp2515.write(mcp2515.TXB0DLC,select("#",...))--将本帧待发送的数据长度写入发送缓冲器0的发送长度寄存器
    end
    mcp2515.write(mcp2515.TXB0CTRL,0x08)--请求发送报文
end

--[[ 
mcp2515 数据接收
@api mcp2515.receive_buffer()
@return number len 接收数据长度
@return string buff 接收数据
@return table config 接收数据参数 id:报文ID ide:是否为扩展帧 rtr:是否为远程帧
@usage
sys.subscribe("mcp2515", function(len,buff,config)
    print("mcp2515", len,buff:byte(1,len))
    for k, v in pairs(config) do
        print(k,v)
    end
end)
]]
function mcp2515.receive_buffer()
    local config = {}
    local len
    local buff
    local temp = mcp2515.read(mcp2515.CANINTF)
    if temp & 0x01 ~= 0  then
        local sidh=mcp2515.read(mcp2515.RXB0SIDH)
        local sidl=mcp2515.read(mcp2515.RXB0SIDL)
        if sidl&0x08 ==0 then
            config.ide = false
            config.id = sidh<<3|sidl>>5
            if sidl&0x10 ==0 then
                config.rtr = false
            else
                config.rtr = true
            end
        else
            config.ide = true
            local eidh=mcp2515.read(mcp2515.RXB0EID8)
            local eidl=mcp2515.read(mcp2515.RXB0EID0)
            config.id = sidh<<21|(sidl&0xE0)<<13|(sidl&0x03)<<16|eidh<<8|eidl
        end
        local dlc=mcp2515.read(mcp2515.RXB0DLC)
        if config.ide then
            if dlc&0x40 == 0 then
                config.rtr = false
            else
                config.rtr = true
            end
        end
        len = dlc&0x0F
        buff = string.char(mcp2515.read(mcp2515.RXB0D0,len))
    end
    mcp2515.write(mcp2515.CANINTF,0)
    return len,buff,config
end

local function mcp2515_int(val)
    if val==0 then
        local len,buff,config = mcp2515.receive_buffer()
        if len then
            sys.publish("mcp2515", len,buff,config)
        end
    end
end

--[[
mcp2515 设置模式
@api mcp2515.mode(mode)
@number mode     模式
@usage
mcp2515.mode(mcp2515.REQOP_NORMAL)--进入正常模式
]]
function mcp2515.mode(mode)
    mcp2515.write(mcp2515.CANCTRL,mode|mcp2515.CLKOUT_ENABLED)
	local temp = mcp2515.read(mcp2515.CANSTAT)
    if mode ~= (temp&0xE0) then
        mcp2515.write(mcp2515.CANCTRL,mode|mcp2515.CLKOUT_ENABLED)
    end
end

--[[
mcp2515 设置波特率(注意:需在配置模式使用)
@api mcp2515.baud(baud)
@number baud     波特率
@usage
mcp2515.baud(mcp2515.CAN_500Kbps)
]]
function mcp2515.baud(baud)
    mcp2515.write(mcp2515.CNF1,baud)
end

--[[
mcp2515 设置过滤表(注意:需在配置模式使用)
@api mcp2515.filter(id,ide,shield)
@number id     id
@bool ide     是否为扩展帧
@bool shield     是否为屏蔽表
@usage
mcp2515.filter(0x1FF,false,false)
]]
function mcp2515.filter(id,ide,shield)
    mcp2515.mode(mcp2515.REQOP_CONFIG)--进入配置模式
    if ide then
        if shield then
            mcp2515.write(mcp2515.RXM0SIDH,(id>>21)&0xFF)--配置验收屏蔽寄存器n标准标识符高位
	        mcp2515.write(mcp2515.RXM0SIDL,((id>>16)&0x03)|((id>>13)&0xE0))--配置验收屏蔽寄存器n标准标识符低位
            mcp2515.write(mcp2515.RXM0EID8,(id>>8)&0xFF)--配置验收屏蔽寄存器n拓展标识符高位
	        mcp2515.write(mcp2515.RXM0EID0,id&0xFF)--配置验收屏蔽寄存器n拓展标识符低位
        else
            mcp2515.write(mcp2515.RXF0SIDH,(id>>21)&0xFF)--配置验收滤波寄存器n标准标识符高位
            mcp2515.write(mcp2515.RXF0SIDL,((id>>16)&0x03)|0x08|((id>>13)&0xE0))--配置验收滤波寄存器n标准标识符低位(第3位为接收拓展标识符使能位)
            mcp2515.write(mcp2515.RXF0EID8,(id>>8)&0xFF)--配置验收滤波寄存器n标准标识符高位
	        mcp2515.write(mcp2515.RXF0EID0,id&0xFF)--配置验收滤波寄存器n标准标识符低位
        end
    else
        if shield then
            mcp2515.write(mcp2515.RXM0SIDH,(id>>3)&0xFF)--配置验收屏蔽寄存器n标准标识符高位
	        mcp2515.write(mcp2515.RXM0SIDL,(id&0x07)<<5)--配置验收屏蔽寄存器n标准标识符低位
        else
            mcp2515.write(mcp2515.RXF0SIDH,(id>>3)&0xFF)--配置验收滤波寄存器n标准标识符高位
	        mcp2515.write(mcp2515.RXF0SIDL,(id&0x07)<<5)--配置验收滤波寄存器n标准标识符低位(第3位为接收拓展标识符使能位)
        end
    end
    mcp2515.mode(mcp2515.REQOP_NORMAL)--进入正常模式
end

--[[
mcp2515 初始化
@api mcp2515.init(spi_id,cs,int,baud)
@number spi_id spi端口号
@number cs      cs引脚
@number int     int引脚
@number baud     波特率
@return bool 初始化结果
@usage
spi_mcp2515 = spi.setup(mcp2515_spi,nil,0,0,8,20*1000*1000,spi.MSB,1,0)
mcp2515.init(mcp2515_spi,mcp2515_cs,mcp2515_int,mcp2515.CAN_500Kbps)
]]
function mcp2515.init(spi_id,cs,int,baud)
    mcp2515.spi = spi_id
    mcp2515.cs = gpio.setup(cs, 0, gpio.PULLUP) 
    mcp2515.cs(1)
    gpio.setup(int,mcp2515_int, gpio.PULLUP)
    mcp2515.reset()
    -- 以下部分根据需求参考手册修改
    -- 配置CNF1,CNF2,CNF3,
    mcp2515.baud(baud)
	mcp2515.write(mcp2515.CNF2,0x80|mcp2515.PHSEG1_3TQ|mcp2515.PRSEG_1TQ)
	mcp2515.write(mcp2515.CNF3,mcp2515.PHSEG2_3TQ)
	mcp2515.write(mcp2515.RXB0SIDH,0x00)--清空接收缓冲器0的标准标识符高位
	mcp2515.write(mcp2515.RXB0SIDL,0x00)--清空接收缓冲器0的标准标识符低位
    mcp2515.write(mcp2515.RXB0EID8,0x00)--清空接收缓冲器0的拓展标识符高位
	mcp2515.write(mcp2515.RXB0EID0,0x00)--清空接收缓冲器0的拓展标识符低位
	mcp2515.write(mcp2515.CANINTF,0x00)--清空CAN中断标志寄存器的所有位(必须由MCU清空)
	mcp2515.write(mcp2515.CANINTE,0x01)--配置CAN中断使能寄存器的接收缓冲器0满中断使能,其它位禁止中断
    mcp2515.mode(mcp2515.REQOP_NORMAL)--进入正常模式
    return true
end

return mcp2515
