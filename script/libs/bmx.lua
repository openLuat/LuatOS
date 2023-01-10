--[[
@module bmx
@summary bmx 气压传感器 目前支持bmp180 bmp280 bme280 bme680 会自动判断器件
@version 1.0
@date    2022.04.9
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local bmx = require "bmx"
i2cid = 0
i2c_speed = i2c.SLOW
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    bmx.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local bmx_data = bmx.get_data()
        if bmx_data.temp then
            log.info("bmx_data_data.temp:"..(bmx_data.temp).."°C")
        end
        if bmx_data.press then
            log.info("bmx_data_data.press:"..(bmx_data.press).."hPa")
        end
        if bmx_data.high then
            log.info("bmx_data_data.high:"..(bmx_data.high).."m")
        end
        if bmx_data.hum then
            log.info("bmx_data_data.hum:"..(bmx_data.hum).."%")
        end
        sys.wait(1000)
    end
end)
]]


local bmx = {}

local sys = require "sys"

local i2cid
local BMX_ADDRESS_ADR
local CHIP_ID

local BMX_ADDRESS_ADR_LOW           =   0x76
local BMX_ADDRESS_ADR_HIGH          =   0x77

---器件所用地址
local BMX_CHIP_ID_CHECK			    =   0xD0	
local BMP180_CHIP_ID                =   0x55
local BMP280_CHIP_ID                =   0x58
local BME280_CHIP_ID                =   0x60
local BME680_CHIP_ID                =   0x61

local BMX_RESET			            =   0xE0
local BMX_RESET_VALUE		        =   0xB6

local BMP180_AC1_ADDR				=   0xAA
local BMP180_AC2_ADDR               =   0xAC  
local BMP180_AC3_ADDR               =   0xAE  
local BMP180_AC4_ADDR               =   0xB0  
local BMP180_AC5_ADDR               =   0xB2  
local BMP180_AC6_ADDR               =   0xB4
local BMP180_B1_ADDR                =   0xB6  
local BMP180_B2_ADDR                =   0xB8  
local BMP180_MB_ADDR                =   0xBA  
local BMP180_MC_ADDR                =   0xBC  
local BMP180_MD_ADDR                =   0xBE

local BMP180_CTRL_ADDR		        =   0xF4 --控制寄存器
local BMP180_CTRL_TEMP		        =   0x2E --转换温度 4.5MS
local BMP180_CTRL_POSS0		        =   0x34 --转换大气压 4.5ms
local BMP180_CTRL_POSS1		        =   0x74 --转换大气压 7.5ms
local BMP180_CTRL_POSS2		        =   0xB4 --转换大气压 13.5ms
local BMP180_CTRL_POSS3		        =   0xF4 --转换大气压 25.5ms

local BMP180_AD_MSB			        =   0xF6 --ADC输出高8位
local BMP180_AD_LSB			        =   0xF7 --ADC输出低8位
local BMP180_AD_XLSB			    =   0xF8 --19位测量时，ADC输出最低3位

local BMX280_T1_ADDR				=   0x88
local BMX280_T2_ADDR				=   0x8A
local BMX280_T3_ADDR				=   0x8C
local BMX280_P1_ADDR				=   0x8E
local BMX280_P2_ADDR				=   0x90
local BMX280_P3_ADDR				=   0x90
local BMX280_P4_ADDR				=   0x94
local BMX280_P5_ADDR				=   0x96
local BMX280_P6_ADDR				=   0x98
local BMX280_P7_ADDR				=   0x9A
local BMX280_P8_ADDR				=   0x9C
local BMX280_P9_ADDR				=   0x9E

local BME280_H1_ADDR				=   0xA1
local BME280_H2_ADDR				=   0xE1
local BME280_H3_ADDR				=   0xE3
local BME280_H4_ADDR				=   0xE4
local BME280_H5_ADDR				=   0xE5
local BME280_H6_ADDR				=   0xE7

local BMX280_CTRLMHUM_ADDR		    =   0xF2 --控制寄存器
local BMX280_STATUS_ADDR		    =   0xF3 --状态寄存器
local BMX280_CTRLMEAS_ADDR		    =   0xF4 --控制寄存器
local BMX280_CONFIG_ADDR		    =   0xF5 --配置寄存器

