local FM17622 = {}

local sys = require "sys"

local FM17622_iic_id, FM17622_iic_addr, FM17622_NPD,debug
local endcall
local nfc_Data = {}

local nfc_work=false--防冲突

-- LPCD配置信息
LPCD_THRSH_H = 0x00
LPCD_THRSH_L = 0x10
LPCD_CWP = 10 -- LPCD PMOS输出驱动 0~63
LPCD_CWN = 10 -- LPCD NMOS输出驱动 0~15
LPCD_SLEEPTIME = 10 -- LPCD 唤醒间隔时间，每一档为32ms，休眠时间：(16+1)*32=544ms

TX1_TX2_CW_DISABLE = 0
TX1_CW_ENABLE = 1
TX2_CW_ENABLE = 2
TX1_TX2_CW_ENABLE = 3

JREG_PAGE0 = 0x00 -- Page register in page 0
JREG_COMMAND = 0x01 -- Contains Command bits, PowerDown bit and bit to switch receiver off.
JREG_COMMIEN = 0x02 -- Contains Communication interrupt enable bits andbit for Interrupt inversion.
JREG_DIVIEN = 0x03 -- Contains RfOn, RfOff, CRC and Mode Interrupt enable and bit to switch Interrupt pin to PushPull mode.
JREG_COMMIRQ = 0x04 -- Contains Communication interrupt request bits.
JREG_DIVIRQ = 0x05 -- Contains RfOn, RfOff, CRC and Mode Interrupt request.
JREG_ERROR = 0x06 -- Contains Protocol, Parity, CRC, Collision, Buffer overflow, Temperature and RF error flags.
JREG_STATUS1 = 0x07 -- Contains status information about Lo- and HiAlert, RF-field on, Timer, Interrupt request and CRC status.
JREG_STATUS2 = 0x08 -- Contains information about internal states (Modemstate),Mifare states and possibility to switch Temperature sensor off.
JREG_FIFODATA = 0x09 -- Gives access to FIFO. Writing to register increments theFIFO level (register =0x0A), reading decrements it.
JREG_FIFOLEVEL = 0x0A -- Contains the actual level of the FIFO.     
JREG_WATERLEVEL = 0x0B -- Contains the Waterlevel value for the FIFO 
JREG_CONTROL = 0x0C -- Contains information about last received bits, Initiator mode bit, bit to copy NFCID to FIFO and to Start and stopthe Timer unit.
JREG_BITFRAMING = 0x0D -- Contains information of last bits to send, to align received bits in FIFO and activate sending in Transceive]]
JREG_COLL = 0x0E -- Contains all necessary bits for Collission handling 
JREG_RFU0F = 0x0F -- Currently not used.                                 

JREG_PAGE1 = 0x10 -- Page register in page 1
JREG_MODE = 0x11 -- Contains bits for auto wait on Rf, to detect SYNC byte in NFC mode and MSB first for CRC calculation
JREG_TXMODE = 0x12 -- Contains Transmit Framing, Speed, CRC enable, bit for inverse mode and TXMix bit.                            
JREG_RXMODE = 0x13 -- Contains Transmit Framing, Speed, CRC enable, bit for multiple receive and to filter errors.                 
JREG_TXCONTROL = 0x14 -- Contains bits to activate and configure Tx1 and Tx2 and bit to activate 100% modulation.                      
JREG_TXAUTO = 0x15 -- Contains bits to automatically switch on/off the Rf and to do the collission avoidance and the initial rf-on.
JREG_TXSEL = 0x16 -- Contains SigoutSel, DriverSel and LoadModSel bits.
JREG_RXSEL = 0x17 -- Contains UartSel and RxWait bits.                 
JREG_RXTRESHOLD = 0x18 -- Contains MinLevel and CollLevel for detection.    
JREG_DEMOD = 0x19 -- Contains bits for time constants, hysteresis and IQ demodulator settings. 
JREG_FELICANFC = 0x1A -- Contains bits for minimum FeliCa length received and for FeliCa syncronisation length.
JREG_FELICANFC2 = 0x1B -- Contains bits for maximum FeliCa length received.      
JREG_MIFARE = 0x1C -- Contains Miller settings, TxWait settings and MIFARE halted mode bit.
JREG_MANUALRCV = 0x1D -- Currently not used.                          
JREG_RFU1E = 0x1E -- Currently not used.                          
JREG_SERIALSPEED = 0x1F -- Contains speed settings for serila interface.

