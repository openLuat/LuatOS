--[[
@module  ads1115plus
@summary ADS1115驱动
测量2次，逼近量程测量方案
可以用8种通道方式,4种差分，4种in0-in3
ads1115完全驱动
@version 1.0
@data    2023/12/14
@author  杨壮壮
@usage
require 'ads1115plus'
sys.taskInit(function ()
	i2c.setup(i2cid, i2c_speed)
    ads1115plus.Setup(i2cid) -- 一次初始化
	
	while true do
		log.info("ads1115:",ads1115plus.task_read(5))
		sys.wait(1000)
	end

end)
]]


require 'sys'

_G.sys = require ("sys")






ads1115plus = {}    --定义存放程序的TABLE 全局变量

local i2cid=1
local i2cslaveaddr = 0x48


--[[
ADS1115初始化
@api ads1115plus.Setup(i2c_id)
@number 所在的i2c总线id
@return bool   成功返回true
@usage
i2c.setup(0, i2c_speed)
ads1115plus.Setup(0)
]]

function ads1115plus.Setup(i2c_id)
    i2cid=i2c_id
    i2c.writeReg(i2cid, i2cslaveaddr, 0x02, string.char(0x00, 0x00)) --给低阈值寄存器写进去值 A1高八位 A2 低八位
    i2c.writeReg(i2cid, i2cslaveaddr, 0x03, string.char(0xff, 0xff)) --给高阈值寄存器写进去值 A1高八位 A2 低八位
    log.info("ADS1115", "init_ok")
    return true
end



--[[
获取ADS1115原始数据
@api ads1115plus.task_recv(MU1,FSR)
@number MUX：通道选择 0-7  MUX=0 AIN0 AIN1   MUX=7 AIN3 GND
MU1
    |                | 000 : AINP = AIN0 and AINN = AIN1 (default)
    |                | 001 : AINP = AIN0 and AINN = AIN3
    |                | 010 : AINP = AIN1 and AINN = AIN3
    |                | 011 : AINP = AIN2 and AINN = AIN3
    |                | 100 : AINP = AIN0 and AINN = GND
    |                | 101 : AINP = AIN1 and AINN = GND
    |                | 110 : AINP = AIN2 and AINN = GND
    |                | 111 : AINP = AIN3 and AINN = GND


@number FSR：量程选择 0-7   2 2.048v 
-- 这个参数的选择：8.1:噪声性能
FSR
    |                | 000 : FSR = В±6.144 V
    |                | 001 : FSR = В±4.096 V
    |                | 010 : FSR = В±2.048 V (默认)
    |                | 011 : FSR = В±1.024 V
    |                | 100 : FSR = В±0.512 V
    |                | 101 : FSR = В±0.256 V
    |                | 110 : FSR = В±0.256 V
    |                | 111 : FSR = В±0.256 V

@return number ADC数据,若读取失败会返回nil
@usage
local ads1115_data = ads1115plus.task_recv(0,2)
log.info("ads1115", ads1115_data)
]]
function ads1115plus.task_recv( MU1,FSR )   
    a1 = 0x80 + (MU1 * 16) + (FSR * 2) + 1  --a1为配置寄存器高八位  a2为低八位
    if FSR > 0x05 then                  --FSR大于5时，切换速率减少噪声，提高采样数据精确度
        a2 = (0x3 * 32) + 3               --量程超过5的时候，速率配置为64sps
        i2c.writeReg(i2cid, i2cslaveaddr, 0x01, string.char(a1, a2)) --给配置寄存器写进去值 A1高八位 A2 低八位
        sys.wait(60)
    else
        a2 = (0x4 * 32) + 3               --其他情况下速率为128sps
        i2c.writeReg(i2cid, i2cslaveaddr, 0x01, string.char(a1, a2)) --给配置寄存器写进去值 A1高八位 A2 低八位
        sys.wait(30)
    end
    
    -- 从转换就绪引脚读取转换好的采集数据2个字节（四个十六进制的数值）的数据
    local data = i2c.readReg(i2cid, i2cslaveaddr,0x00 , 2)  

    local _,val_data_raw = pack.unpack(data, ">h")

    if not val_data_raw then
        return
    end
    if val_data_raw>=0x8000 then
        return ((0xffff-val_data_raw))
    else
        return (val_data_raw)
    end

end

--[[
ADS1115读取mv值
@api ads1115plus.task_read(MU1)
@number 所在的i2c总线id
@return number ADC的mv数据,若读取失败会返回nil
@usage
log.info("ads1115plus:",ads1115plus.task_read(5))
]]


function ads1115plus.task_read(MU1)
    local ads = ads1115plus.task_recv(MU1,0) --先用大量程测量正负6.144去测量 逼近
	if ads == nil then 
		return nil             --判断采样数值是否非空
	end
    local ads_ADC=0
	if ads < 0 then
		ads_ADC = -ads
	else
		ads_ADC = ads
	end
    local mv =0
	if 	ads_ADC > 10922 then	
        if ads_ADC>20000 then
            mv = ads * 0.1875
        else
            ads = ads1115plus.task_recv(MU1,1)
            mv = ads * 0.125
        end
		
	elseif 	ads_ADC > 5461 then	
		ads = ads1115plus.task_recv(MU1,2)
		mv = ads * 0.0625
	elseif 	ads_ADC > 2730 then
		ads = ads1115plus.task_recv(MU1,3)
		mv = ads * 0.03125
	elseif ads_ADC > 1365 then 	
		ads = ads1115plus.task_recv(MU1,4)
		mv = ads * 0.015625
	else
		ads = ads1115plus.task_recv(MU1,5)
		mv = ads * 0.0078125
	end
	return mv   --返回采集到的电压值 单位（mV）有正有负  
end

return ads1115plus