local BMX280_SLEEP_MODE             =   0x00 
local BMX280_FORCED_MODE            =   0x01 
local BMX280_NORMAL_MODE            =   0x03 

local BMX280_P_MODE_SKIP            =   0x00 --skipped
local BMX280_P_MODE_1               =   0x01 --x1
local BMX280_P_MODE_2               =   0x02 --x2
local BMX280_P_MODE_3               =   0x03 --x4
local BMX280_P_MODE_4               =   0x04 --x8
local BMX280_P_MODE_5               =   0x05 --x16
local BMX280_T_MODE_SKIP            =   0x00 --skipped
local BMX280_T_MODE_1               =   0x01 --x1
local BMX280_T_MODE_2               =   0x02 --x2
local BMX280_T_MODE_3               =   0x03 --x4
local BMX280_T_MODE_4               =   0x04 --x8
local BMX280_T_MODE_5               =   0x05 --x16

local BMX280_FILTER_OFF             =   0x00 --filter off
local BMX280_FILTER_MODE_1		    =   0x01 --0.223*ODR     x2
local BMX280_FILTER_MODE_2		    =   0x02 --0.092*ODR     x4
local BMX280_FILTER_MODE_3		    =   0x03 --0.042*ODR     x8
local BMX280_FILTER_MODE_4		    =   0x04 --0.021*ODR     x16

local BMX280_T_SB1                  =   0x00 --0.5ms
local BMX280_T_SB2			        =   0x01 --62.5ms
local BMX280_T_SB3			        =   0x02 --125ms
local BMX280_T_SB4			        =   0x03 --250ms
local BMX280_T_SB5			        =   0x04 --500ms
local BMX280_T_SB6			        =   0x05 --1000ms
local BMX280_T_SB7			        =   0x06 --2000ms
local BMX280_T_SB8			        =   0x07 --4000ms

local BMX280_H_SB0			        =   0x00 --Skipped (output set to 0x8000)
local BMX280_H_SB1			        =   0x01 --oversampling ×1
local BMX280_H_SB2			        =   0x02 --oversampling ×2
local BMX280_H_SB3			        =   0x03 --oversampling ×4
local BMX280_H_SB4			        =   0x04 --oversampling ×8
local BMX280_H_SB5			        =   0x05 --oversampling ×16

local BMX280_SPI_DISABLE			=   0x00
local BMX280_SPI_ENABLE			    =   0x01

local BME680_CONFIG_ADDR			=   0x75
local BME680_CTRLMEAS_ADDR			=   0x74
local BME680_CTRLHUM_ADDR			=   0x72
local BME680_CTRLGAS1_ADDR			=   0x71
local BME680_CTRLGAS0_ADDR			=   0x70

local BME680_GASRLSB_ADDR			=   0x2B
local BME680_GASRMSB_ADDR			=   0x2A
local BME680_HUMLSB_ADDR			=   0x26
local BME680_HUMMSB_ADDR			=   0x25
local BME680_TEMPXLSB_ADDR			=   0x24
local BME680_TEMPLSB_ADDR			=   0x23
local BME680_TEMPMSB_ADDR			=   0x22
local BME680_PRESSXLSB_ADDR			=   0x21
local BME680_PRESSLSB_ADDR			=   0x20
local BME680_PRESSMSB_ADDR			=   0x1F
local BME680_EASSTATUS0_ADDR		=   0x1D

local BME680_T1_ADDR				=   0xE9
local BME680_T2_ADDR				=   0x8A
local BME680_T3_ADDR				=   0x8C

local BME680_P1_ADDR				=   0x8E
local BME680_P2_ADDR				=   0x90
local BME680_P3_ADDR				=   0x92
local BME680_P4_ADDR				=   0x94
local BME680_P5_ADDR				=   0x96
local BME680_P6_ADDR				=   0x99
local BME680_P7_ADDR				=   0x98
local BME680_P8_ADDR				=   0x9C
local BME680_P9_ADDR				=   0x9E
local BME680_P10_ADDR				=   0xA0

