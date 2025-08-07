--[[
@module max31856
@summary max31856 热电偶温度检测 
@version 1.0
@date    2024.06.17
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
--注意:ads1115的配置需按照项目需求配置,您需要按照配置寄存器说明重新配置 ADS1115_CONF_HCMD 和 ADS1115_CONF_LCMD !!!
-- 用法实例
max31856 = require("max31856")

sys.taskInit(function()
    max31856_spi_device = spi.deviceSetup(1,pin.PB11,1,1,8,5*1000*1000,spi.MSB,1,0)
    max31856.init(max31856_spi_device)
    while 1 do
        local cj_temp = max31856.read_cj_temp()
        if cj_temp then
            log.info("max31856 cj_temp: ", cj_temp)
        end
        local tc_temp = max31856.read_tc_temp()
        if tc_temp then
            log.info("max31856 tc_temp: ", tc_temp)
        end
        log.info("max31856 fault: ", max31856.read_fault())
        sys.wait(1000)
    end
end)
]]

--[[
    Register Memory Map
    ADDRESS READ/WRITE NAME     FACTORY FUNCTION
                                DEFAULT
    00h/80h Read/Write CR0      00h     Configuration 0 Register
    01h/81h Read/Write CR1      03h     Configuration 1 Register
    02h/82h Read/Write MASK     FFh     Fault Mask Register
    03h/83h Read/Write CJHF     7Fh     Cold-Junction High Fault Threshold
    04h/84h Read/Write CJLF     C0h     Cold-Junction Low Fault Threshold
    05h/85h Read/Write LTHFTH   7Fh     Linearized Temperature High Fault Threshold MSB
    06h/86h Read/Write LTHFTL   FFh     Linearized Temperature High Fault Threshold LSB
    07h/87h Read/Write LTLFTH   80h     Linearized Temperature Low Fault Threshold MSB
    08h/88h Read/Write LTLFTL   00h     Linearized Temperature Low Fault Threshold LSB
    09h/89h Read/Write CJTO     00h     Cold-Junction Temperature Offset Register
    0Ah/8Ah Read/Write CJTH     00h     Cold-Junction Temperature Register, MSB
    0Bh/8Bh Read/Write CJTL     00h     Cold-Junction Temperature Register, LSB
    0Ch     Read Only  LTCBH    00h     Linearized TC Temperature, Byte 2
    0Dh     Read Only  LTCBM    00h     Linearized TC Temperature, Byte 1
    0Eh     Read Only  LTCBL    00h     Linearized TC Temperature, Byte 0
    0Fh     Read Only  SR       00h     Fault Status Register
]]

local max31856 = {}

local sys = require "sys"

max31856.TCTYPE_B                   =   0x00    -- 类型B
max31856.TCTYPE_E                   =   0x01    -- 类型E
max31856.TCTYPE_J                   =   0x02    -- 类型J
max31856.TCTYPE_K                   =   0x03    -- 类型K
max31856.TCTYPE_N                   =   0x04    -- 类型N
max31856.TCTYPE_R                   =   0x05    -- 类型R
max31856.TCTYPE_S                   =   0x06    -- 类型S
max31856.TCTYPE_T                   =   0x07    -- 类型T

max31856.ONESHOT                    =   0x00    -- 单次转换模式
max31856.CONTINUOUS                 =   0x01    -- 自动转换模式

max31856.SAMPLE1                    =   0x00    -- 1个样品
max31856.SAMPLE2                    =   0x01    -- 2个样品
max31856.SAMPLE4                    =   0x02    -- 4个样品
max31856.SAMPLE8                    =   0x03    -- 8个样品
max31856.SAMPLE16                   =   0x04    -- 16个样品

local MAX31856_CR0_REG   	        =   0x00    -- 配置寄存器0
local MAX31856_CR1_REG       	    =   0x01    -- 配置寄存器1
local MAX31856_MASK_REG      	    =   0x02    -- 故障屏蔽寄存器
local MAX31856_CJHF_REG      	    =   0x03    -- 冷端上限故障
local MAX31856_CJLF_REG      	    =   0x04    -- 冷接下限故障
local MAX31856_LTHFTH_REG      	    =   0x05    -- 线性化温度上限故障 MSB
local MAX31856_LTHFTL_REG      	    =   0x06    -- 线性化温度上限故障 LSB
local MAX31856_LTLFTH_REG      	    =   0x07    -- 线性化温度下限故障 MSB
local MAX31856_LTLFTL_REG      	    =   0x08    -- 线性化温度下限故障 LSB
local MAX31856_CJTO_REG      	    =   0x09    -- 冷端温度偏移寄存器
local MAX31856_CJTH_REG      	    =   0x0A    -- 冷端温度寄存器 MSB
local MAX31856_CJTL_REG      	    =   0x0B    -- 冷端温度寄存器 LSB
local MAX31856_LTCBH_REG      	    =   0x0C    -- 线性化TC温度，字节2
local MAX31856_LTCBM_REG      	    =   0x0D    -- 线性化TC温度，字节1
local MAX31856_LTCBL_REG      	    =   0x0E    -- 线性化TC温度，字节0
local MAX31856_SR_REG      	        =   0x0F    -- 故障状态寄存器

local max31856_spi_device
local max31856_conversion_mode
local max31856_sample_mode

local function max31856_write_cmd(reg, data)
    -- log.info("max31856_write_cmd "..(reg|0x80).." "..data)
    max31856_spi_device:send({reg|0x80, data})
end

