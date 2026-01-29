--[[
@module  soft_i2c_sht20_test
@summary 软件I2C读取SHT20测试
@version 1.0
@date    2025.07.01
@author  Jensen
@usage
使用Air780EGH核心板通过软件I2C去读取SHT20温湿度传感器的过程，并介绍luatos中I2C相关接口的用法。
]]

--[[
SHT20 --- 模块
SDA   -   I2C_SDA GPIO17 PIN100
SCL   -   I2C_SCL GPIO16 PIN97
VCC   -   3.3V
GND   -   GND

注意这里需要使用luatIO配置工具配置对应管脚功能，详见pins_Air780EGH.json
]]

-- 定义软件I2C-SCL
local io_scl = 16
-- 定义软件I2C-SDA
local io_sda = 17

--0100 0000  SHT20传感器七位地址
local addr = 0x40
    
function test_soft_i2c_sht20_func()

    local tmp,hum -- 原始数据
    local temp,hump -- 真实值
    
    --初始化软件I2C, 返回参数为软件I2C的实例，后续通过该实例来操作i2c的读写操作
    local softI2C = i2c.createSoft(io_scl,io_sda)
    log.info("i2c", "sw i2c initial",  softI2C)
    
    while 1 do
        --发送0xF3来查询温度
        i2c.send(softI2C, addr, string.char(0xF3)) 
        sys.wait(100)
        --读取传感器的温度值
        tmp = i2c.recv(softI2C, addr, 2)  
        log.info("SHT20", "read tem data", tmp:toHex())
        
        --发送0xF5来查询湿度
        i2c.send(softI2C, addr, string.char(0xF5)) 
        sys.wait(100)
        --读取传感器湿度值
        hum = i2c.recv(softI2C, addr, 2) 
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
--运行这个task的主函数 test_soft_i2c_sht20_func
sys.taskInit(test_soft_i2c_sht20_func)