local BME680_H1M_ADDR				=   0xE3
local BME680_H1_ADDR				=   0xE2
local BME680_H2M_ADDR				=   0xE1
local BME680_H3_ADDR				=   0xE4
local BME680_H4_ADDR				=   0xE5
local BME680_H5_ADDR				=   0xE6
local BME680_H6_ADDR				=   0xE7
local BME680_H7_ADDR				=   0xE8

--按照官方手册配置一种模式,此处可自行修改
local osrs_t                        =   BMX280_T_MODE_1
local osrs_p                        =   BMX280_P_MODE_3
local osrs_h                        =   BMX280_H_SB1
local mode                          =   BMX280_NORMAL_MODE
local t_sb                          =   BMX280_T_SB1
local filter                        =   BMX280_FILTER_MODE_4
local spi_en                        =   BMX280_SPI_DISABLE

local ctrl_hum                      =   osrs_h
local ctrl_meas                     =   bit.bor(bit.lshift(osrs_t,5), bit.lshift(osrs_p, 2), mode)
local config                        =   bit.bor(bit.lshift(t_sb,5), bit.lshift(filter, 2), spi_en)

local BMX180_CTRL_TEMP		        =   0x2E --转换温度 4.5MS
local BMX180_CTRL_POSS0		        =   0x34 --转换大气压 4.5ms
local BMX180_CTRL_POSS1		        =   0x74 --转换大气压 7.5ms
local BMX180_CTRL_POSS2		        =   0xB4 --转换大气压 13.5ms
local BMX180_CTRL_POSS3		        =   0xF4 --转换大气压 25.5ms

local BMX280_PRESS_MSB			    =   0xF7
local BMX280_PRESS_LSB			    =   0xF8
local BMX280_PRESS_XLSB			    =   0xF9

local BMX280_TEMP_MSB			    =   0xFA
local BMX280_TEMP_LSB			    =   0xFB
local BMX280_TEMP_XLSB			    =   0xFC

local BMX280_HUM_MSB			    =   0xFD
local BMX280_HUM_LSB			    =   0xFE

local PRESSURE_OF_SEA			    =   101325	-- 参考海平面压强

local AC1,AC2,AC3,AC4,AC5,AC6,B1,B2,MB,MC,MD
local H1,H2,H3,H4,H5,H6,H7,T1,T2,T3,P1,P2,P3,P4,P5,P6,P7,P8,P9,P10


--器件ID检测
local function chip_check()
    i2c.send(i2cid, BMX_ADDRESS_ADR_LOW, BMX_CHIP_ID_CHECK)--读器件地址
    local revData = i2c.recv(i2cid, BMX_ADDRESS_ADR_LOW, 1)
    if revData:byte() ~= nil then
        BMX_ADDRESS_ADR = BMX_ADDRESS_ADR_LOW
    else
        i2c.send(i2cid, BMX_ADDRESS_ADR_HIGH, BMX_CHIP_ID_CHECK)--读器件地址
        sys.wait(50)
        local revData = i2c.recv(i2cid, BMX_ADDRESS_ADR_HIGH, 1)
        if revData:byte() ~= nil then
            BMX_ADDRESS_ADR = BMX_ADDRESS_ADR_HIGH
        else
            log.info("i2c", "Can't find bmx device")
            return false
        end
    end
    i2c.send(i2cid, BMX_ADDRESS_ADR, BMX_CHIP_ID_CHECK)--读器件地址
    sys.wait(50)
    local revData = i2c.recv(i2cid, BMX_ADDRESS_ADR, 1)
    if revData:byte() == BMP180_CHIP_ID then
        CHIP_ID = BMP180_CHIP_ID
        log.info("Device i2c id is: bmp180")
    elseif revData:byte() == BMP280_CHIP_ID then
        CHIP_ID = BMP280_CHIP_ID
        log.info("Device i2c id is: bmp280")
    elseif revData:byte() == BME280_CHIP_ID then
        log.info("Device i2c id is: bme280")
        CHIP_ID = BME280_CHIP_ID
    elseif revData:byte() == BME680_CHIP_ID then
        log.info("Device i2c id is: bme680")
        CHIP_ID = BME680_CHIP_ID
    else
        log.info("i2c", "Can't find bmx device")
        return false
    end
    return true
