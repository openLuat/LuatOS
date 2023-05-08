--[[
@module mlx90614
@summary mlx90614 红外温度
@version 1.0
@date    2023.01.12
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local mlx90614 = require "mlx90614"


sys.taskInit(function()
    -- 硬件i2c方式 618不支持此方式因为618发送会发送停止信号
    i2cid = 0
    i2c_speed = i2c.SLOW
    print("i2c",i2c.setup(i2cid,i2c_speed)) 

    -- 软件i2c 此方式通用,需要 2023.5.8之后编译的固件
    --i2cid = i2c.createSoft(18,19)

    mlx90614.init(i2cid)
    while 1 do
        print("mlx90614 ambient",mlx90614.ambient()) 
        print("mlx90614 object",mlx90614.object()) 
        sys.wait(1000)
    end
end)
]]


local mlx90614 = {}
local sys = require "sys"
local i2cid

local MLX90614_ADDRESS_ADR          =   0x5A

local MLX90614_TA                   =   0x06
local MLX90614_TOBJ1                =   0x07
local MLX90614_TOBJ2                =   0x08

--[[
mlx90614 初始化
@api mlx90614.init(i2c_id)
@number 所在的i2c总线硬件/软件id
@return bool   成功返回true
@usage
mlx90614.init(0)
]]
function mlx90614.init(i2c_id)
    i2cid = i2c_id
    sys.wait(20)--20 毫秒等待设备稳定
end

local rxbuff = zbuff.create(3)

--[[
获取 mlx90614 环境温度
@api mlx90614.ambient()
@return table mlx90614 环境温度
@usage
local mlx90614_ambient = mlx90614.ambient()
log.info("mlx90614_ambient", mlx90614_ambient)
]]
function mlx90614.ambient()
    local ambient
    rxbuff:del()
    local ret = i2c.transfer(i2cid, MLX90614_ADDRESS_ADR, MLX90614_TA, rxbuff, 3)
    if ret then
        ambient = rxbuff[0] | (rxbuff[1] << 8)
        ambient = ambient*0.02 - 273.15
    end
    return ambient
end

--[[
获取 mlx90614 环境温度
@api mlx90614.ambient()
@return table mlx90614 环境温度
@usage
local mlx90614_ambient = mlx90614.ambient()
log.info("mlx90614_ambient", mlx90614_ambient)
]]
function mlx90614.object()
    local object
    rxbuff:del()
    local ret = i2c.transfer(i2cid, MLX90614_ADDRESS_ADR, MLX90614_TOBJ1, rxbuff, 3)
    if ret then
        object = rxbuff[0] | (rxbuff[1] << 8)
        object = object*0.02 - 273.15
    end
    return object
end

return mlx90614


