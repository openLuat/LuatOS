
local da221={}

local i2cId = 0
local intPin = gpio.WAKEUP2
local interruptMode = true      -- 中断模式
-- 是否打印日志
local logSwitch = true
local moduleName = "da221"

local da221Addr = 0x27
local soft_reset = {0x00, 0x24}         -- 软件复位地址
local chipid_addr = 0x01                -- 芯片ID地址
local rangeaddr = {0x0f, 0x00}          -- 设置加速度量程，默认2g
-- local rangeaddr = {0x0f, 0x01}          -- 设置加速度量程，默认4g
-- local rangeaddr = {0x0f, 0x10}          -- 设置加速度量程，默认8g
local int_set1_reg = {0x16, 0x87}       --设置x,y,z发生变化时，产生中断
local int_set2_reg = {0x17, 0x10}       --使能新数据中断，数据变化时，产生中断，本程序不设置
local int_map1_reg = {0x19, 0x04}       --运动的时候，产生中断
local int_map2_reg = {0x1a, 0x01}

local active_dur_addr = {0x27, 0x01}    -- 设置激活时间，默认0x01
local active_ths_addr = {0x28, 0x33}    -- 设置激活阈值，灵敏度最高
-- local active_ths_addr = {0x28, 0x80}    -- 设置激活阈值，灵敏度适中
-- local active_ths_addr = {0x28, 0xFE}    -- 设置激活阈值，灵敏度最低
local odr_addr = {0x10, 0x08}           -- 设置采样率 100Hz
local mode_addr = {0x11, 0x00}          -- 设置正常模式
local int_latch_addr = {0x21, 0x02}     -- 设置中断锁存

local x_lsb_reg = 0x02 -- X轴LSB寄存器地址
local x_msb_reg = 0x03 -- X轴MSB寄存器地址
local y_lsb_reg = 0x04 -- Y轴LSB寄存器地址
local y_msb_reg = 0x05 -- Y轴MSB寄存器地址
local z_lsb_reg = 0x06 -- Z轴LSB寄存器地址
local z_msb_reg = 0x07 -- Z轴MSB寄存器地址

local active_state = 0x0b -- 激活状态寄存器地址
local active_state_data

--[[
    获取da221的xyz轴数据
@api da221.read_xyz()
@return number x轴数据，number y轴数据，number z轴数据
@usage
    local x,y,z =  da221.read_xyz()      --读取x，y，z轴的数据
        log.info("x", x..'g', "y", y..'g', "z", z..'g')
]]
function da221.read_xyz()
    -- da221是LSB在前，MSB在后，每个寄存器都是1字节数据，每次读取都是6个寄存器数据一起获取
    -- 因此直接从X轴LSB寄存器(0x02)开始连续读取6字节数据(X/Y/Z各2字节)，避免出现数据撕裂问题
    i2c.send(i2cId, da221Addr, x_lsb_reg, 1)
    local recv_data = i2c.recv(i2cId, da221Addr, 6)

    -- LSB数据格式为: D[3] D[2] D[1] D[0] unused unused unused unused
    -- MSB数据格式为: D[11] D[10] D[9] D[8] D[7] D[6] D[5] D[4]
    -- 数据位为12位，需要将MSB数据左移4位，LSB数据右移4位，最后进行或运算
    -- 解析X轴数据 (LSB在前，MSB在后)
    local x_data = (string.byte(recv_data, 2) << 4) | (string.byte(recv_data, 1) >> 4)

    -- 解析Y轴数据 (LSB在前，MSB在后)
    local y_data = (string.byte(recv_data, 4) << 4) | (string.byte(recv_data, 3) >> 4)

    -- 解析Z轴数据 (LSB在前，MSB在后)
    local z_data = (string.byte(recv_data, 6) << 4) | (string.byte(recv_data, 5) >> 4)

    -- 转换为12位有符号整数
    -- 判断X轴数据是否大于2047，若大于则表示数据为负数
    -- 因为12位有符号整数的范围是 -2048 到 2047，原始数据为无符号形式，大于2047的部分需要转换为负数
    -- 通过减去4096 (2^12) 将无符号数转换为对应的有符号负数
    if x_data > 2047 then x_data = x_data - 4096 end
    -- 判断Y轴数据是否大于2047，若大于则进行同样的有符号转换
    if y_data > 2047 then y_data = y_data - 4096 end
    -- 判断Z轴数据是否大于2047，若大于则进行同样的有符号转换
    if z_data > 2047 then z_data = z_data - 4096 end

    -- 转换为加速度值（单位：g）
    local x_accel = x_data / 1024
    local y_accel = y_data / 1024
    local z_accel = z_data / 1024

    -- 输出加速度值（单位：g）
    return x_accel, y_accel, z_accel
