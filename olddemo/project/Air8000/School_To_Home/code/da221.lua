local i2cId = 0
local da221Addr = 0x27
local intPin = gpio.WAKEUP2
local logSwitch = false
local moduleName = "da221"
local function logF(...)
    if logSwitch then
        log.info(moduleName, ...)
    end
end

-- 将mg单位转换为m/s²
local function mg_to_ms2(value)
    return value * 9.80665 * 1e-3
end

local function gsensor_xyz()
    i2c.send(i2cId, da221Addr, 0x02, 1)
    local x_lsb = string.byte(i2c.recv(i2cId, da221Addr, 1))
    if not x_lsb then return nil end

    i2c.send(i2cId, da221Addr, 0x03, 1)
    local x_msb = string.byte(i2c.recv(i2cId, da221Addr, 1))
    if not x_msb then return nil end

    i2c.send(i2cId, da221Addr, 0x04, 1)
    local y_lsb = string.byte(i2c.recv(i2cId, da221Addr, 1))
    if not y_lsb then return nil end

    i2c.send(i2cId, da221Addr, 0x05, 1)
    local y_msb = string.byte(i2c.recv(i2cId, da221Addr, 1))
    if not y_msb then return nil end

    i2c.send(i2cId, da221Addr, 0x06, 1)
    local z_lsb = string.byte(i2c.recv(i2cId, da221Addr, 1))
    if not z_lsb then return nil end

    i2c.send(i2cId, da221Addr, 0x07, 1)
    local z_msb = string.byte(i2c.recv(i2cId, da221Addr, 1))
    if not z_msb then return nil end

    local x = (bit.lshift(x_msb, 4) + x_lsb)
    local y = (bit.lshift(y_msb, 4) + y_lsb)
    local z = (bit.lshift(z_msb, 4) + z_lsb)
    return mg_to_ms2(x), mg_to_ms2(y), mg_to_ms2(z)
end

local interruptCount = 0 -- 计数器
local function ind()
    logF("int", gpio.get(intPin))
    gsensor() -- 调用gsensor函数
    if gpio.get(intPin) == 1 then
        -- interruptCount = interruptCount + 1  -- 增加计数器
        -- if interruptCount >= 2 then  -- 判断是否达到2次
        --     gsensor()  -- 调用gsensor函数
        --     interruptCount = 0  -- 重置计数器
        -- end
        -- manage.setLastCrashLevel()
        local x, y, z = gsensor_xyz()
        if x and y and z then
            logF("x:", x, "y:", y, "z:", z)
        else
            sys.publish("RESTORE_GSENSOR")
            return
        end
        i2c.send(i2cId, da221Addr, 0x0D, 1)
        local data = i2c.recv(i2cId, da221Addr, 2)
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
    i2c.close(i2cId)
    i2c.setup(i2cId, i2c.SLOW)
    sys.wait(50)

    i2c.send(i2cId, da221Addr, { 0x00, 0x24 }, 1)
    i2c.send(i2cId, da221Addr, { 0x0F, 0x00 }, 1)
    i2c.send(i2cId, da221Addr, { 0x11, 0x34 }, 1)
    i2c.send(i2cId, da221Addr, { 0x10, 0x07 }, 1)

    -- int set1
    i2c.send(i2cId, da221Addr, { 0x16, 0x87 }, 1)

    -- init active interrupt
    i2c.send(i2cId, da221Addr, { 0x38, 0x03 }, 1)
    i2c.send(i2cId, da221Addr, { 0x39, 0x09 }, 1)
    i2c.send(i2cId, da221Addr, { 0x3A, 0x06 }, 1)
    i2c.send(i2cId, da221Addr, { 0x3B, 0x06 }, 1)
    i2c.send(i2cId, da221Addr, { 0x19, 0x04 }, 1)

    -- enable active
    i2c.send(i2cId, da221Addr, { 0x11, 0x30 }, 1)

    -- init step counter
    i2c.send(i2cId, da221Addr, { 0x33, 0x80 }, 1)
end

sys.taskInit(function()
    while true do
        init()
        while true do
            local result = sys.waitUntil("RESTORE_GSENSOR", 60 * 1000)
            if result then
                break
            end
            i2c.send(i2cId, da221Addr, 0x01, 1)
            local data = i2c.recv(i2cId, da221Addr, 1)
            if not data or data == "" or string.byte(data) ~= 0x13 then
                break
            end
        end
    end
end)
