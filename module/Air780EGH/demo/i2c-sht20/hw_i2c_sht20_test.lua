--[[
@module  hw_i2c_sht20_test
@summary 硬件I2C读取SHT20测试
@version 1.0
@date    2025.07.01
@author  Jensen
@usage
使用Air780EGH核心板通过硬件I2C去读取SHT20温湿度传感器的过程，并介绍luatos中I2C相关接口的用法。
]]

--[[
SHT20 --- 模块
SDA   -   I2C1_SDA PIN67
SCL   -   I2C1_SCL PIN66
VCC   -   3.3V
GND   -   GND

注意这里需要使用luatIO配置工具配置对应管脚功能，详见pins_Air780EGH.json
]]


-- 使用硬件I2C通道 1
local i2c_hwid = 1

--0100 0000  SHT20传感器七位地址
local addr = 0x40
    
function test_hw_i2c_sht20_func()

    local tmp,hum -- 原始数据
    local temp,hump -- 真实值
    
    --初始化硬件I2C
    local ret = i2c.setup(i2c_hwid)
    log.info("i2c".. i2c_hwid, "hw i2c initial",  ret)
    
    while 1 do
        --发送0xF3来查询温度
        i2c.send(i2c_hwid, addr, string.char(0xF3)) 
        sys.wait(100)
        --读取传感器的温度值
        tmp = i2c.recv(i2c_hwid, addr, 2)  
        log.info("SHT20", "read tem data", tmp:toHex())
        
        --发送0xF5来查询湿度
        i2c.send(i2c_hwid, addr, string.char(0xF5)) 
        sys.wait(100)
        --读取传感器湿度值
        hum = i2c.recv(i2c_hwid, addr, 2) 
        log.info("SHT20", "read hum data", hum:toHex())
        
        --提取一个按照大端字节序编码的16位无符号整数
        local _,tval = pack.unpack(tmp,'>H') 
        local _,hval = pack.unpack(hum,'>H')
        --log.info("SHT20", "tval hval", tval,hval)
        if tval and hval then
            --按照传感器手册来计算对应的温湿度
            temp = (((17572 * tval) >> 16) - 4685)/100
            hump = (((12500 * hval) >> 16) - 600)/100
            log.info("SHT20", "temp,humi",string.format("%.2f",temp),string.format("%.2f",hump))
        end
        
        sys.wait(1000)
    end
end


--创建并且启动一个task
--运行这个task的主函数 test_hw_i2c_sht20_func
sys.taskInit(test_hw_i2c_sht20_func)