-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "dht12demo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

-- 初始化并打开I2C操作DHT12
local function read_dht12(id)
    --if i2c.setup(id, i2c.SLOW) ~= i2c.SLOW then
    --    log.error("I2C.init is: ", "fail")
    --    i2c.close(id)
    --    return
    --end
    local addr = 0xB8
    i2c.writeReg(id, addr, 0x00, 0x00)
    sys.wait(400)
    local data = i2c.recv(id, addr, 5)
    --i2c.close(id)
    log.info("DHT12", data:byte(1), data:byte(2), data:byte(3), data:byte(4), data:byte(5))
    --log.info("DHT12 HEX data: ", data:toHex())
    -- 分别是湿度整数,湿度小数,温度整数,温度湿度
    --[[
    local _, h_H, h_L, t_H, t_L = pack.unpack(data, 'b4')
    log.info("DHT12 data: ", h_H, h_L, t_H, t_L)
    -- 需要考虑温度低于0度的情况, t_L第0位是符号位
    local t_L2 = tonumber(t_L)
    if t_L2 > 127 then
        return h_H .. ".".. h_L, "-" .. t_H .. "." .. tostring(t_L2 - 128)
    else
        return h_H .. ".".. h_L, t_H .. "." .. t_L
    end
    ]]
end

sys.timerLoopStart(function() print("READY") end, 3000)


sys.taskInit(function()
    while 1 do
        print("DHT12", read_dht12(1))
        sys.wait(3000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
