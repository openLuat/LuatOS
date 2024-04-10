--[[
@module pca9685
@summary pca9685 16路PWM驱动舵机 
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

local i2c_id = 1
sys.taskInit(
    function()
        i2c.setup(i2c_id,i2c.SLOW)
        sys.wait(1000)
        pca9685.init(i2c_id,60)
        sys.wait(1000)
        local i=0
        while true do
            pca9685.setpwm(i2c_id,0,i)
            if i >= 100 then
                i=0
            end
            i=i+10
            sys.wait(2000)
        end
    end
)

sys.run()
]]





local pca9685={}




local PCA_Addr = 0x40   --pwm通道地址
local PCA_Model =0x00   --工作模式：读1/写0
local LED0_ON_L =0x06
local LED0_ON_H =0x07
local LED0_OFF_L= 0x08
local LED0_OFF_H =0x09
local PCA_Pre = 0xFE

local function pca9685_write(i2cId,addr, data)
   local ret
   ret=i2c.send(i2cId, PCA_Addr, { addr, data })
   sys.wait(15)
   if ret then
      return true
   else
      return 
   end
end

local function pca9685_read(i2cId,addr)
   i2c.send(i2cId, PCA_Addr, addr)
   sys.wait(5)
   local data = i2c.recv(i2cId,0x40, 1)
   if #data==0 then
      return 
   else
      return data
   end
end
--[[
pca9685 初始化
@api pca9685.init(i2cId,hz)
@int i2cid 使用的i2c id, 或者是软件i2c的实例
@int hz pca9685的输出频率
@return 成功返回true 失败返回nil
]]
function pca9685.init(i2cId,hz)
   local ret=0
   ret=pca9685_write(i2cId,PCA_Model,0x00)
   if not ret then
      return 
   end
   ret=pca9685.setfreq(i2cId,hz)
   if not ret then
      return 
   end
   pca9685.setpwm(i2cId,0,0);
	pca9685.setpwm(i2cId,1,0);
   pca9685.setpwm(i2cId,2,0);
   pca9685.setpwm(i2cId,3,0);
   pca9685.setpwm(i2cId,4,0);
   pca9685.setpwm(i2cId,5,0);
   pca9685.setpwm(i2cId,6,0);
   pca9685.setpwm(i2cId,7,0);
   pca9685.setpwm(i2cId,8,0);
   pca9685.setpwm(i2cId,9,0);
   pca9685.setpwm(i2cId,10,0);
   pca9685.setpwm(i2cId,11,0);
   pca9685.setpwm(i2cId,12,0);
   pca9685.setpwm(i2cId,13,0);
   pca9685.setpwm(i2cId,14,0);
   pca9685.setpwm(i2cId,15,0);
   sys.wait(100)
   return true
end


--[[
pca9685 设置频率
@api pca9685.setfreq(i2cId,freq)
@int i2cid 使用的i2c id, 或者是软件i2c的实例
@int freq pca9685的输出频率,范围为24HZ~1526HZ
@return 成功返回true 失败返回nil
]]
function pca9685.setfreq(i2cId,freq) --PCA9685频率设置
   local prescale
   local oldmode
   local newmode
   local prescaleval
   local ret
   prescaleval = 25000000;
   prescaleval = prescaleval / 4096
   prescaleval = prescaleval / freq
   prescaleval = prescaleval - 1
   prescale = math.floor(prescaleval + 0.5)
   oldmode = string.toHex(pca9685_read(i2cId,PCA_Model))
   newmode = (oldmode & 0x7F)|0x10
   ret=pca9685_write(i2cId,PCA_Model, newmode)
   if not ret then
      return 
   end
   ret=pca9685_write(i2cId,PCA_Pre, prescale)
   if not ret then
      return 
   end
   ret=pca9685_write(i2cId,PCA_Model, oldmode)
   if not ret then
      return 
   end
   sys.wait(5)
   ret=pca9685_write(i2cId,PCA_Model, oldmode|0xa1)
   if not ret then
      return 
   end
   return true
end

--[[
pca9685 设置PWM占空比
@api pca9685.setpwm(i2cId,num, duty_cycle)
@int i2cid 使用的i2c id, 或者是软件i2c的实例
@int num 通道号
@int duty_cycle 占空比 0~100
@return 成功返回true 失败返回nil
]]
function pca9685.setpwm(i2cId,num, duty_cycle)
   local  on = 0
   if duty_cycle==50 then
      on=0
   else
      on=math.floor(4096*((100-duty_cycle)/100))
   end
   local off=on+math.floor(4096*(duty_cycle/100))
   local ret = i2c.send(i2cId, PCA_Addr, { LED0_ON_L + 4 * num, on & 0xFF, on >> 8, off & 0xFF, off >> 8 })
   sys.wait(5)
   if ret==false then
      return 
   end
   return true
end
return pca9685