end

--器件初始化
function bmx.init(i2c_id)
    i2cid = i2c_id
    sys.wait(20)
    if chip_check() then
        i2c.send(i2cid, BMX_ADDRESS_ADR, {BMX_RESET,BMX_RESET_VALUE})--软复位
        sys.wait(20)
        if CHIP_ID == BMP180_CHIP_ID then
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMP180_AC1_ADDR)
            _,AC1 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), ">h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMP180_AC2_ADDR)
            _,AC2 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), ">h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMP180_AC3_ADDR)
            _,AC3 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), ">h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMP180_AC4_ADDR)
            _,AC4 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), ">H")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMP180_AC5_ADDR)
            _,AC5 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), ">H")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMP180_AC6_ADDR)
            _,AC6 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), ">H")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMP180_B1_ADDR)
            _,B1 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), ">h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMP180_B2_ADDR)
            _,B2 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), ">h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMP180_MB_ADDR)
            _,MB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), ">h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMP180_MC_ADDR)
            _,MC = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), ">h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMP180_MD_ADDR)
            _,MD = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), ">h")
        elseif CHIP_ID == BME680_CHIP_ID then
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_T1_ADDR)
            _,T1 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_T2_ADDR)
            _,T2 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_T3_ADDR)
            _,T3 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "<c")

            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_P1_ADDR)
            _,P1 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<H")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_P2_ADDR)
            _,P2 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<H")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_P3_ADDR)
            _,P3 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "<c")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_P4_ADDR)
            _,P4 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_P5_ADDR)
            _,P5 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_P6_ADDR)
            _,P6 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "<c")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_P7_ADDR)
            _,P7 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "<c")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_P8_ADDR)
            _,P8 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_P9_ADDR)
            _,P9 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_P10_ADDR)
            _,P10 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "<c")
            
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_H1M_ADDR)
            local _,tmp1 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_H1_ADDR)
            local _,tmp2 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_H2M_ADDR)
            local _,tmp3 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")

            H1 = bit.bor(bit.lshift(tmp1,4),bit.band(tmp2,0x0F))
            H2 = bit.bor(bit.lshift(tmp3,4),bit.band(bit.rshift(tmp2,4),0x0F))

            if bit.band(H1,0x0080)~=0 then H4 = bit.bxor(-H1,0x00FF) + 1 end
            if bit.band(H2,0x0080)~=0 then H5 = bit.bxor(-H2,0x00FF) + 1 end

            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_H3_ADDR)
            _,H3 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "<c")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_H4_ADDR)
            _,H4 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "<c")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_H5_ADDR)
            _,H5 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "<c")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_H6_ADDR)
            _,H6 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "<c")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BME680_H7_ADDR)
            _,H7 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "<c")

        else
            if CHIP_ID == BME280_CHIP_ID then
                i2c.send(i2cid, BMX_ADDRESS_ADR, BME280_H1_ADDR)
                _,H1 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "<b")
                i2c.send(i2cid, BMX_ADDRESS_ADR, BME280_H2_ADDR)
                _,H2 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
                i2c.send(i2cid, BMX_ADDRESS_ADR, BME280_H3_ADDR)
                _,H3 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "<b")

                i2c.send(i2cid, BMX_ADDRESS_ADR, 0xE4)
                local _,tmp1 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
                i2c.send(i2cid, BMX_ADDRESS_ADR, 0xE5)
                local _,tmp2 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
                i2c.send(i2cid, BMX_ADDRESS_ADR, 0xE6)
                local _,tmp3 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")

                H4 = bit.bor(bit.lshift(tmp1,4),bit.band(tmp2,0x0F))
                H5 = bit.bor(bit.lshift(tmp3,4),bit.band(bit.rshift(tmp2,4),0x0F))

                if bit.band(H4,0x0080)~=0 then H4 = bit.bxor(-H4,0x00FF) + 1 end
                if bit.band(H5,0x0080)~=0 then H5 = bit.bxor(-H5,0x00FF) + 1 end
                
                i2c.send(i2cid, BMX_ADDRESS_ADR, BME280_H6_ADDR)
                _,H6 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "<c")
            end
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMX280_T1_ADDR)
            _,T1 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<H")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMX280_T2_ADDR)
            _,T2 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMX280_T3_ADDR)
            _,T3 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMX280_P1_ADDR)
            _,P1 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<H")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMX280_P2_ADDR)
            _,P2 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMX280_P3_ADDR)
            _,P3 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMX280_P4_ADDR)
            _,P4 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMX280_P5_ADDR)
            _,P5 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMX280_P6_ADDR)
            _,P6 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMX280_P7_ADDR)
            _,P7 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMX280_P8_ADDR)
            _,P8 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
            i2c.send(i2cid, BMX_ADDRESS_ADR, BMX280_P9_ADDR)
            _,P9 = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), "<h")
        end
        if CHIP_ID == BME680_CHIP_ID then
            i2c.send(i2cid, BMX_ADDRESS_ADR, {BME680_CONFIG_ADDR,0x1C})
            i2c.send(i2cid, BMX_ADDRESS_ADR, {BME680_CTRLMEAS_ADDR,ctrl_meas})
            i2c.send(i2cid, BMX_ADDRESS_ADR, {BME680_CTRLHUM_ADDR,ctrl_hum})
            i2c.send(i2cid, BMX_ADDRESS_ADR, {BME680_CTRLGAS1_ADDR,0x19})
            i2c.send(i2cid, BMX_ADDRESS_ADR, {BME680_CTRLGAS0_ADDR,0x08})
        else
            if CHIP_ID == BME280_CHIP_ID then
                i2c.send(i2cid, BMX_ADDRESS_ADR, {BMX280_CTRLMHUM_ADDR,ctrl_hum})
            end
            if CHIP_ID == BMP280_CHIP_ID or CHIP_ID == BME280_CHIP_ID then
                i2c.send(i2cid, BMX_ADDRESS_ADR, {BMX280_CTRLMEAS_ADDR,ctrl_meas})
                i2c.send(i2cid, BMX_ADDRESS_ADR, {BMX280_CONFIG_ADDR,config})
            end
        end
        
        sys.wait(20)--跳过首次数据
        log.info("bmx init_ok")
        return true
    end
    return false