JREG_PAGE2 = 0x20 -- Page register in page 2 
JREG_CRCRESULT1 = 0x21 -- Contains MSByte of CRC Result.                
JREG_CRCRESULT2 = 0x22 -- Contains LSByte of CRC Result.                
JREG_GSNLOADMOD = 0x23 -- Contains the conductance and the modulation settings for the N-MOS transistor only for load modulation (See difference to JREG_GSN!). 
JREG_MODWIDTH = 0x24 -- Contains modulation width setting.                    
JREG_TXBITPHASE = 0x25 -- Contains TxBitphase settings and receive clock change.
JREG_RFCFG = 0x26 -- Contains sensitivity of Rf Level detector, the receiver gain factor and the RfLevelAmp.
JREG_GSN = 0x27 -- Contains the conductance and the modulation settings for the N-MOS transistor during active modulation (no load modulation setting!).
JREG_CWGSP = 0x28 -- Contains the conductance for the P-Mos transistor.    
JREG_MODGSP = 0x29 -- Contains the modulation index for the PMos transistor.
JREG_TMODE = 0x2A -- Contains all settings for the timer and the highest 4 bits of the prescaler.
JREG_TPRESCALER = 0x2B -- Contais the lowest byte of the prescaler.   
JREG_TRELOADHI = 0x2C -- Contains the high byte of the reload value. 
JREG_TRELOADLO = 0x2D -- Contains the low byte of the reload value.  
JREG_TCOUNTERVALHI = 0x2E -- Contains the high byte of the counter value.
JREG_TCOUNTERVALLO = 0x2F -- Contains the low byte of the counter value. 

JREG_PAGE3 = 0x30 -- Page register in page 3
JREG_TESTSEL1 = 0x31 -- Test register                              
JREG_TESTSEL2 = 0x32 -- Test register                              
JREG_TESTPINEN = 0x33 -- Test register                              
JREG_TESTPINVALUE = 0x34 -- Test register                              
JREG_TESTBUS = 0x35 -- Test register                              
JREG_AUTOTEST = 0x36 -- Test register                              
JREG_VERSION = 0x37 -- Contains the product number and the version .
JREG_ANALOGTEST = 0x38 -- Test register                              
JREG_TESTSUP1 = 0x39 -- Test register                              
JREG_TESTSUP2 = 0x3A -- Test register                              
JREG_TESTADC = 0x3B -- Test register                              
JREG_ANALOGUETEST1 = 0x3C -- Test register                              
JREG_ANALOGUETEST0 = 0x3D -- Test register                              
JREG_ANALOGUETPD_A = 0x3E -- Test register                              
JREG_ANALOGUETPD_B = 0x3F -- Test register                              

CMD_MASK = 0xF0

CMD_IDLE = 0x00
CMD_CONFIGURE = 0x01
CMD_GEN_RAND_ID = 0x02
CMD_CALC_CRC = 0x03
CMD_TRANSMIT = 0x04
CMD_NOCMDCHANGE = 0x07
CMD_RECEIVE = 0x08
CMD_TRANSCEIVE = 0x0C
CMD_AUTOCOLL = 0x0D
CMD_AUTHENT = 0x0E
CMD_SOFT_RESET = 0x0F
-- ============================================================================
JREG_EXT_REG_ENTRANCE = 0x0F -- ext register entrance
-- ============================================================================
JBIT_EXT_REG_WR_ADDR = 0x40 -- wrire address cycle
JBIT_EXT_REG_RD_ADDR = 0x80 -- read address cycle
JBIT_EXT_REG_WR_DATA = 0xC0 -- write data cycle
JBIT_EXT_REG_RD_DATA = 0x00 -- read data cycle

-- ============================================================================
JREG_LPCDTEST = 0x21
-- ============================================================================

-- ============================================================================
JREG_LPCDGMSEL = 0x24
-- ============================================================================
-- LPCD_ENB_AGC_AVDD = 0x00
-- LPCD_ENB_AGC_DVDD = 0x10

-- LPCD_RXCHANGE_JUDGE_MODE_0 = 0x00
-- LPCD_RXCHANGE_JUDGE_MODE_1 = 0x04

-- LPCD_GM_SEL_0 = 0x00
-- LPCD_GM_SEL_1 = 0x01
-- LPCD_GM_SEL_2 = 0x02
-- LPCD_GM_SEL_3 = 0x03

-- ============================================================================
JREG_LPCDSARADC1 = 0x25
-- ============================================================================
-- SARADC_SOC_CFG_4 = 0x00
-- SARADC_SOC_CFG_8 = 0x01
-- SARADC_SOC_CFG_16 = 0x02
-- SARADC_SOC_CFG_24 = 0x03

-- ============================================================================
JREG_LPCDDELTA_HI = 0x26
-- ============================================================================

-- ============================================================================
JREG_LPCDDELTA_LO = 0x27
-- ============================================================================

-- ============================================================================
JREG_LPCDICURR_HI = 0x28
-- ============================================================================

-- ============================================================================
JREG_LPCDICURR_LO = 0x29
-- ============================================================================

-- ============================================================================
JREG_LPCDQCURR_HI = 0x2A
-- ============================================================================

-- ============================================================================
JREG_LPCDQCURR_LO = 0x2B
-- ============================================================================

-- ============================================================================
JREG_LPCDILAST_HI = 0x2C
-- ============================================================================

-- ============================================================================
JREG_LPCDILAST_LO = 0x2D
-- ============================================================================

-- ============================================================================
JREG_LPCDQLAST_HI = 0x2E
-- ============================================================================

-- ============================================================================
JREG_LPCDQLAST_LO = 0x2F
-- ============================================================================

