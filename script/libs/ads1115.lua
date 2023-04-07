--[[
@module ads1115
@summary ads1115 模数转换器 
@version 1.0
@date    2022.03.18
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
--注意:ads1115的配置需按照项目需求配置,您需要按照配置寄存器说明重新配置 ADS1115_CONF_HCMD 和 ADS1115_CONF_LCMD !!!
-- 用法实例
local ads1115 = require "ads1115"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    ads1115.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local ads1115_data = ads1115.get_val()
        log.info("ads1115", ads1115_data)
        sys.wait(1000)
    end
end)
]]

local ads1115 = {}

local sys = require "sys"

local i2cid
local i2cslaveaddr

local ADS1115_ADDRESS_AD0_LOW       =   0x48 -- address pin low (GND), default for InvenSense evaluation board
local ADS1115_ADDRESS_AD0_HIGH      =   0x49 -- address pin high (VCC)
local ADS1115_ADDRESS_AD0_SDA       =   0x4A
local ADS1115_ADDRESS_AD0_SCL       =   0x4B

-- ADS1115 registers define
local ADS1115_DATA_REG   	        =   0x00    --转换寄存器
local ADS1115_CONF_REG			    =   0x01    --配置寄存器
local ADS1115_LOTH_REG			    =   0x02    --阈值比较器高字节寄存器
local ADS1115_HITH_REG	            =   0x03    --阈值比较器低字节寄存器

--[[ 
配置寄存器说明
config register
-----------------------------------------------------------------------------------
CRH[15:8](R/W)
BIT      15      14      13      12      11      10      9       8
NAME     OS      MUX2    MUX1    MUX0    PGA2    PGA1    PGA0    MODE
-----------------------------------------------------------------------------------
L[7:0] (R/W)
BIT      7       6       5       4       3       2       1       0
NAME    DR0     DR1     DR0   COM_MODE COM_POL COM_LAT COM_QUE1 COM_QUE0
-----------------------------------------------------------------------------------
15    | OS             |  运行状态和单次转换开始
    |                | 写时:
    |                | 0   : 无效
    |                | 1   : 开始单次转换(处于掉电状态时)
    |                | 读时:
    |                | 0   : 正在转换
    |                | 1   : 未执行转换
-----------------------------------------------------------------------------------
14:12 | MUX [2:0]      | 输入复用多路配置
    |                | 000 : AINP = AIN0 and AINN = AIN1 (default)
    |                | 001 : AINP = AIN0 and AINN = AIN3
    |                | 010 : AINP = AIN1 and AINN = AIN3
    |                | 011 : AINP = AIN2 and AINN = AIN3
    |                | 100 : AINP = AIN0 and AINN = GND
    |                | 101 : AINP = AIN1 and AINN = GND
    |                | 110 : AINP = AIN2 and AINN = GND
    |                | 111 : AINP = AIN3 and AINN = GND
-----------------------------------------------------------------------------------
11:9  | PGA [2:0]      | 可编程增益放大器配置(FSR  full scale range)
    |                | 000 : FSR = В±6.144 V
    |                | 001 : FSR = В±4.096 V
    |                | 010 : FSR = В±2.048 V (默认)
    |                | 011 : FSR = В±1.024 V
    |                | 100 : FSR = В±0.512 V
    |                | 101 : FSR = В±0.256 V
    |                | 110 : FSR = В±0.256 V
    |                | 111 : FSR = В±0.256 V
-----------------------------------------------------------------------------------
8     | MODE           | 工作模式
    |                | 0   : 连续转换
    |                | 1   : 单次转换
-----------------------------------------------------------------------------------
7:5   | DR [2:0]       | 采样频率
    |                | 000 : 8 SPS
    |                | 001 : 16 SPS
    |                | 010 : 32 SPS
    |                | 011 : 64 SPS
    |                | 100 : 128 SPS (默认)
    |                | 101 : 250 SPS
    |                | 110 : 475 SPS
    |                | 111 : 860 SPS
-----------------------------------------------------------------------------------
4     | COMP_MODE      | 比较器模式
    |                | 0   : 传统比较器 (default)
    |                | 1   : 窗口比较器
-----------------------------------------------------------------------------------
3     | COMP_POL       | Comparator polarity
    |                | 0   : 低电平有效 (default)
    |                | 1   : 高电平有效
-----------------------------------------------------------------------------------
2     | COMP_LAT       | Latching comparator
    |                | 0   : 非锁存比较器. (default)
    |                | 1   : 锁存比较器.
-----------------------------------------------------------------------------------
1:0   | COMP_QUE [1:0] | Comparator queue and disable
    |                | 00  : Assert after one conversion
    |                | 01  : Assert after two conversions
    |                | 10  : Assert after four conversions
    |                | 11  : 禁用比较器并将ALERT/RDY设置为高阻抗 (default)
-----------------------------------------------------------------------------------
]]

local ADS1115_CONF_HCMD	            =   0x42	-- AIN0单端输入 В±4.096 V  连续模式  0 100 001 0
local ADS1115_CONF_LCMD	            =   0x83  	-- 128sps 传统比较器 输出低有效  非锁存比较器 禁用比较器并将ALERT/RDY设置为高阻抗 100 0 0 0 11

--[[
ADS1115初始化
@api ads1115.init(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
ads1115.init(0)
]]
function ads1115.init(i2c_id)
    i2cid = i2c_id
    -- i2cslaveaddr = ADS1115_ADDRESS_AD0_LOW
    log.info("ADS1115", "init_ok")
    return true
end

--[[
获取ADS1115数据
@api ads1115.get_val()
@return number 光照强度数据,若读取失败会返回nil
@usage
local ads1115_data = ads1115.get_val()
log.info("ads1115", ads1115_data)
]]
function ads1115.get_val()
    i2c.send(i2cid, ADS1115_ADDRESS_AD0_LOW,{ADS1115_CONF_REG,ADS1115_CONF_HCMD,ADS1115_CONF_LCMD})
    sys.wait(5)
    i2c.send(i2cid, ADS1115_ADDRESS_AD0_LOW, ADS1115_DATA_REG)
    local _,val_data_raw = pack.unpack(i2c.recv(i2cid, ADS1115_ADDRESS_AD0_LOW, 2), ">h")
    if not val_data_raw then
        return
    end
    if val_data_raw>=0x8000 then
        return ((0xffff-val_data_raw)/32767.0)*4.096
    else
        return (val_data_raw/32768.0)*4.096
    end
end

return ads1115