end

--获取温度的原始数据
local function bmx_get_temp_raw()
    local temp_raw
    if CHIP_ID == BMP180_CHIP_ID then
        i2c.send(i2cid, BMX_ADDRESS_ADR,{BMP180_CTRL_ADDR,BMP180_CTRL_TEMP})
        sys.wait(5)
        i2c.send(i2cid, BMX_ADDRESS_ADR,BMP180_AD_MSB)
        local buffer = i2c.recv(i2cid, BMX_ADDRESS_ADR, 2)--获取2字节
        _, temp_raw = pack.unpack(buffer, ">h")
    elseif CHIP_ID == BME680_CHIP_ID then
        i2c.send(i2cid, BMX_ADDRESS_ADR,BME680_TEMPMSB_ADDR)
        local _, MSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        i2c.send(i2cid, BMX_ADDRESS_ADR,BME680_TEMPLSB_ADDR)
        local _, LSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        i2c.send(i2cid, BMX_ADDRESS_ADR,BME680_TEMPXLSB_ADDR)
        local _, XLSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        temp_raw = bit.bor(bit.lshift(MSB,12), bit.lshift(LSB, 4), bit.rshift(XLSB, 4))
    else
        i2c.send(i2cid, BMX_ADDRESS_ADR,BMX280_TEMP_MSB)
        local _, MSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        i2c.send(i2cid, BMX_ADDRESS_ADR,BMX280_TEMP_LSB)
        local _, LSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        i2c.send(i2cid, BMX_ADDRESS_ADR,BMX280_TEMP_XLSB)
        local _, XLSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        temp_raw = bit.bor(bit.lshift(MSB,12), bit.lshift(LSB, 4), bit.rshift(XLSB, 4))
    end
    return temp_raw or 0
end

