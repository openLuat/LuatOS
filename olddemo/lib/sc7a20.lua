--[[
@module sc7a20
@summary sc7a20 
@version 1.0
@date    2022.04.11
@author  Dozingfiretruck
@usage
--注意:因使用了sys.wait()所有api需要在协程中使用
-- 用法实例
local sc7a20 = require "sc7a20"
i2cid = 0
i2c_speed = i2c.FAST
sys.taskInit(function()
    i2c.setup(i2cid,i2c_speed)
    sc7a20.init(i2cid)--初始化,传入i2c_id
    while 1 do
        local sc7a20_data = sc7a20.get_data()
        log.info("sc7a20_data", "sc7a20_data.x"..(sc7a20_data.x),"sc7a20_data.y"..(sc7a20_data.y),"sc7a20_data.z"..(sc7a20_data.z))
        sys.wait(1000)
    end
end)
]]


local sc7a20 = {}
local sys = require "sys"
local i2cid

local SC7A20_ADDRESS_ADR                    -- sc7a20设备地址

local SC7A20_ADDRESS_ADR_LOW     =   0x18
local SC7A20_ADDRESS_ADR_HIGH    =   0x19
local SC7A20_CHIP_ID_CHECK       =   0x0f   -- 器件ID检测
local SC7A20_CHIP_ID             =   0x11   -- 器件ID

local SC7A20_REG_CTRL_REG1       =   0x20   -- 控制寄存器1
local SC7A20_REG_CTRL_REG2       =   0x21   -- 控制寄存器2
local SC7A20_REG_CTRL_REG3       =   0x22   -- 控制寄存器3
local SC7A20_REG_CTRL_REG4       =   0x23   -- 控制寄存器4
local SC7A20_REG_CTRL_REG5       =   0x24   -- 控制寄存器5
local SC7A20_REG_CTRL_REG6       =   0x25   -- 控制寄存器6
local SC7A20_REG_REFERENCE       =   0x26   -- 参考寄存器
local SC7A20_REG_STATUS_REG      =   0x27   -- 状态寄存器
local SC7A20_REG_OUT_X_L         =   0x28   -- X轴数据低字节
local SC7A20_REG_OUT_X_H         =   0x29   -- X轴数据高字节
local SC7A20_REG_OUT_Y_L         =   0x2A   -- Y轴数据低字节
local SC7A20_REG_OUT_Y_H         =   0x2B   -- Y轴数据高字节
local SC7A20_REG_OUT_Z_L         =   0x2C   -- Z轴数据低字节
local SC7A20_REG_OUT_Z_H         =   0x2D   -- Z轴数据高字节
local SC7A20_REG_FIFO_CTRL_REG   =   0x2E   -- FIFO控制寄存器
local SC7A20_REG_FIFO_SRC_REG    =   0x2F   -- FIFO源寄存器
local SC7A20_REG_INT1_CFG        =   0x30   -- 中断1配置寄存器
local SC7A20_REG_INT1_SRC        =   0x31   -- 中断1源寄存器
local SC7A20_REG_INT1_THS        =   0x32   -- 中断1阈值寄存器
local SC7A20_REG_INT1_DURATION   =   0x33   -- 中断1持续时间寄存器
local SC7A20_REG_INT2_CFG        =   0x34   -- 中断2配置寄存器
local SC7A20_REG_INT2_SRC        =   0x35   -- 中断2源寄存器
local SC7A20_REG_INT2_THS        =   0x36   -- 中断2阈值寄存器
local SC7A20_REG_INT2_DURATION   =   0x37   -- 中断2持续时间寄存器
local SC7A20_REG_CLICK_CFG       =   0x38   -- 单击配置寄存器
local SC7A20_REG_CLICK_SRC       =   0x39   -- 单击源寄存器
local SC7A20_REG_CLICK_THS       =   0x3A   -- 单击阈值寄存器
local SC7A20_REG_TIME_LIMIT      =   0x3B   -- 单击时间限制寄存器
local SC7A20_REG_TIME_LATENCY    =   0x3C   -- 单击时间延迟寄存器
local SC7A20_REG_TIME_WINDOW     =   0x3D   -- 单击时间窗口寄存器
local SC7A20_REG_ACT_THS         =   0x3E   -- 活动阈值寄存器
local SC7A20_REG_ACT_DUR         =   0x3F   -- 活动持续时间寄存器


--器件ID检测
local function chip_check()
    i2c.send(i2cid, SC7A20_ADDRESS_ADR_LOW, SC7A20_CHIP_ID_CHECK)--读器件地址
    local revData = i2c.recv(i2cid, SC7A20_ADDRESS_ADR_LOW, 1)
    if revData:byte() ~= nil then
        SC7A20_ADDRESS_ADR = SC7A20_ADDRESS_ADR_LOW
    else
        i2c.send(i2cid, SC7A20_ADDRESS_ADR_HIGH, SC7A20_CHIP_ID_CHECK)--读器件地址
        sys.wait(50)
        local revData = i2c.recv(i2cid, SC7A20_ADDRESS_ADR_HIGH, 1)
        if revData:byte() ~= nil then
            SC7A20_ADDRESS_ADR = SC7A20_ADDRESS_ADR_HIGH
        else
            log.info("i2c", "Can't find sc7a20 device")
            return false
        end
    end
    i2c.send(i2cid, SC7A20_ADDRESS_ADR, SC7A20_CHIP_ID_CHECK)--读器件地址
    sys.wait(50)
    local revData = i2c.recv(i2cid, SC7A20_ADDRESS_ADR, 1)
    if revData:byte() == SC7A20_CHIP_ID then
        log.info("Device i2c id is: SC7A20")
    else
        log.info("i2c", "Can't find sc7a20 device")
        return false
    end
    return true
