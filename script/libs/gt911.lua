--[[
@module gt911
@summary gt911 驱动
@version 1.0
@date    2022.05.26
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local gt911 = require "gt911"

local i2cid = 0
local gt911_res = pin.PA07
local gt911_int = pin.PA00
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    gt911.init(i2cid,gt911_res,gt911_int)
    while 1 do
        sys.wait(1000)
    end
end)

local function gt911CallBack(press_sta,i,x,y)
    print(press_sta,i,x,y)
end

sys.subscribe("GT911",gt911CallBack)
]]


local gt911 = {}
local sys = require "sys"
local i2cid

local gt911_id
local gt911_id_2 = 0x14
local gt911_id_1 = 0x5D

local function gt911_send(...)
    i2c.send(i2cid, gt911_id, {...})
end

local function gt911_recv(...)
    i2c.send(i2cid, gt911_id, {...})
    local _, read_data = pack.unpack(i2c.recv(0, gt911_id, 1), "b")
    return read_data
end

local press_sta = false

local point = {{x=0,y=0},{x=0,y=0},{x=0,y=0},{x=0,y=0},{x=0,y=0}}

--器件ID检测
local function chip_check()
    local ret = i2c.send(i2cid, gt911_id_1,string.char(0x00, 0x00))
    if ret then
        gt911_id = gt911_id_1
    else
        ret = i2c.send(i2cid, gt911_id_2,string.char(0x00, 0x00))
        if ret then
            gt911_id = gt911_id_2
        else
            log.info("gt911", "Can't find device")
            return false
        end
    end
    log.info("gt911", "find device",gt911_id)
    return true
end

--[[
gt911初始化
@api gt911.init(gt911_i2c,gt911_res,gt911_int)
@number gt911_i2c i2c_id
@number gt911_res 复位引脚
@number gt911_int 中断引脚
@return bool   成功返回true
@usage
gt911.init(0)
]]
function gt911.init(gt911_i2c,gt911_res,gt911_int)
    i2cid = gt911_i2c
    gpio.setup(gt911_int, 0)
    gpio.setup(gt911_res, 0)

    gpio.set(gt911_int, 0)
    gpio.set(gt911_res, 1)

    gpio.set(gt911_res, 0)
    sys.wait(10)
    gpio.set(gt911_res, 1)
    sys.wait(10)
    if chip_check()~=true then
        return false
    end
    gpio.setup(gt911_int, 
        function(val) 
            local count
            local data = gt911_recv(0x81, 0x4E)
            if data ~=0 then
                press_sta = true
                press_times = 0
                count = data-128
                -- print("触控点数",count)
                if press_sta == true and count==0 then
                    press_sta = false
                    -- print("抬起")
                    sys.publish("GT911",press_sta,1,point[1].x,point[1].y)
                end
                for i=1,data-128 do
                    point[i].x=gt911_recv(0x81, 0x50+(i-1)*8)+gt911_recv(0x81, 0x51+(i-1)*8)*256
                    point[i].y=gt911_recv(0x81, 0x52+(i-1)*8)+gt911_recv(0x81, 0x53+(i-1)*8)*256
                    -- print(i,point[i].x,point[i].y)
                    sys.publish("GT911",press_sta,i,point[i].x,point[i].y)
                end
                gt911_send(0x81, 0x4E, 0x00)
            else
            end
        end,nil,gpio.RISING)
        
    gt911_send(0x80, 0x40, 0x02)
    gt911_send(0x80, 0x40, 0x00)
    local touchic_id = gt911_recv(0x81, 0x40)
    print("touchic_id",touchic_id)
    return true
end

return gt911