-- ============================================================================
JREG_LPCDAUX = 0x30
-- ============================================================================
-- IBN2U = 0x00
-- TEST_BG = 0x01
-- TEST_SAMPLE_I = 0x02
-- TEST_AMP_OUT_IN = 0x03
-- TEST_AMP_OUT_IP = 0x04
-- TEST_AMP_OUT_QN = 0x05
-- TEST_AMP_OUT_QP = 0x06
-- OSC_64K = 0x07
-- VBN2 = 0x08
-- VBN1 = 0x09
-- TEST_BG_VREF = 0x0A
-- AVSS = 0x0B
-- TEST_SAMPLE_Q = 0x0C
-- DVDD = 0x0D
-- TEST_CRYSTAL_VDD = 0x0E
-- AVDD = 0x0F
-- FLOAT_IN = 0x10

-- ============================================================================
JREG_LPCDMISSWUP = 0x31
-- ============================================================================

-- ============================================================================
JREG_LPCDFLAGINV = 0x32
-- ============================================================================
-- LPCD_FLAG_INV_DISABLE = 0x00
-- LPCD_FLAG_INV_ENABLE = 0x20

-- ============================================================================
JREG_LPCDSLEEPTIMER = 0x33
-- ============================================================================

-- ============================================================================
JREG_LPCDTHRESH_H = 0x34
-- ============================================================================

-- ============================================================================
JREG_LPCDTHRESH_L = 0x35
-- ============================================================================

-- ============================================================================
JREG_LPCDREQATIMER = 0x37
-- ============================================================================
-- LPCD_IRQMISSWUP_ENABLE = 0x20
-- LPCD_IRQMISSWUP_DISABLE = 0x00

-- LPCD_REQA_TIME_80us = 0x00
-- LPCD_REQA_TIME_100us = 0x01
-- LPCD_REQA_TIME_120us = 0x02
-- LPCD_REQA_TIME_150us = 0x03
-- LPCD_REQA_TIME_200us = 0x04
-- LPCD_REQA_TIME_250us = 0x05
-- LPCD_REQA_TIME_300us = 0x06
-- LPCD_REQA_TIME_400us = 0x07
-- LPCD_REQA_TIME_500us = 0x08
-- LPCD_REQA_TIME_600us = 0x09
-- LPCD_REQA_TIME_800us = 0x0A
-- LPCD_REQA_TIME_1ms = 0x0B
-- LPCD_REQA_TIME_1ms2 = 0x0C
-- LPCD_REQA_TIME_1ms6 = 0x0D
-- LPCD_REQA_TIME_2ms = 0x0E
-- LPCD_REQA_TIME_2ms5 = 0x0F
-- LPCD_REQA_TIME_3ms = 0x10
-- LPCD_REQA_TIME_3ms5 = 0x11
-- LPCD_REQA_TIME_4ms = 0x12
-- LPCD_REQA_TIME_5ms = 0x13
-- LPCD_REQA_TIME_7ms = 0x14

-- ============================================================================
JREG_LPCDREQAANA = 0x38
-- ============================================================================
-- LPCD_RXGAIN_23DB = 0x00
-- LPCD_RXGAIN_33DB = 0x10 -- default
-- LPCD_RXGAIN_38DB = 0x20
-- LPCD_RXGAIN_43DB = 0x30

-- LPCD_MINLEVEL_3 = 0x00
-- LPCD_MINLEVEL_6 = 0x04
-- LPCD_MINLEVEL_9 = 0x08
-- LPCD_MINLEVEL_C = 0x0C

-- LPCD_MODWIDTH_32 = 0x00
-- LPCD_MODWIDTH_38 = 0x02

-- ============================================================================
JREG_LPCDDETECTMODE = 0x39
-- ============================================================================
-- LPCD_TXSCALE_0 = 0x00 -- 1/8 of the TX power configured by CWGSP/CWGSNON
-- LPCD_TXSCALE_1 = 0x08 -- 1/4 of the TX power configured by CWGSP/CWGSNON
-- LPCD_TXSCALE_2 = 0x10 -- 1/2 of the TX power configured by CWGSP/CWGSNON
-- LPCD_TXSCALE_3 = 0x18 -- 3/4 of the TX power configured by CWGSP/CWGSNON
-- LPCD_TXSCALE_4 = 0x20 -- equal to of the TX power configured by CWGSP/CWGSNON
-- LPCD_TXSCALE_5 = 0x28 -- twice of the TX power configured by CWGSP/CWGSNON
-- LPCD_TXSCALE_6 = 0x30 -- 3 times of the TX power configured by CWGSP/CWGSNON
-- LPCD_TXSCALE_7 = 0x31 -- 4 times of the TX power configured by CWGSP/CWGSNON

-- LPCD_RX_CHANGE_MODE = 0x00
-- LPCD_REQA_MODE = 0x01
-- LPCD_COMBINE_MODE = 0x02

-- ============================================================================
JREG_LPCDCTRLMODE = 0x3A
-- ============================================================================
-- RF_DET_ENABLE = 0x40
-- RF_DET_DISABLE = 0x00