end


local function da221_init()
    gpio.setup(24, 1, gpio.PULLUP)  -- gsensor 开关
    gpio.setup(164, 1, gpio.PULLUP) -- air8000 和解码芯片公用
    gpio.setup(147, 1, gpio.PULLUP) -- camera的供电使能脚
    log.info("da221 init...")
    --关闭i2c
    i2c.close(i2cId)
    --重新打开i2c,i2c速度设置为低速
    i2c.setup(i2cId, i2c.SLOW)

    sys.wait(50)
    i2c.send(i2cId, da221Addr, soft_reset, 1)
    sys.wait(50)
    i2c.send(i2cId, da221Addr, chipid_addr, 1)
    local chipid = i2c.recv(i2cId, da221Addr, 1)
    log.info("i2c", "chipid",chipid:toHex())
    if string.byte(chipid) == 0x13 then
        log.info("da221 init success")
        sys.publish("DA221_INIT_SUCCESS")
    else
        log.info("da221 init fail")
    end

    -- 设置寄存器
    i2c.send(i2cId, da221Addr, rangeaddr, 1)    --设置加速度量程，默认2g
    sys.wait(5)
    i2c.send(i2cId, da221Addr, int_set1_reg, 1) --设置x,y,z发生变化时，产生中断
    sys.wait(5)
    i2c.send(i2cId, da221Addr, int_map1_reg, 1)--运动的时候，产生中断
    sys.wait(5)
    i2c.send(i2cId, da221Addr, active_dur_addr, 1)-- 设置激活时间，默认0x00
    sys.wait(5)
    i2c.send(i2cId, da221Addr, active_ths_addr, 1)-- 设置激活阈值
    sys.wait(5)
    i2c.send(i2cId, da221Addr, mode_addr, 1)-- 设置模式
    sys.wait(5)
    i2c.send(i2cId, da221Addr, odr_addr, 1)-- 设置采样率
    sys.wait(5)
    i2c.send(i2cId, da221Addr, int_latch_addr, 1)-- 设置中断锁存 中断一旦触发将保持，直到手动清除
    sys.wait(5)
end

--[[
    打开da221
@api da221.open(mode)
@number da221模式设置，1、静态/微动检测，使用场景：微振动检测、手势识别；2、常规运动监测，使用场景：运动监测、车载设备；3、高动态冲击检测，使用场景：碰撞检测、工业冲击
@return nil
@usage
    da221.open(1)
]]
function da221.open(mode)
    if mode==1 or tonumber(mode)==1 then
        --轻微检测
        log.info("轻微检测")
        rangeaddr = {0x0f, 0x00}          -- 设置加速度量程，默认2g
        active_ths_addr = {0x28, 0x1A}    -- 设置激活阈值
        odr_addr = {0x10, 0x04}           -- 设置采样率 15.63Hz
        active_dur_addr = {0x27, 0x01}    -- 设置激活时间，默认0x01
    elseif mode==2 or tonumber(mode)==2 then
        --常规检测
        rangeaddr = {0x0f, 0x01}          -- 设置加速度量程，默认4g
        active_ths_addr = {0x28, 0x26}    -- 设置激活阈值
        odr_addr = {0x10, 0x08}           -- 设置采样率 250Hz
        active_dur_addr = {0x27, 0x14}    -- 设置激活时间，默认0x01
    elseif mode==3 or tonumber(mode)==3 then
        --高动态检测
        rangeaddr = {0x0f, 0x10}          -- 设置加速度量程，默认8g
        active_ths_addr = {0x28, 0x80}    -- 设置激活阈值
        odr_addr = {0x10, 0x0F}           -- 设置采样率 1000Hz
        active_dur_addr = {0x27, 0x04}    -- 设置激活时间，默认0x01
    end
    sys.taskInit(da221_init)
end

return da221