local function max31856_read_cmd(reg)
    local data = max31856_spi_device:transfer(string.char(reg))
    -- log.info("max31856_read_cmd "..reg.." "..data:byte())
    return data:byte()
end

local function trigger_oneshot()
    local cr0 = max31856_read_cmd(MAX31856_CR0_REG)
    cr0 = cr0&(~0x80)
    cr0 = cr0|0x40
    max31856_write_cmd(MAX31856_CR0_REG, cr0)
end

local function oneshot_conversion_complete()
    return (max31856_read_cmd(MAX31856_CR0_REG) & 0x40) == 0
end

--[[
设置热电偶类型
@api max31856.set_tc_type(type)
@number type max31856.TCTYPE_B max31856.TCTYPE_E max31856.TCTYPE_J max31856.TCTYPE_K max31856.TCTYPE_N max31856.TCTYPE_R max31856.TCTYPE_S max31856.TCTYPE_T
@usage
max31856.set_tc_type(max31856.TCTYPE_K) -- 设置类型为K
]]
function max31856.set_tc_type(type)
    local cr1 = max31856_read_cmd(MAX31856_CR1_REG)
    cr1 = cr1&0xF0
    max31856_write_cmd(MAX31856_CR1_REG, cr1|type)
end

--[[
设置热电偶电压转换平均模式 
@api max31856.set_avgsel(sample_count)
@number sample_count max31856.SAMPLE1 max31856.SAMPLE2 max31856.SAMPLE4 max31856.SAMPLE8 max31856.SAMPLE16
@usage
max31856.set_avgsel(max31856.SAMPLE1) -- 设置平均模式为1个样品
]]
function max31856.set_avgsel(sample_count)
    max31856_sample_mode = sample_count
    local cr1 = max31856_read_cmd(MAX31856_CR1_REG)
    max31856_write_cmd(MAX31856_CR1_REG, cr1|(sample_count<<4))
end

--[[
设置转化模式
@api max31856.set_cmode(type)
@number type max31856.ONESHOT max31856.CONTINUOUS
@usage
max31856.set_cmode(max31856.ONESHOT) -- 设置转化模式为单次转换
]]
function max31856.set_cmode(type)
    max31856_conversion_mode = type
    local cr0 = max31856_read_cmd(MAX31856_CR0_REG)
    if type == max31856.ONESHOT then
        cr0 = cr0&(~0x80)
        cr0 = cr0|0x40
    else
        cr0 = cr0|0x80
        cr0 = cr0&(~0x40)
    end
    max31856_write_cmd(MAX31856_CR0_REG, cr0)
end

--[[
读取错误码
@api max31856.read_fault()
@return number 错误码
@usage
local fault = max31856.read_fault()
]]
function max31856.read_fault()
    return max31856_read_cmd(MAX31856_SR_REG)
end

--[[
读取冷端温度
@api max31856.read_cj_temp()
@return number 冷端温度
@usage
local cj_temp = max31856.read_cj_temp()
]]
function max31856.read_cj_temp()
    if max31856_conversion_mode == max31856.ONESHOT then
        trigger_oneshot()
        sys.wait(145+(max31856_sample_mode-1)*33)
        local wait = 20
        while oneshot_conversion_complete() == false do
            sys.wait(10)
            wait = wait - 1
            if wait == 0 then return end
        end
    end
    local CJTH = max31856_read_cmd(MAX31856_CJTH_REG)
    local CJTL = max31856_read_cmd(MAX31856_CJTL_REG)
    return ((CJTH<<8)|CJTL) / 256.0
end

--[[
读取tc温度
@api max31856.read_tc_temp()
@return number tc温度
@usage
local tc_temp = max31856.read_tc_temp()
]]
function max31856.read_tc_temp()
    if max31856_conversion_mode == max31856.ONESHOT then
        trigger_oneshot()
        sys.wait(145+(max31856_sample_mode-1)*33)
        local wait = 20
        while oneshot_conversion_complete() == false do
            sys.wait(10)
            wait = wait - 1
            if wait == 0 then return end
        end
    end
    local LTCBH = max31856_read_cmd(MAX31856_LTCBH_REG)
    local LTCBM = max31856_read_cmd(MAX31856_LTCBM_REG)
    local LTCBL = max31856_read_cmd(MAX31856_LTCBL_REG)
    local temp24 = (LTCBH<<16)|(LTCBM<<8)|LTCBL
    if temp24 & 0x800000 ~= 0 then
        temp24 = temp24 | 0xFF000000
    end
    temp24 = temp24 >> 5
    return temp24 * 0.0078125
end

--[[
max31856 初始化
@api max31856.init(spi_device)
@userdata spi_device spi设备句柄
@return boolean 初始化成功返回true
@usage
max31856.init(spi_device)
]]
function max31856.init(spi_device)
    if type(spi_device) ~= "userdata" then
        return
    end
    max31856_spi_device = spi_device

    max31856_write_cmd(MAX31856_MASK_REG, 0x00) -- 断言所有错误
    max31856_write_cmd(MAX31856_CR0_REG, 0x10) -- 开启开路故障检测
    max31856_write_cmd(MAX31856_CJTO_REG, 0x00) -- 冷端温度偏移设置为零

    max31856.set_tc_type(max31856.TCTYPE_K) -- 设置类型为K

    max31856.set_cmode(max31856.ONESHOT) -- 设置转化模式为单次转换
    max31856.set_avgsel(max31856.SAMPLE1) -- 设置平均模式为1个样品
    return true
end

return max31856































