local i2cId = 0
local intPin = gpio.WAKEUP2
local interruptMode = false      -- 中断模式
-- 是否打印日志
local logSwitch = true
local moduleName = "da221"

local da221Addr = 0x27
local soft_reset = {0x00, 0x24}         -- 软件复位地址
local chipid_addr = 0x01                -- 芯片ID地址
local rangeaddr = {0x0f, 0x00}          -- 设置加速度量程，默认2g
local int_set1_reg = {0x16, 0x87}       --设置x,y,z发生变化时，产生中断
local int_set2_reg = {0x17, 0x10}       --使能新数据中断，数据变化时，产生中断，本程序不设置
local int_map1_reg = {0x19, 0x04}       --运动的时候，产生中断
local int_map2_reg = {0x1a, 0x01}

local active_dur_addr = {0x27, 0x00}    -- 设置激活时间，默认0x00
local active_ths_addr = {0x28, 0x05}    -- 设置激活阈值
local odr_addr = {0x10, 0x08}           -- 设置采样率 100Hz
local mode_addr = {0x11, 0x00}          -- 设置正常模式
local int_latch_addr = {0x21, 0x02}     -- 设置中断锁存

local x_lsb_reg = 0x02
local x_mab_reg = 0x03
local y_lsb_reg = 0x04
local y_mab_reg = 0x05
local z_lsb_reg = 0x06
local z_mab_reg = 0x07

local active_state = 0x0b
local active_state_data


local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

local function read_xyz()
    i2c.send(i2cId, da221Addr, x_lsb_reg, 1)
    local recv_x_lsb = i2c.recv(i2cId, da221Addr, 1)
    i2c.send(i2cId, da221Addr, x_mab_reg, 1)
    local recv_x_mab = i2c.recv(i2cId, da221Addr, 1)
    local x_data = (string.byte(recv_x_mab) << 8) | string.byte(recv_x_lsb)

    i2c.send(i2cId, da221Addr, y_lsb_reg, 1)
    local recv_y_lsb = i2c.recv(i2cId, da221Addr, 1)
    i2c.send(i2cId, da221Addr, y_mab_reg, 1)
    local recv_y_mab = i2c.recv(i2cId, da221Addr, 1)
    local y_data = (string.byte(recv_y_mab) << 8) | string.byte(recv_y_lsb)

    i2c.send(i2cId, da221Addr, z_lsb_reg, 1)
    local recv_z_lsb = i2c.recv(i2cId, da221Addr, 1)
    i2c.send(i2cId, da221Addr, z_mab_reg, 1)
    local recv_z_mab = i2c.recv(i2cId, da221Addr, 1)
    local z_data = (string.byte(recv_z_mab) << 8) | string.byte(recv_z_lsb)

    local x_accel = x_data / 1024
    local y_accel = y_data / 1024
    local z_accel = z_data / 1024


    return x_accel, y_accel, z_accel
end

-- 中断模式
if interruptMode then
    local function ind()
        logF("int", gpio.get(intPin))
        if gpio.get(intPin) == 1 then
            local x,y,z = read_xyz()      --读取x，y，z轴的数据
            log.info("x", x, "y", y, "z", z)
        end
    end

    -- gpio.debounce(intPin, 100)
    gpio.setup(intPin, ind)

end

local function da221_init()
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


sys.taskInit(function()
    local result = sys.waitUntil("DA221_INIT_SUCCESS")

    -- 轮询读取三轴速度
    if not interruptMode then
        while true do
            -- 读取三轴速度
            local x,y,z = read_xyz()      --读取x，y，z轴的数据
            log.info("x", x, "y", y, "z", z)
            sys.wait(1000)
        end
    end
end)

sys.taskInit(da221_init)