--获取气压的原始数据
local function bmx_get_pressure_raw()
    local pressure_raw
    if CHIP_ID == BMP180_CHIP_ID then
        i2c.send(i2cid, BMX_ADDRESS_ADR,{BMP180_CTRL_ADDR,BMP180_CTRL_POSS3})
        sys.wait(26)
        i2c.send(i2cid, BMX_ADDRESS_ADR,BMP180_AD_MSB)
        local _, MSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        i2c.send(i2cid, BMX_ADDRESS_ADR,BMP180_AD_LSB)
        local _, LSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        i2c.send(i2cid, BMX_ADDRESS_ADR,BMP180_AD_XLSB)
        local _, XLSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        pressure_raw = bit.rshift((bit.lshift(MSB, 16)+bit.lshift(LSB, 8)+XLSB),5)
    elseif CHIP_ID == BME680_CHIP_ID then
        i2c.send(i2cid, BMX_ADDRESS_ADR,BME680_PRESSMSB_ADDR)
        local _, MSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        i2c.send(i2cid, BMX_ADDRESS_ADR,BME680_PRESSLSB_ADDR)
        local _, LSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        i2c.send(i2cid, BMX_ADDRESS_ADR,BME680_PRESSXLSB_ADDR)
        local _, XLSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        pressure_raw = bit.bor(bit.lshift(MSB,12), bit.lshift(LSB, 4), bit.rshift(XLSB, 4))
    else
        i2c.send(i2cid, BMX_ADDRESS_ADR,BMX280_PRESS_MSB)
        local _, MSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        i2c.send(i2cid, BMX_ADDRESS_ADR,BMX280_PRESS_LSB)
        local _, LSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        i2c.send(i2cid, BMX_ADDRESS_ADR,BMX280_PRESS_XLSB)
        local _, XLSB = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 1), "b")
        pressure_raw = bit.bor(bit.lshift(MSB,12), bit.lshift(LSB, 4), bit.rshift(XLSB, 4))
    end
    return pressure_raw or 0
end

--获取湿度的原始数据 
local function bmx_get_humidity_raw()
    local humidity
    if CHIP_ID == BME680_CHIP_ID then
        i2c.send(i2cid, BMX_ADDRESS_ADR,BME680_HUMMSB_ADDR)
        _, humidity = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), ">h")
    else
        i2c.send(i2cid, BMX_ADDRESS_ADR,BMX280_HUM_MSB)
        _, humidity = pack.unpack(i2c.recv(i2cid, BMX_ADDRESS_ADR, 2), ">h")
    end
    return humidity or 0
end

--[[
获取bmx数据
@api bmx.get_data()
@return table bmx数据
@usage
local bmx_data = bmx.get_data()
if bmx_data.temp then
    log.info("bmx_data_data.temp:"..(bmx_data.temp).."°C")
end
if bmx_data.press then
    log.info("bmx_data_data.press:"..(bmx_data.press).."hPa")
end
if bmx_data.high then
    log.info("bmx_data_data.high:"..(bmx_data.high).."m")
end
if bmx_data.hum then
    log.info("bmx_data_data.hum:"..(bmx_data.hum).."%")
end
]]

