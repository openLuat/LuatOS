--[[
@module pca9685
@summary pca9685 pwm 
@version 1.0
@date    2023.12.26
@author  xwtx
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
PROJECT = "pca9685"
VERSION = "1.0.0"


sys = require("sys")
pca9685=require("pca9685")

local function pca9685_init()
    sys.wait(2000)
    log.info("--------------------------------------------")
    pca9685.Init(60,180)
    while true do
        pca9685.setPWM(0,0,2048);
        sys.wait(500)
     end
end

sys.taskInit(pca9685_init)

sys.run()
]]





local pca9685={}
local i2cId =0     --i2c通道设置



local PCA_Addr = 0x40   --pwm通道地址
local PCA_Model =0x00   --工作模式：读1/写0
local LED0_ON_L =0x06
local LED0_ON_H =0x07
local LED0_OFF_L= 0x08
local LED0_OFF_H =0x09
local PCA_Pre = 0xFE

local function pca9685_Write(addr, data)
   i2c.send(i2cId, PCA_Addr, { addr, data })
   --log.info("PCA9685_Write发送成功:", aa)
   sys.wait(15)
end

local function pca9685_Read(addr)
   i2c.send(i2cId, PCA_Addr, addr)
   sys.wait(5)
   local data = i2c.recv(i2cId,0x40, 1)
   return data
end

function pca9685.Init(hz, angle)  --pcA9685初始化 
   local off=0
   i2c.setup(i2cId, i2c.SLOW)
   pca9685_Write(PCA_Model,0x00)
   pca9685.setFreq(hz)
	off = 145+angle*2.4
   pca9685.setPWM(0,0,off);
	pca9685.setPWM(1,0,off);
	pca9685.setPWM(2,0,off);
	pca9685.setPWM(3,0,off);
	pca9685.setPWM(4,0,off);
	pca9685.setPWM(5,0,off);
	pca9685.setPWM(6,0,off);
	pca9685.setPWM(7,0,off);
	pca9685.setPWM(8,0,off);
	pca9685.setPWM(9,0,off);
	pca9685.setPWM(10,0,off);
	pca9685.setPWM(11,0,off);
	pca9685.setPWM(12,0,off);
	pca9685.setPWM(13,0,off);
	pca9685.setPWM(14,0,off);
	pca9685.setPWM(15,0,off);
   sys.wait(100)
end



function pca9685.setFreq(freq) --PCA9685频率设置
   local prescale
   local oldmode
   local newmode
   local prescaleval

   prescaleval = 25000000;
   prescaleval = prescaleval / 4096
   prescaleval = prescaleval / freq
   prescaleval = prescaleval - 1
   prescale = math.floor(prescaleval + 0.5)
   oldmode = string.toHex(pca9685_Read(PCA_Model))
   newmode = (oldmode & 0x7F)|0x10
   pca9685_Write(PCA_Model, newmode)
   pca9685_Write(PCA_Pre, prescale)
   pca9685_Write(PCA_Model, oldmode)
   sys.wait(5)
   pca9685_Write(PCA_Model, oldmode|0xa1)
end


function pca9685.setPWM(num, on, off)
   local cc = i2c.send(i2cId, PCA_Addr, { LED0_ON_L + 4 * num, on & 0xFF, on >> 8, off & 0xFF, off >> 8 })
   --log.info("PCA9685_setPWM发送成功:", cc)
   sys.wait(5)
end

function pca9685.setAngle(num, angle)
   local off = 0
   off = 158 + angle * 2.2
   pca9685.setPWM(num, 0, off)
end

return pca9685