-- RF_DET_SEN_135mV = 0x00
-- RF_DET_SEN_180mV = 0x08
-- RF_DET_SEN_240mV = 0x10
-- RF_DET_SEN_300mV = 0x18

-- LPCD_DISABLE = 0x00
-- LPCD_ENABLE = 0x02

-- ============================================================================
JREG_LPCDIRQ = 0x3B
-- ============================================================================

-- ============================================================================
JREG_LPCDRFTIMER = 0x3C
-- ============================================================================
-- LPCD_IRQINV_ENABLE = 0x20
-- LPCD_IRQINV_DISABLE = 0x00

-- LPCD_IRQ_PUSHPULL = 0x10
-- LPCD_IRQ_OD = 0x00

-- LPCD_RFTIME_5us = 0x00
-- LPCD_RFTIME_10us = 0x01
-- LPCD_RFTIME_15us = 0x02
-- LPCD_RFTIME_20us = 0x03
-- LPCD_RFTIME_25us = 0x04 -- default
-- LPCD_RFTIME_30us = 0x05
-- LPCD_RFTIME_35us = 0x06
-- LPCD_RFTIME_40us = 0x07
-- LPCD_RFTIME_50us = 0x08
-- LPCD_RFTIME_60us = 0x09
-- LPCD_RFTIME_70us = 0x0A
-- LPCD_RFTIME_80us = 0x0B
-- LPCD_RFTIME_100us = 0x0C
-- LPCD_RFTIME_120us = 0x0D
-- LPCD_RFTIME_150us = 0x0E
-- LPCD_RFTIME_200us = 0x0F

-- ============================================================================
JREG_LPCDTXCTRL1 = 0x3D
-- ============================================================================
-- LPCD_TX2_ENABLE = 0x20
-- LPCD_TX2_DISABLE = 0x00

-- LPCD_TX1_ENABLE = 0x10
-- LPCD_TX1_DISABLE = 0x00

-- LPCD_TX2ON_INV_ENABLE = 0x08
-- LPCD_TX2ON_INV_DISABLE = 0x00

-- LPCD_TX1ON_INV_ENABLE = 0x04
-- LPCD_TX1ON_INV_DISABLE = 0x00

-- LPCD_TX2OFF_INV_ENABLE = 0x02
-- LPCD_TX2OFF_INV_DISABLE = 0x00

-- LPCD_TX1OFF_INV_ENABLE = 0x01
-- LPCD_TX1OFF_INV_DISABLE = 0x00

-- ============================================================================
JREG_LPCDTXCTRL2 = 0x3E
-- ============================================================================

-- ============================================================================
JREG_LPCDTXCTRL3 = 0x3F
-- ============================================================================
-- LPCD_FLAG_TOUT_ENABLE = 0x20 -- TOUT Pad, set while LPCD DETECT, clear while LPCD SLEEP/SETUP(LPCD_TXEN_FLAG_INV = 0);
-- LPCD_FLAG_TOUT_DISABLE = 0x00 -- disable TOUT Pad as the LPCD DETECT flag.

-- LPCD_FLAG_D3_ENABLE = 0x10 -- D3 Pad, set while LPCD DETECT, clear while LPCD SLEEP/SETUP(LPCD_TXEN_FLAG_INV = 0);
-- LPCD_FLAG_D3_DISABLE = 0x00 -- disable D3 Pad as the LPCD DETECT flag.

FM17622_SUCCESS = 0x00
FM17622_COMM_ERR = 0xf4

--[[
写FM17622寄存器
@api FM17622.SetReg(address, value)
@number address 地址
@number value    值
@usage
write_rawrc(FM17622_bit_framing,0x07)
]]
local function SetReg(address, value)

    -- log.info("寄存器写：0x",string.format("%X",address),"值为0x",string.format("%X",value))

    i2c.writeReg(FM17622_iic_id, FM17622_iic_addr, address, string.char(value))
end

--[[
读FM17622寄存器
@api FM17622.GetReg(address,len)
@number address 地址
@number len 读取长度
@return number 寄存器值
@usage
local n = read_rawrc(FM17622_com_irq,1) 
]]