end


--[[
sc7a20 初始化
@api sc7a20.init(i2c_id)
@number i2c id
@return bool   成功返回true
@usage
sc7a20.init(0)
]]
function sc7a20.init(i2c_id)
    i2cid = i2c_id
    sys.wait(20)--20 毫秒等待设备稳定
    if chip_check() then
        i2c.send(i2cid, SC7A20_ADDRESS_ADR, {SC7A20_REG_CTRL_REG1,0X47})
        i2c.send(i2cid, SC7A20_ADDRESS_ADR, {SC7A20_REG_CTRL_REG2,0X00})
        i2c.send(i2cid, SC7A20_ADDRESS_ADR, {SC7A20_REG_CTRL_REG3,0X00})
        i2c.send(i2cid, SC7A20_ADDRESS_ADR, {SC7A20_REG_CTRL_REG4,0X88})
        i2c.send(i2cid, SC7A20_ADDRESS_ADR, {SC7A20_REG_CTRL_REG6,0X00})
        log.info("sc7a20 init_ok")
        sys.wait(20)
        return true
    end
    return false
end

--[[
获取 sc7a20 数据
@api sc7a20.get_data()
@return table sc7a20 数据
@usage
local sc7a20_data = sc7a20.get_data()
log.info("sc7a20_data", "sc7a20_data.x"..(sc7a20_data.x),"sc7a20_data.y"..(sc7a20_data.y),"sc7a20_data.z"..(sc7a20_data.z))
]]
function sc7a20.get_data()
    local accel={x=nil,y=nil,z=nil}
    i2c.send(i2cid, SC7A20_ADDRESS_ADR,SC7A20_REG_OUT_X_L)
    _,accel.x = pack.unpack(i2c.recv(i2cid, SC7A20_ADDRESS_ADR, 2),">h")
    i2c.send(i2cid, SC7A20_ADDRESS_ADR,SC7A20_REG_OUT_Y_L)
    _,accel.y = pack.unpack(i2c.recv(i2cid, SC7A20_ADDRESS_ADR, 2),">h")
    i2c.send(i2cid, SC7A20_ADDRESS_ADR,SC7A20_REG_OUT_Z_L)
    _,accel.z = pack.unpack(i2c.recv(i2cid, SC7A20_ADDRESS_ADR, 2),">h")
    return accel
end


--[[
设置 sc7a20 活动阀值
@api sc7a20.set_thresh (i2cid, activity, time_inactivity)
@number i2c id
@number 活动阀值
@number 活动持续时间
@usage
sc7a20.set_thresh(0, string.char(0x05), string.char(0x05)) 
]]
function sc7a20.set_thresh(i2cid, activity, time_inactivity)
    i2c.writeReg(i2cid, SC7A20_ADDRESS_ADR, SC7A20_REG_ACT_THS, activity)
    i2c.writeReg(i2cid, SC7A20_ADDRESS_ADR, SC7A20_REG_ACT_DUR, time_inactivity)
end


--[[
设置 sc7a20 中断设置
@api sc7a20.set_irqf(i2cid, int, irqf_ths, irqf_duration, irqf_cfg)
@number i2c id
@number 中断脚 传入1及配置INT1脚，传入2及配置INT2脚
@number 中断阀值
@number 中断持续时间
@number 中断配置
@usage
sc7a20.set_irqf(0, 1, string.char(0x05), string.char(0x05), string.char(0x00))
]]
function sc7a20.set_irqf(i2cid, int, irqf_ths, irqf_duration, irqf_cfg)
    if int == 1 then
        i2c.send(i2cid, SC7A20_ADDRESS_ADR, {SC7A20_REG_CTRL_REG3,0X40})        -- AOI1中断映射到INT1上
        i2c.writeReg(i2cid, SC7A20_ADDRESS_ADR, SC7A20_REG_INT1_THS, irqf_ths)
        i2c.writeReg(i2cid, SC7A20_ADDRESS_ADR, SC7A20_REG_INT1_DURATION, irqf_duration)
        i2c.writeReg(i2cid, SC7A20_ADDRESS_ADR, SC7A20_REG_INT1_CFG, irqf_cfg)
    elseif int == 2 then
        i2c.send(i2cid, SC7A20_ADDRESS_ADR, {SC7A20_REG_CTRL_REG6,0X42})        -- AOI2中断映射到INT2上 并且配置低电平触发中断
        i2c.writeReg(i2cid, SC7A20_ADDRESS_ADR, SC7A20_REG_INT2_THS, irqf_ths)
        i2c.writeReg(i2cid, SC7A20_ADDRESS_ADR, SC7A20_REG_INT2_DURATION, irqf_duration)
        i2c.writeReg(i2cid, SC7A20_ADDRESS_ADR, SC7A20_REG_INT2_CFG, irqf_cfg)
    else
        log.info("sc7a20", "int Parameter error")
    end
end


return sc7a20


