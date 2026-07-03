local i2cId = 1
local da267Addr = 0x26
local intPin = 39
-- 是否打印日志
local logSwitch = true
local moduleName = "da267"

local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

local interruptCount = 0  -- 计数器
local function ind()
    logF("int", gpio.get(intPin))
    gsensor()  -- 调用gsensor函数，计算设备是否处于运动状态
    if gpio.get(intPin) == 1 then
        -- interruptCount = interruptCount + 1  -- 增加计数器
        -- if interruptCount >= 2 then  -- 判断是否达到2次
        --     gsensor()  -- 调用gsensor函数
        --     interruptCount = 0  -- 重置计数器
        -- end
        -- manage.setLastCrashLevel()
        --读取x，y，z轴的数据
        i2c.send(i2cId, da267Addr, 0x02, 1)
        local data = i2c.recv(i2cId, da267Addr, 6)
        if data and #data == 6 then
            logF("XYZ ORIGIN DATA", data:toHex())
            local xl, xm, yl, ym, zl, zm = string.byte(data, 1, 1), string.byte(data, 2, 2), string.byte(data, 3, 3), string.byte(data, 4, 4), string.byte(data, 5, 5), string.byte(data, 6, 6)
            local x, y, z = (xm << 8 | xl) >> 4, (ym << 8 | yl) >> 4, (zm << 8 | zl) >> 4
            logF("x:", x, "y:", y, "z:", z)
        else
            sys.publish("RESTORE_GSENSOR")
            return
        end
        --读取计步的数据
        i2c.send(i2cId, da267Addr, 0x0D, 1)
        local data = i2c.recv(i2cId, da267Addr, 2)
        if data and #data == 2 then
            local xl, xm = string.byte(data, 1, 1), string.byte(data, 2, 2)
            local step = ((xl << 8) + xm) // 2
            logF("step:", step)
        else
            sys.publish("RESTORE_GSENSOR")
        end
    end
end

-- gpio.debounce(intPin, 100)
gpio.setup(intPin, ind)

local function init()
    --关闭i2c
    i2c.close(i2cId)
    --重新打开i2c,i2c速度设置为低速
    i2c.setup(i2cId, i2c.SLOW)
    --设置传感器的i2c配置
    i2c.send(i2cId, da267Addr, {0x00, 0x24}, 1)
    sys.wait(20)
    --[[设置量程,量程的设置会影响加速度数据的分辨率和灵敏度。
            量程：7、8位
            00：2g,K=3.91
            01：4g,K=7.81
            10：8g,K=15.625
            11：16g,K=31.25
    ]]
    i2c.send(i2cId, da267Addr, {0x0F, 0x00}, 1)
    i2c.send(i2cId, da267Addr, {0x11, 0x34}, 1)
    i2c.send(i2cId, da267Addr, {0x10, 0x07}, 1)

    -- int set1
    i2c.send(i2cId, da267Addr, {0x16, 0x87}, 1)

    -- init active interrupt
    --[[设置中断阈值,用于设置触发中断信号的加速度值。
        0x39是设置X轴中断阈值的地址
        0x3A是设置Y轴中断阈值的地址
        0x3B是设置Z轴中断阈值的地址
        阈值取值为8位寄存器,即0-255
        例如：在本示例中，量程上面设置的是2g,所以加速度为0x05*K=19.55mg
    ]]
    i2c.send(i2cId, da267Addr, {0x38, 0x03}, 1)
    i2c.send(i2cId, da267Addr, {0x39, 0x06}, 1)
    i2c.send(i2cId, da267Addr, {0x3A, 0x06}, 1)
    i2c.send(i2cId, da267Addr, {0x3B, 0x06}, 1)
    i2c.send(i2cId, da267Addr, {0x19, 0x04}, 1)

    -- enable active
    i2c.send(i2cId, da267Addr, {0x11, 0x30}, 1)

    -- init step counter
    i2c.send(i2cId, da267Addr, {0x33, 0x80}, 1)
end

sys.taskInit(function()
    mcu.altfun(mcu.I2C, i2cId, 23, 2, 0)
    mcu.altfun(mcu.I2C, i2cId, 24, 2, 0)
    while true do
        init()
        while true do
            --等待da267传感器数据不正确，复位的消息
            local result = sys.waitUntil("RESTORE_GSENSOR", 60 * 1000)
            --如果接收到了复位消息，则跳出读取数据的循环，重新执行init()函数
            if result then
                break
            end
            --读取da267传感器的型号值，默认是0x13
            i2c.send(i2cId, da267Addr, 0x01, 1)
            local data = i2c.recv(i2cId, da267Addr, 1)
            if not data or data == "" or string.byte(data) ~= 0x13 then
                break
            end
        end
    end
end)
