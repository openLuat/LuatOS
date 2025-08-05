
--[[
@module ap3216c
@summary ap3216c 光照传感器 
@version 1.0
@date    2023.12.20
@author  xwtx
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
PROJECT = "ap3216c"
VERSION = "1.0.0"
sys = require("sys")
ap3216c=require("ap3216c")

local i2c_id = 1

function ap32_test()
    i2c.setup(i2c_id,i2c.SLOW)
    ap3216c.init(i2c_id)
    sys.wait(120)
    while true do
        local ir=ap3216c.ir()
        local ALS=ap3216c.als()
        local PS=ap3216c.ps()
        log.info("ap3216 read ir",ir)
        log.info("ap3216 read ALS",ALS)
        log.info("ap3216 read PS",PS)
        sys.wait(500)
    end
end

sys.taskInit(ap32_test)


sys.run()
]]


local ap3216c={}

local AP3216C_Addr=0x1e
local i2c_id=1

--[[
初始化ap3216c
@api ap3216c.init(i2cid)
@int i2cid 使用的i2c id, 或者是软件i2c的实例
@return nil 无返回值
]]
function ap3216c.init(i2cid)
    i2c_id = i2cid
    i2c.send(i2c_id, AP3216C_Addr, {0x00,0x04})
    sys.wait(50)
    i2c.send(i2c_id, AP3216C_Addr, {0x00,0x03})
    --i2c.send(i2c_id, AP3216C_Addr, {0x00})
    --local data = i2c.recv(i2c_id, AP3216C_Addr, 1)
    --log.info("date",data:toHex())
end

--[[
读取红外强度
@api ap3216c.ir()
@return int 返回红外强度值,如果读取失败会返回nil
]]
function ap3216c.ir()
    i2c.send(i2c_id, AP3216C_Addr, {0x0a})
    local data0= i2c.recv(i2c_id, AP3216C_Addr, 1)
    --log.info("date",data0:toHex())
    i2c.send(i2c_id, AP3216C_Addr, {0x0b})
    local data1= i2c.recv(i2c_id, AP3216C_Addr, 1)
    --log.info("date",data1:toHex())
    if #data0 ~= 1 and #data1 ~=1 then
        return
    end

    local _,ir_l = pack.unpack(data0, "b")
    local _,ir_h = pack.unpack(data1, "b")
    if bit.band(ir_l,0x80) ==0 then
        return bit.bor(bit.lshift( ir_h, 2 ),bit.band(ir_l,0x03))
    else
        log.info("read IR failed")
        return nil
    end
end

--[[
读取光强
@api ap3216c.als()
@return int 返回光强值,如果读取失败会返回nil
]]
function ap3216c.als()
    i2c.send(i2c_id, AP3216C_Addr, {0x0c})
    local data0= i2c.recv(i2c_id, AP3216C_Addr, 1)
    --log.info("date",data0:toHex())
    i2c.send(i2c_id, AP3216C_Addr, {0x0d})
    local data1= i2c.recv(i2c_id, AP3216C_Addr, 1)
    --log.info("date",data1:toHex())

    if #data0 ~= 1 and #data1 ~=1 then
        return
    end

    local _,ir_l = pack.unpack(data0, "b")
    local _,ir_h = pack.unpack(data1, "b")
   
    return bit.bor(bit.lshift( ir_h, 8 ),ir_l)
  
end

--[[
读取距离
@api ap3216c.ps()
@return int 返回距离值,如果读取失败会返回nil
]]
function ap3216c.ps()
    i2c.send(i2c_id, AP3216C_Addr, {0x0e})
    local data0= i2c.recv(i2c_id, AP3216C_Addr, 1)
    --log.info("date",data0:toHex())
    i2c.send(i2c_id, AP3216C_Addr, {0x0f})
    local data1= i2c.recv(i2c_id, AP3216C_Addr, 1)
    --log.info("date",data1:toHex())
    
    if #data0 ~= 1 and #data1 ~=1 then
        return
    end

    local _,ir_l = pack.unpack(data0, "b")
    local _,ir_h = pack.unpack(data1, "b")
   
    return bit.bor(bit.lshift(bit.band(ir_h,0x3f), 4),bit.band(ir_l,0x0f))
  
end

return ap3216c