function bmx.get_data()
    local bme_data={}
    local temp_raw = bmx_get_temp_raw()
    local pressure_raw = bmx_get_pressure_raw()
    if CHIP_ID == BMP180_CHIP_ID then
        local P = 0
        local X1 = ((temp_raw - AC6) * AC5) / 32768
        local X2 = (MC * 2048) / (X1 + MD)
        local B5 = X1 + X2 
        temp_raw  = (B5 + 8)/16
        bme_data.temp = temp_raw/10
        local B6 = B5 - 4000
        X1 = (B2 * (B6 * B6 /4096))/2048
        X2 = AC2 * B6/2048
        local X3 = X1 + X2 
        local B3 = (((AC1 * 4 + X3)*8) + 2) /4
        X1 = (AC3 * B6)/8192
        X2 = (B1 * (B6 * B6 /4096))/65536
        X3 = ((X1 + X2) + 2)/4
        local B4 = AC4 * (X3 + 32768)/32768
        local B7 = (pressure_raw - B3) * (50000/8)
        if (B7 < 0x80000000)then
            P = (B7 * 2) / B4 
        else
            P = (B7 / B4) * 2
        end
        X1 = (P/256) * (P/256)
        X1 = (X1 * 3038)/65536
        X2 = (-7357 * P)/65536
        P = P + ((X1 + X2 + 3791)/16)
        bme_data.press = P /100
        bme_data.high = 44330 * (1 - math.pow((P / PRESSURE_OF_SEA), (1.0 / 5.255)))
        bme_data.high = 44330 * (1 - math.pow((P / PRESSURE_OF_SEA), (1.0 / 5.255)))
    elseif CHIP_ID == BME680_CHIP_ID then
        local var1 = (temp_raw/16384.0 - T1/1024.0) * T2
        local var2 = ((temp_raw/131072.0 - T1/8192.0) *(temp_raw/131072.0 - T1/8192.0)) * T3 * 16
        local t_fine = var1 + var2
        bme_data.temp = t_fine / 5120.0

        var1 = t_fine/2.0 - 64000.0
        var2 = var1 * var1 * P6 / 131072.0
        var2 = var2 + var1 * P5 * 2.0
        var2 = var2 / 4.0 + P4 * 65536.0
        var1 = (P3 * var1 * var1 / 16384.0 + P2 * var1) / 524288.0
        var1 = (1.0 + var1 / 32768.0)*P1
        if var1==0 then
            return bme_data
        end
        local p = 1048576.0 - pressure_raw
        p = (p - (var2 / 4096.0)) * 6250.0 / var1
        var1 = P9 * p * p / 2147483648.0
        var2 = p * P8 / 32768.0
        local var3 = p / 256.0 * p / 256.0 * p / 256.0 * P10 / 131072.0
        p = p + (var1 + var2 + var3 + P7 * 128.0) / 16.0
        bme_data.press = p /100
        bme_data.high = 44330 * (1 - math.pow((p / PRESSURE_OF_SEA), (1.0 / 5.255)))

        local humidity_raw = bmx_get_humidity_raw()
        local var1 = humidity_raw - (H1 * 16.0 + H3 / 2.0 * bme_data.temp)
        local var2 = var1 * (H2 / 262144.0 * (1.0 + H4 / 16384.0 * bme_data.temp + H5 / 1048576.0 * bme_data.temp * bme_data.temp))
        local var3 = H6 / 16384.0
        local var4 = H7 / 2097152.0;
        bme_data.hum = var2 + ((var3 + var4 * bme_data.temp) * var2 * var2)
    else
        local var1 = (temp_raw/16384.0 - T1/1024.0) * T2
        local var2 = ((temp_raw/131072.0 - T1/8192.0) *(temp_raw/131072.0 - T1/8192.0)) * T3
        local t_fine = var1 + var2
        bme_data.temp = (var1 + var2) / 5120.0
        var1 = t_fine/2.0 - 64000.0
        var2 = var1 * var1 * P6 / 32768.0
        var2 = var2 + var1 * P5 * 2.0
        var2 = var2 / 4.0 + P4 * 65536.0
        var1 = (P3 * var1 * var1 / 524288.0 + P2 * var1) / 524288.0
        var1 = (1.0 + var1 / 32768.0)*P1
        if var1==0 then
            return bme_data
        end
        local p = 1048576.0 - pressure_raw
        p = (p - (var2 / 4096.0)) * 6250.0 / var1
        var1 = P9 * p * p / 2147483648.0
        var2 = p * P8 / 32768.0
        p = p + (var1 + var2 + P7) / 16.0
        bme_data.press = p /100
        bme_data.high = 44330 * (1 - math.pow((p / PRESSURE_OF_SEA), (1.0 / 5.255)))
        if CHIP_ID == BME280_CHIP_ID then
            local humidity_raw = bmx_get_humidity_raw()
            local var_H = t_fine - 76800.0
            var_H = (humidity_raw - (H4 * 64.0 + H5 / 16384.0 * var_H)) * (H2 / 65536.0 * (1.0 + H6 / 67108864.0 * var_H * (1.0 + H3 / 67108864.0 * var_H)))
            var_H = var_H * (1.0 - H1 * var_H / 524288.0)
            if var_H > 100.0 then
                var_H = 100.0
            elseif var_H < 0.0 then
                var_H = 0.0
            end
            bme_data.hum=var_H
        end
    end 
    return bme_data
end

return bmx