local function GetReg(address, len)
    if len == nil then
        len = 1
    end

    local val = i2c.readReg(FM17622_iic_id, FM17622_iic_addr, address, len)

    -- log.info("iic",val,type(val),#val)
    if #val == 0 then
        return nil;
    end
    -- log.info("寄存器读：0x",string.format("%X",address),"值为0x",string.format("%X",string.byte(val)))
    return string.byte(val)
end

local function SetReg_Ext(address, value)
    -- log.info("扩展寄存器写：0x",string.format("%X",address),"值为0x",string.format("%X",string.byte(value)))
    SetReg(JREG_EXT_REG_ENTRANCE, (JBIT_EXT_REG_WR_ADDR + address) % 256)
    SetReg(JREG_EXT_REG_ENTRANCE, (JBIT_EXT_REG_WR_DATA + value) % 256)
    return;
end

-- //***********************************************
-- //函数名称：GetReg_Ext(unsigned char ExtRegAddr)
-- //函数功能：读取扩展寄存器值
-- //入口参数：ExtRegAddr:扩展寄存器地址 
-- //出口参数：unsigned char  TRUE：读取成功   FALSE:失败
-- //***********************************************
local function GetReg_Ext(address)
    -- log.info("扩展寄存器读：0x",string.format("%X",address))
    SetReg(JREG_EXT_REG_ENTRANCE, (JBIT_EXT_REG_RD_ADDR + address))
    return GetReg(JREG_EXT_REG_ENTRANCE)

end

BIT0 = 0x01
BIT1 = 0x02
BIT2 = 0x04
BIT3 = 0x08
BIT4 = 0x10
BIT5 = 0x20
BIT6 = 0x40
BIT7 = 0x80
--[[
对rc522寄存器置位
@api FM17622.set_bit_mask(address, mask)
@number address 地址
@number mask    置位值
@number set     选择置位还是清位
@usage
FM17622.set_bit_mask (rc522_fifo_level, 0x80)	
]]
local function ModifyReg(addr, mask, set)
    local regdata = GetReg(addr)
    if set == 1 then
        regdata = regdata | mask
    else
        regdata = regdata & (~mask);
    end
    SetReg(addr, regdata);
end

--[[
对FM17622寄存器置位
@api FM17622.set_bit_mask(address, mask)
@number address 地址
@number mask    置位值
@usage
FM17622.set_bit_mask (rc522_fifo_level, 0x80)	
]]
function FM17622.set_bit_mask(address, mask)
    ModifyReg(address, mask, 1)
end

--[[
对FM17622寄存器清位
@api FM17622.clear_bit_mask(address, mask)
@number address 地址
@number mask    清位值
@usage
FM17622.clear_bit_mask(rc522_com_irq, 0x80 )
]]
function FM17622.clear_bit_mask(address, mask)
    ModifyReg(address, mask, 0)
end























-- //*************************************
-- //函数  名：FM17622_Initial_ReaderA
-- 设置A卡模式
-- //入口参数：
-- //出口参数：
-- //*************************************
local function FM17622_Initial_ReaderA()
    SetReg(JREG_MODWIDTH, 0x26) -- MODWIDTH = 106kbps
    ModifyReg(JREG_TXAUTO, BIT6, 1) -- Force 100ASK = 1
    SetReg(JREG_GSN, (0x0f << 4)) -- Config GSN Config ModGSN 	
    SetReg(JREG_CWGSP, 63) -- Config GSP  0-63
    SetReg(JREG_CONTROL, BIT4) -- Initiator = 1
    SetReg(JREG_RFCFG, 5 << 4) -- Config RxGain
    SetReg(JREG_RXTRESHOLD, (8 << 4) | 4) -- Config MinLevel Config CollLevel	
end
local function ReaderA_Request()
    SetReg(JREG_TXMODE, 0) -- Disable TxCRC
    SetReg(JREG_RXMODE, 0) -- Disable RxCRC
    SetReg(JREG_COMMAND, 0) -- command = Idel
    SetReg(JREG_FIFOLEVEL, 128) -- Clear FIFO
    SetReg(JREG_FIFODATA, 0x26)
    SetReg(JREG_COMMAND, 12) -- command = Transceive
    SetReg(JREG_BITFRAMING, 0x87) -- Start Send
    sys.wait(5)
    local reg_data = GetReg(JREG_FIFOLEVEL)

    if reg_data == 2 then
        -- 
        nfc_Data["ATQA"] = GetReg(JREG_FIFODATA) * 256 + GetReg(JREG_FIFODATA)
        return FM17622_SUCCESS
    end
    return FM17622_COMM_ERR
end
local function ReaderA_AntiColl()
    SetReg(JREG_TXMODE, 0) -- Disable TxCRC
    SetReg(JREG_RXMODE, 0) -- Disable RxCRC
    SetReg(JREG_COMMAND, 0) -- command = Idel
    SetReg(JREG_FIFOLEVEL, 128) -- Clear FIFO
    SetReg(JREG_FIFODATA, 0x93)
    SetReg(JREG_FIFODATA, 0x20)
    SetReg(JREG_COMMAND, 12) -- command = Transceive
    SetReg(JREG_BITFRAMING, 0x80) -- Start Send
    sys.wait(5)
    local reg_data = GetReg(JREG_FIFOLEVEL)

    if reg_data == 5 then

        local uid1 = GetReg(JREG_FIFODATA)
        nfc_Data["UID"] = {}
        nfc_Data["UID"][1] = uid1

        local uid2 = GetReg(JREG_FIFODATA)
        nfc_Data["UID"][2] = uid2

        local uid3 = GetReg(JREG_FIFODATA)
        nfc_Data["UID"][3] = uid3

        local uid4 = GetReg(JREG_FIFODATA)
        nfc_Data["UID"][4] = uid4

        nfc_Data["BCC"] = GetReg(JREG_FIFODATA)

        if (uid1 ~ uid2 ~ uid3 ~ uid4) == nfc_Data["BCC"] then
            return FM17622_SUCCESS
        end

        return FM17622_COMM_ERR
    end
    return FM17622_COMM_ERR
end

local function ReaderA_Select()
    SetReg(JREG_TXMODE, 0x80) -- Enable TxCRC
    SetReg(JREG_RXMODE, 0x80) -- Enable RxCRC
    SetReg(JREG_COMMAND, 0) -- command = Idel
    SetReg(JREG_FIFOLEVEL, 128) -- Clear FIFO
    SetReg(JREG_FIFODATA, 0x93)
    SetReg(JREG_FIFODATA, 0x70)
    SetReg(JREG_FIFODATA, nfc_Data["UID"][1])
    SetReg(JREG_FIFODATA, nfc_Data["UID"][2])
    SetReg(JREG_FIFODATA, nfc_Data["UID"][3])
    SetReg(JREG_FIFODATA, nfc_Data["UID"][4])
    SetReg(JREG_FIFODATA, nfc_Data["BCC"])
    SetReg(JREG_COMMAND, 12) -- command = Transceive
    SetReg(JREG_BITFRAMING, 0x80) -- Start Send
    sys.wait(5)
    local reg_data = GetReg(JREG_FIFOLEVEL)
    if reg_data == 1 then
        nfc_Data["SAK"] = GetReg(JREG_FIFODATA)
        return FM17622_SUCCESS
    end
    return FM17622_COMM_ERR
end

-- *************************************
-- 函数  名：ReaderA_CardActivate
-- 开始寻卡，找卡选卡
-- 入口参数：
-- 出口参数：FM17622_SUCCESS, FM17622_COMM_ERR
-- *************************************

local function ReaderA_CardActivate()
    local result = ReaderA_Request()
    if result ~= FM17622_SUCCESS then
        return FM17622_COMM_ERR
    end

    result = ReaderA_AntiColl()
    if result ~= FM17622_SUCCESS then
        return FM17622_COMM_ERR
    end

    result = ReaderA_Select()
    if result ~= FM17622_SUCCESS then
        return FM17622_COMM_ERR
    end

    return result
end

local function SetCW(cw_mode)
    local reg
    SetReg(JREG_TXCONTROL, 0x80);
    if cw_mode == TX1_TX2_CW_DISABLE then
        ModifyReg(JREG_TXCONTROL, 1 | 2, 0);
        reg = GetReg(JREG_TXCONTROL)
    end
    if cw_mode == TX1_CW_ENABLE then
        ModifyReg(JREG_TXCONTROL, 1, 1);
        ModifyReg(JREG_TXCONTROL, 2, 0);
    end
    if cw_mode == TX2_CW_ENABLE then
        ModifyReg(JREG_TXCONTROL, 1, 0);
        ModifyReg(JREG_TXCONTROL, 2, 1);
    end
    if cw_mode == TX1_TX2_CW_ENABLE then
        ModifyReg(JREG_TXCONTROL, 1 | 2, 1);
    end
    sys.wait(5)
end

--[[ 
FM17622 发送命令通讯
@api FM17622.command()
@number command 发送（0x0e）还是放松并接受（0x0c）
@number data  发送是数据

]]

function FM17622.command(cmd, data)
    local out_data = {}
    local irqEn
    local waitFor
    -- SetReg(JREG_TXMODE, 0) -- Disable TxCRC
    -- SetReg(JREG_RXMODE, 0) -- Disable RxCRC
    SetReg(JREG_COMMAND, 0) -- command = Idel
    SetReg(JREG_FIFOLEVEL, 128) -- Clear FIFO
    for i = 1, #data do
        SetReg(JREG_FIFODATA, data[i])
    end
    SetReg(JREG_COMMAND, cmd) -- command = Transceive
    SetReg(JREG_BITFRAMING, 0x80) -- Start Send

    sys.wait(25)
    FM17622.clear_bit_mask(JREG_BITFRAMING, 0x80)

    local reg_data = GetReg(JREG_FIFOLEVEL)

    if reg_data == 0 then
        return nil
    end
    for i = 1, reg_data do
        out_data[i] = GetReg(JREG_FIFODATA)
    end
    return out_data
end

--[[ 
FM17622 LPCD初始化
@api FM17622.LPCD_setup()
@usage
FM17622.LPCD_setup()
]]
function LPCD_setup()

    SetReg(JREG_COMMAND, CMD_SOFT_RESET)
    sys.wait(5)
    if GetReg(JREG_COMMAND) ~= 0x20 then
        log.debug("没有复位成功", GetReg(JREG_COMMAND))
        return false;
    end

    SetReg_Ext(JREG_LPCDGMSEL, 0x10 | 0x04 | 0x00)
    SetReg_Ext(JREG_LPCDSARADC1, 0x38 | 0x02);
    SetReg_Ext(JREG_LPCDCTRLMODE, 0 | 0 | 2)
    SetReg_Ext(JREG_LPCDDETECTMODE, 0x20 | 0)
    SetReg_Ext(JREG_LPCDSLEEPTIMER, LPCD_SLEEPTIME)
    SetReg_Ext(JREG_LPCDRFTIMER, 0x20 | 0x10 | 0x01)
    SetReg_Ext(JREG_LPCDTHRESH_L, LPCD_THRSH_L)
    SetReg_Ext(JREG_LPCDTXCTRL2, LPCD_CWP)
    SetReg_Ext(JREG_LPCDTXCTRL3, LPCD_CWN)
    log.debug("复位成功")
    return true
end

-- //***********************************************
-- //函数名称：Lpcd_Get_ADC_Value()
-- //函数功能：Lpcd_Get_ADC_Value读取LPCD的ADC数据
--             用于调试的lpcd参数
-- //入口参数：
-- //出口参数：
-- //***********************************************
local function Lpcd_Get_ADC_Value()

    local reg = GetReg_Ext(JREG_LPCDICURR_HI);
    local reg1 = GetReg_Ext(JREG_LPCDICURR_LO);
    local Current1 = (reg << 6) + reg1;
    Current2 = reg % 4 -- ((reg<<6)>>8);
    log.debug("-> LPCD I Current is:", Current2, Current1, "\r\n");

    reg = GetReg_Ext(JREG_LPCDQCURR_HI);
    reg1 = GetReg_Ext(JREG_LPCDQCURR_LO);
    Current1 = (reg << 6) + reg1;
    Current2 = reg % 4 -- ((reg<<6)>>8);
    log.debug("-> LPCD Q Current is:", Current2, Current1, "\r\n");

    reg = GetReg_Ext(JREG_LPCDILAST_HI);
    reg1 = GetReg_Ext(JREG_LPCDILAST_LO);
    Current1 = (reg << 6) + reg1;
    Current2 = reg % 4 -- ((reg<<6)>>8);
    log.debug("-> LPCD I Last is:", Current2, Current1, "\r\n");

    reg = GetReg_Ext(JREG_LPCDQLAST_HI);
    reg1 = GetReg_Ext(JREG_LPCDQLAST_LO);
    Current1 = (reg << 6) + reg1;
    Current2 = reg % 4 -- ((reg<<6)>>8);
    log.debug("-> LPCD Q Last is:", Current2, Current1, "\r\n");

    reg = GetReg_Ext(JREG_LPCDDELTA_HI);
    reg1 = GetReg_Ext(JREG_LPCDDELTA_LO);
    Current1 = (reg << 6) + reg1;
    Current2 = reg % 4 -- ((reg<<6)>>8);
    log.debug("-> LPCD Delta is:", Current2, Current1, "\r\n");

end




-- //***********************************************
-- //函数名称：Lpcd_Card_Event()
-- //函数功能：LPCD检测到卡
-- //入口参数：
-- //出口参数：
-- //***********************************************

local function Lpcd_Card_Event()
    FM17622_Initial_ReaderA()
    SetCW(TX1_TX2_CW_ENABLE)
    nfc_Data = {}--清空选卡
    result = ReaderA_CardActivate()
    if result == FM17622_SUCCESS then
        if endcall ~= nil then
            endcall()
        end
    end
    SetCW(TX1_TX2_CW_DISABLE)
    nfc_Data = {}--清空结束
end

-- //***********************************************
-- //函数名称：Lpcd_IRQ_Event()
-- //函数功能：LPCD中断处理
-- //入口参数：
-- //出口参数：
-- //***********************************************
function Lpcd_IRQ_Event()
    log.debug("FM17622.Lpcd_IRQ_Event");
    gpio.set(FM17622_NPD, 1)
    sys.wait(5)
    local reg = GetReg_Ext(JREG_LPCDIRQ) -- 读取LPCD中断标志，LPCD中断需要判断LPCD IRQ RXCHANGE(0x04)是否置位
    SetReg_Ext(JREG_LPCDIRQ, reg) -- CLEAR LPCD IRQ

    if (reg & 0x08) ~= 0 then
        log.debug("FM17622.Lpcd_IRQ_Event", "-> LPCD IRQ RFDET SET!\r\n");
    end
    if (reg & 0x04) ~= 0 then
        log.debug("FM17622.Lpcd_IRQ_Event", "-> LPCD IRQ RXCHANGE SET!\r\n"); -- LPCD中断标志
        if debug~=nil then
            if debug==true then
                Lpcd_Get_ADC_Value()
            end
        end
        

        Lpcd_Card_Event()

    end
    if (reg & 0x02) ~= 0 then
        log.debug("FM17622.Lpcd_IRQ_Event", "-> LPCD IRQ ATQAREC SET!\r\n");
    end
    if (reg & 0x10) ~= 0 then
        log.debug("FM17622.Lpcd_IRQ_Event", "-> LPCD IRQ MISSWUP SET!\r\n");
    end

    gpio.set(FM17622_NPD, 0)
    sys.wait(5)
    gpio.set(FM17622_NPD, 1)
    sys.wait(5)
    for i = 1, 10, 1 do
        if LPCD_setup() == true then
            break
        end
        gpio.set(FM17622_NPD, 0)
        sys.wait(5)
        gpio.set(FM17622_NPD, 1)
        sys.wait(5)
    end

    sys.wait(5)
    gpio.set(FM17622_NPD, 0)
end

--[[
FM17622 初始化
@module FM17622.setup(iic_id, iic_addr, NPD,IRQ,ENDCall)
@summary FM17622初始化
@author  杨壮壮

@number iic_id iic端口号
@number iic_addr   iic地址
@number NPD     rst引脚
@number  IRQ    INT引脚
@number  Debug  是否调试
@number ENDCall 终端回调执行不用可未空
@return bool 初始化结果
@usage
    FM17622=require "FM17622"
    i2c.setup(1, i2c.FAST)
    FM17622.setup(1, 0x28,20,32,function()

        local Key_A = string.char(0x01,0x02,0x03,0x04,0x05,0x06)
        local wdata = {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}
        FM17622.write_datablock(4,wdata,0,Key_A)
        local strat,rdata=FM17622.read_datablock(4,0,Key_A)
        if strat then
            log.info(json.encode(rdata))     
        end

    end,true)
]]



function FM17622.setup(iic_id, iic_addr, NPD,IRQ,ENDCall,Debug)
    FM17622_iic_id = iic_id
    FM17622_iic_addr = iic_addr
    FM17622_NPD = NPD
    endcall=ENDCall
    debug=Debug;

    gpio.setup(FM17622_NPD, 0, gpio.PULLUP)
    sys.wait(5)
    gpio.set(FM17622_NPD, 1)
    sys.wait(5)



    gpio.debounce(32, 200)
    gpio.setup(32, function(var)
        if nfc_work==false then
            nfc_work=true;
            sys.taskInit(function()
                Lpcd_IRQ_Event()
                nfc_work=false
            end)
            
        end
    end, gpio.PULLDOWN, gpio.FALLING)



    if GetReg(JREG_VERSION) == 0xA2 then
        log.debug("IC Version = FM17622 or FM17610 \r\n")
        LPCD_setup()
        sys.wait(5)
        gpio.set(FM17622_NPD, 0)
        return true
    end


    return false;
end

--[[
@module  write_datablock
@summary 写入ic卡数据
@author  杨壮壮
@number addr    ic卡地址块0到64
@number data    写入数据
@number A/B密码选择   A为0，B为1
@number key      密码字符串
@usage
local Key_A = string.char(0x01,0x02,0x03,0x04,0x05,0x06)
        local wdata = {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00}
        FM17622.write_datablock(4,wdata,0,Key_A)
]]
function FM17622.write_datablock(addr, data, mode, key)
    if #data ~= 16 then
        log.error("data must be 16 bytes")
        return false
    end
    if nfc_Data["UID"] == nil then
        log.error("UID 不能为空")
        return false
    end
    if #key ~= 6 then
        log.error("key must be 6 bytes")
        return false
    end

    -- 验证密码
    local buff = {}
    buff[1] = mode + 0x60
    buff[2] = addr
    for i = 1, 6 do
        buff[i + 2] = key:byte(i)
    end
    for i = 1, 4 do
        buff[i + 8] = nfc_Data["UID"][i]
    end
    FM17622.command(0x0E, buff)
    if (GetReg(JREG_STATUS2) & 0x08) == 0 then
        log.info("密码错误", (GetReg(JREG_STATUS2) & 0x08))
        return false
    end
    
    buff = {}
    buff[1] = 0xa0
    buff[2] = addr
    FM17622.command(0x0C, buff)
    FM17622.command(0x0C, data)
    

end

--[[
@module  read_datablock
@summary 读取ic卡数据
@author  杨壮壮
@number addr    ic卡地址块0到64
@number A/B密码选择   A为0，B为1
@number key      密码字符串

@usage
local Key_A = string.char(0x01,0x02,0x03,0x04,0x05,0x06)
local strat,rdata=FM17622.read_datablock(4,0,Key_A)
        if strat then
            log.info(json.encode(rdata))     
        end
]]
function FM17622.read_datablock(addr, mode, key)

    if nfc_Data["UID"] == nil then
        log.error("UID 不能为空")
        return false
    end
    if #key ~= 6 then
        log.error("key must be 6 bytes")
        return false
    end

    -- 验证密码
    local buff = {}
    buff[1] = mode + 0x60
    buff[2] = addr
    for i = 1, 6 do
        buff[i + 2] = key:byte(i)
    end
    for i = 1, 4 do
        buff[i + 8] = nfc_Data["UID"][i]
    end
    FM17622.command(0x0E, buff)
    if (GetReg(JREG_STATUS2) & 0x08) == 0 then
        log.info("密码错误", (GetReg(JREG_STATUS2) & 0x08))
        return false
    end

    -- 读取数据
    local buff = {}
    buff[1] = 0x30
    buff[2] = addr
    return true, FM17622.command(0x0C, buff)

end

return FM17622