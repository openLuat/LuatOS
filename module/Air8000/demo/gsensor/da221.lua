local i2cId = 0
local intPin = 39
-- 是否打印日志
local logSwitch = true
local moduleName = "da221"

local da221Addr = 0x27
local soft_reset = {0x00, 0x24}     -- 软件复位地址
local chipid_addr = 0x01            -- 芯片ID地址
local rangeaddr = {0x0f, 0x00}      -- 设置加速度量程，默认2g
local int_set1_reg = {0x16, 0x87}   --设置x,y,z发生变化时，产生中断
local int_set2_reg = {0x17, 0x10}   --使能新数据中断，数据变化时，产生中断，本程序不设置
local int_map1_reg = {0x19, 0x04}   --运动的时候，产生中断
local int_map2_reg = {0x1a, 0x01}

local active_dur_addr = {0x27, 0x00}  -- 设置激活时间，默认0x00
local active_ths_addr = {0x28, 0x05}  -- 设置激活阈值
local mode_addr = {0x11, 0x34}  -- 设置模式
local odr_addr = {0x10, 0x08}  -- 设置采样率
local int_latch_addr = {0x21, 0x02}  -- 设置中断锁存

local x_lsb_reg = 0x02
local active_state = 0x0b
local active_state_data


local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

--字符串转字节数组
local function stringToBytes(hexStr)
    local bytes = {}
    for i = 1, #hexStr, 2 do
        local byteStr = hexStr:sub(i, i+1)
        local byte = tonumber(byteStr, 16)
        table.insert(bytes, byte)
    end
    return bytes
end

local interruptCount = 0  -- 计数器
local function ind()
    logF("int", gpio.get(intPin))
    --gsensor()  -- 调用gsensor函数，计算设备是否处于运动状态
    if gpio.get(intPin) == 1 then
        -- interruptCount = interruptCount + 1  -- 增加计数器
        -- if interruptCount >= 2 then  -- 判断是否达到2次
        --     gsensor()  -- 调用gsensor函数
        --     interruptCount = 0  -- 重置计数器
        -- end
        -- manage.setLastCrashLevel()
        --读取x，y，z轴的数据
        i2c.send(i2cId, da221Addr, 0x02, 1)
        local data = i2c.recv(i2cId, da221Addr, 6)
        if data and #data == 6 then
            logF("XYZ ORIGIN DATA", data:toHex())
            local xl, xm, yl, ym, zl, zm = string.byte(data, 1, 1), string.byte(data, 2, 2), string.byte(data, 3, 3), string.byte(data, 4, 4), string.byte(data, 5, 5), string.byte(data, 6, 6)
            local x, y, z = (xm << 8 | xl) >> 4, (ym << 8 | yl) >> 4, (zm << 8 | zl) >> 4
            logF("x:", x, "y:", y, "z:", z)
        else
            sys.publish("RESTORE_GSENSOR")
            return
        end

    end
end

-- gpio.debounce(intPin, 100)
gpio.setup(intPin, ind)

local function init()
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
    else
        log.info("da221 init fail")
    end

    -- 设置寄存器
    i2c.send(i2cId, da221Addr, int_set1_reg, 1)--设置x,y,z发生变化时，产生中断
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
    mcu.altfun(mcu.I2C, i2cId, 13, 2, 0)
    mcu.altfun(mcu.I2C, i2cId, 14, 2, 0)
    -- while true do
        init()


        while true do
        --     --等待da221传感器数据不正确，复位的消息
        --     local result = sys.waitUntil("RESTORE_GSENSOR", 60 * 1000)
        --     --如果接收到了复位消息，则跳出读取数据的循环，重新执行init()函数
        --     if result then
        --         break
        --     end
        --     --读取da221传感器的型号值，默认是0x13
        --     i2c.send(i2cId, da221Addr, 0x01, 1)
        --     local data = i2c.recv(i2cId, da221Addr, 1)
        --     if not data or data == "" or string.byte(data) ~= 0x13 then
        --         break
        --     end
            -- 读取三轴速度
            i2c.send(i2cId, da221Addr, x_lsb_reg, 1)
            local recv_data_xyz = i2c.recv(i2cId, da221Addr, 6)
            local hex_data_xyz = stringToBytes(recv_data_xyz:toHex())
            log.info("recv_data_xyz", recv_data_xyz:toHex())
            if recv_data_xyz and #recv_data_xyz == 6 then
                -- local data_xyz = {}
                -- for i = 1, #recv_data_xyz do
                --     -- 将提取的子字符串添加到结果表中
                --     table.insert(data_xyz, recv_data_xyz:sub(i, i):toHex())
                -- end
                -- data_xyz = data_xyz:byte()
                log.info(string.format("Byte: %02X %02X %02X %02X %02X %02X", hex_data_xyz[1], hex_data_xyz[2], hex_data_xyz[3], hex_data_xyz[4], hex_data_xyz[5], hex_data_xyz[6]))
                -- 提取X轴数据
                local acc_x = ((hex_data_xyz[2] << 8)|hex_data_xyz[1])>>4;
                -- 提取Y轴数据
                local acc_y = ((hex_data_xyz[4] << 8)|hex_data_xyz[3])>>4;
                -- 提取Z轴数据
                local acc_z = ((hex_data_xyz[6] << 8)|hex_data_xyz[5])>>4;
                log.info(string.format("acc_x %.1f", acc_x))
                log.info(string.format("acc_y %.1f", acc_y))
                log.info(string.format("acc_z %.1f", acc_z))
                -- sys.publish("gsensor", {x = acc_x, y = acc_y, z = acc_z})
            end
            sys.wait(4000)
        end
    -- end
end)
