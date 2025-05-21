--本文件中的主机是指I2C主机，具体指Air8101
--本文件中的从机是指I2C从机，具体指AirGPIO_1000配件板上的IO扩展芯片



local AirGPIO_1000 = 
{
    -- i2c_id：主机的i2c id；
    -- gpio_int_id：主机的GPIO中断引脚id；
    -- slave_address：从机地址；
    -- ints =    --从机各个扩展IO配置为中断时的处理函数以及上一次的输入电平
    -- {
    --     [0x00] = {cb_func=, old_level=},
    --     [0x01] = {cb_func=, old_level=},
    --     [0x02] = {cb_func=, old_level=},
    --     [0x03] = {cb_func=, old_level=},
    --     [0x04] = {cb_func=, old_level=},
    --     [0x05] = {cb_func=, old_level=},
    --     [0x06] = {cb_func=, old_level=},
    --     [0x07] = {cb_func=, old_level=},

    --     [0x10] = {cb_func=, old_level=},
    --     [0x11] = {cb_func=, old_level=},
    --     [0x12] = {cb_func=, old_level=},
    --     [0x13] = {cb_func=, old_level=},
    --     [0x14] = {cb_func=, old_level=},
    --     [0x15] = {cb_func=, old_level=},
    --     [0x16] = {cb_func=, old_level=},
    --     [0x17] = {cb_func=, old_level=},
    -- }
}

-- A0 A1 A2 connect GND
local SALVE_ADDRESS_HIGH_4BIT = (0x40 >> 1)

-- 寄存器地址
local REG_INPUT_PORT_0 = 0x00    -- 输入端口0
local REG_INPUT_PORT_1 = 0x01    -- 输入端口1
local REG_OUTPUT_PORT_0 = 0x02   -- 输出端口0
local REG_OUTPUT_PORT_1 = 0x03   -- 输出端口1
local REG_POL_INV_0 = 0x04       -- 极性反转端口0
local REG_POL_INV_1 = 0x05       -- 极性反转端口1
local REG_CONFIG_0 = 0x06        -- 配置端口0
local REG_CONFIG_1 = 0x07        -- 配置端口1


-- 写入AirGPIO_1000的寄存器

--reg：number类型；
--         表示AirGPIO_1000上的寄存器地址；
--         取值范围：0x00到0x07，参考本文件上方的寄存器地址列表；
--         必须传入，不允许为空；

--value：number类型；
--         表示要写入到AirGPIO_1000寄存器中的数据；
--         取值范围：0x00到0xFF，1个字节的长度；
--         必须传入，不允许为空；

--返回值：成功返回true，失败返回false
local function write_register(reg, value)
    local data = {reg, value}
    local result = i2c.send(AirGPIO_1000.i2c_id, AirGPIO_1000.slave_address, data)
    return result
end

-- 读取AirGPIO_1000的寄存器

--reg：number类型；
--         表示AirGPIO_1000上的寄存器地址；
--         取值范围：0x00到0x07，参考本文件上方的寄存器地址列表；
--         必须传入，不允许为空；

--返回值：成功返回1个字节的number类型，失败返回nil
local function read_register(reg)
    i2c.send(AirGPIO_1000.i2c_id, AirGPIO_1000.slave_address, reg)
    local data = i2c.recv(AirGPIO_1000.i2c_id, AirGPIO_1000.slave_address, 1)
    if data and #data == 1 then
        return string.byte(data, 1)
    end
    return nil
end


--主机上的中断引脚处理函数
local function gpio_int_callback()
    log.info("gpio_int_callback")
    sys.publish("AirGPIO_1000_INT")
end

sys.subscribe("AirGPIO_1000_INT", function()
    if AirGPIO_1000.ints then
        for k,v in pairs(AirGPIO_1000.ints) do
            if v then
                local cur_level = AirGPIO_1000.get(k)
                if v.old_level~=cur_level then
                    v.old_level = cur_level
                    if v.cb_func then v.cb_func(k, cur_level==1 and gpio.RISING or gpio.FALLING) end
                end
            end
        end
    end
end)

--检查AirGPIO_1000上的扩展GPIO ID是否有效

--gpio_id：number类型；
--         表示AirGPIO_1000上的扩展GPIO ID；
--         取值范围：0x00到0x07，0x10到0x17，一共16种，分别对应16个扩展GPIO引脚；
--         必须传入，不允许为空；

--返回值：有效返回true，无效返回false
local function check_gpio_id_valid(gpio_id)
    return (gpio_id>=0x00 and gpio_id<=0x07 or gpio_id>=0x10 and gpio_id<=0x17)
end

--配置主机和AirGPIO_1000之间的通信参数；

--i2c_id：number类型；
--        主机使用的I2C ID，用来控制AirGPIO_1000；
--        取值范围：仅支持0和1；
--        如果没有传入此参数，则默认为0；
--int_id：number类型；
--        主机使用的中断引脚GPIO ID，和AirGPIO_1000上的INT引脚相连；
--        AirGPIO_1000可以扩展出来16个GPIO，这些GPIO支持配置为输入；
--        AirGPIO_1000上的任意一个输入GPIO的状态发生上升沿或者下降沿变化时，会通过INT引脚通知到主机的int_id中断引脚；
--        此时主机可以通过I2C接口立即读取AirGPIO_1000上配置为输入模式的扩展GPIO的电平状态，从而判断是哪些扩展GPIO的输入电平发生了变化；
--        取值范围：nil或者空，或者0到9，或者12到55，注意不要使用已经复用为其他功能的引脚；nil或者空时，表示不使用中断通知功能；
--        如果没有传入此参数，则默认为空，表示不使用中断通知功能；

--返回值：成功返回true，失败返回false
function AirGPIO_1000.init(i2c_id, gpio_int_id)
    if not (i2c_id == 0 or i2c_id == 1) then
        log.error("AirGPIO_1000.init", "invalid i2c_id", i2c_id)
        return false
    end

    if not (gpio_int_id==nil or gpio_int_id>=0 and gpio_int_id<=9 or gpio_int_id>=12 and gpio_int_id<=55) then
        log.error("AirGPIO_1000.init", "invalid gpio_int_id", gpio_int_id)
        return false
    end

    AirGPIO_1000.i2c_id = i2c_id
    AirGPIO_1000.gpio_int_id = gpio_int_id

    if i2c.setup(i2c_id, i2c.FAST) ~= 1 then
        log.error("AirGPIO_1000.init", "i2c.setup error", i2c_id)
        return false
    end

    --自动识别从设备地址
    --AirGPIO_1000上使用的TCA9555芯片有三个引脚，A2 A1 A0，可以配置三个bit的I2C从设备地址
    --从 0 0 0 到 1 1 1，一共可以配置8种；
    for i=0,7 do
        i2c.send(i2c_id, SALVE_ADDRESS_HIGH_4BIT+i, REG_INPUT_PORT_0)
        local data = i2c.recv(i2c_id, SALVE_ADDRESS_HIGH_4BIT+i, 1)
        if data~=nil then
            AirGPIO_1000.slave_address = SALVE_ADDRESS_HIGH_4BIT+i
            log.error("AirGPIO_1000.init", "slave_address", SALVE_ADDRESS_HIGH_4BIT+i, data:byte())
            break
        end
    end

    if not AirGPIO_1000.slave_address then
        log.error("AirGPIO_1000.init", "slave_address unknown")
        i2c.close(i2c_id)
        return false
    end

    if gpio_int_id then
        gpio.setup(gpio_int_id, gpio_int_callback, gpio.PULLUP, gpio.FALLING)
    end

    return true
end

--关闭主机和AirGPIO_1000之间的通信；

--返回值：成功返回true，失败返回false
function AirGPIO_1000.deinit()
    if AirGPIO_1000.i2c_id then
        i2c.close(AirGPIO_1000.i2c_id)
        AirGPIO_1000.i2c_id = nil
        AirGPIO_1000.slave_address = nil
    end

    if AirGPIO_1000.gpio_int_id then
        gpio.close(AirGPIO_1000.gpio_int_id)
        AirGPIO_1000.gpio_int_id = nil
    end

    if type(AirGPIO_1000.ints)=="table" then
        for k,v in pairs(AirGPIO_1000.ints) do
            AirGPIO_1000.ints[k] = nil
        end        
        AirGPIO_1000.ints = nil
    end
end


--配置AirGPIO_1000上的扩展GPIO管脚功能

--gpio_id：number类型；
--         表示AirGPIO_1000上的扩展GPIO ID；
--         取值范围：0x00到0x07，0x10到0x17，一共16种，分别对应16个扩展GPIO引脚；
--         必须传入，不允许为空；
--gpio_mode：number类型，nil或者空类型，function类型；
--           number类型时，表示输出模式，取值范围为0和1，0表示默认输出低电平，1表示默认输出高电平；
--           nil或者空类型时，表示输入模式；
--           function类型时，表示中断模式，此function为中断回调函数，函数的定义格式如下：
--                           function cb_func(id, level)
--                               --id：表示触发中断的AirGPIO_1000上的扩展GPIO ID，取值范围为0x00到0x07，0x10到0x17，一共16种，分别对应16个扩展GPIO引脚；
--                               --level：表示触发中断类型，上升沿触发为gpio.RISING，下降沿触发为gpio.FALLING
--                           end

--返回值：成功返回true，失败返回false
function AirGPIO_1000.setup(gpio_id, gpio_mode)
    if not check_gpio_id_valid(gpio_id) then
        log.error("AirGPIO_1000.setup", "invalid gpio_id", gpio_id)
        return false
    end

    if not (gpio_mode==0 or gpio_mode==1 or gpio_mode==nil or type(gpio_mode)=="function") then
        log.error("AirGPIO_1000.setup", "invalid gpio_mode", type(gpio_mode), gpio_mode)
        return false
    end    

    log.info("AirGPIO_1000.setup", "enter", gpio_id, type(gpio_mode), gpio_mode)



    local reg_addr = ((gpio_id>>4) == 0) and REG_CONFIG_0 or REG_CONFIG_1
    local reg_data = read_register(reg_addr)

    if reg_data==nil then
        log.error("AirGPIO_1000.setup", "read config register error", reg_addr)
        return false
    end    

    local mask = 1<<(gpio_id&0x0F)
    local value
    if gpio_mode==0 or gpio_mode==1 then
        value = reg_data & (~mask)
    elseif gpio_mode==nil or type(gpio_mode)=="function" then
        value = reg_data | mask
    end

    if reg_data~=value then
        if not write_register(reg_addr, value) then
            log.error("AirGPIO_1000.setup", "config write error", reg_addr, value)
            return false
        end
    end

    log.info("AirGPIO_1000.setup", "config", reg_addr, reg_data, value)

    if type(gpio_mode)=="function" then
        if AirGPIO_1000.ints==nil then
            AirGPIO_1000.ints = {}
        end
        if AirGPIO_1000.ints[gpio_id]==nil then
            AirGPIO_1000.ints[gpio_id] = {}
        end
        AirGPIO_1000.ints[gpio_id].cb_func = gpio_mode
        AirGPIO_1000.ints[gpio_id].old_level = AirGPIO_1000.get(gpio_id)
    end

    if gpio_mode~=0 and gpio_mode~=1 then return true end



    -- reg_addr = ((gpio_id>>4) == 0) and REG_OUTPUT_PORT_0 or REG_OUTPUT_PORT_1
    -- reg_data = read_register(reg_addr)

    -- if reg_data==nil then
    --     log.error("AirGPIO_1000.setup", "read output register error", reg_addr)
    --     return false
    -- end    

    -- mask = 1<<(gpio_id&0x0F)

    -- if gpio_mode==0 then
    --     value = reg_data & (~mask)
    -- elseif gpio_mode==1 then
    --     value = reg_data | mask
    -- end

    -- if reg_data~=value then
    --     if not write_register(reg_addr, value) then
    --         log.error("AirGPIO_1000.setup", "output write error", reg_addr, value)
    --         return false
    --     end
    -- end

    if not AirGPIO_1000.set(gpio_id, gpio_mode) then
        log.error("AirGPIO_1000.setup", "output set error")
        return false
    end

    log.info("AirGPIO_1000.setup", "output", reg_addr, reg_data, value)

    return true    
end



--设置AirGPIO_1000上配置为输出模式的扩展GPIO的输出电平

--gpio_id：number类型；
--         表示AirGPIO_1000上的扩展GPIO ID；
--         取值范围：0x00到0x07，0x10到0x17，一共16种，分别对应16个扩展GPIO引脚；
--         必须传入，不允许为空；
--output_level：number类型；
--              表示配置为输出模式的扩展GPIO对外输出的电平；
--              取值范围：0和1，0表示输出低电平，1表示输出高电平；
--              必须传入，不允许为空；

--返回值：成功返回true，失败返回false
function AirGPIO_1000.set(gpio_id, output_level)
    if not check_gpio_id_valid(gpio_id) then
        log.error("AirGPIO_1000.set", "invalid gpio_id", gpio_id)
        return false
    end

    if not (output_level==0 or output_level==1) then
        log.error("AirGPIO_1000.set", "invalid output_level", type(output_level), output_level)
        return false
    end    

    log.info("AirGPIO_1000.set", "enter", gpio_id, output_level)

    local reg_addr = ((gpio_id>>4) == 0) and REG_OUTPUT_PORT_0 or REG_OUTPUT_PORT_1
    local reg_data = read_register(reg_addr)

    if reg_data==nil then
        log.error("AirGPIO_1000.set", "read output register error", reg_addr)
        return false
    end    

    local mask = 1<<(gpio_id&0x0F)
    local value

    if output_level==0 then
        value = reg_data & (~mask)
    elseif output_level==1 then
        value = reg_data | mask
    end

    if reg_data~=value then
        if not write_register(reg_addr, value) then
            log.error("AirGPIO_1000.set", "output write error", reg_addr, value)
            return false
        end
    end

    log.info("AirGPIO_1000.set", "output", reg_addr, reg_data, value)

    return true
end


--读取AirGPIO_1000上配置为输入或者中断模式的扩展GPIO的输入电平

--gpio_id：number类型；
--         表示AirGPIO_1000上的扩展GPIO ID；
--         取值范围：0x00到0x07，0x10到0x17，一共16种，分别对应16个扩展GPIO引脚；
--         必须传入，不允许为空；

--返回值：number类型，表示输入的电平，0表示低电平，1表示高电平；如果读取失败，返回nil
function AirGPIO_1000.get(gpio_id)
    if not check_gpio_id_valid(gpio_id) then
        log.error("AirGPIO_1000.get", "invalid gpio_id", gpio_id)
        return false
    end

    local reg_addr = ((gpio_id>>4) == 0) and REG_INPUT_PORT_0 or REG_INPUT_PORT_1
    local value = read_register(reg_addr)

    if not value then
        log.error("AirGPIO_1000.get", "read_register error", reg_addr)
        return nil
    end

    return ((value>>(gpio_id&0x0F)) & 0x01)
end



--关闭AirGPIO_1000上的扩展GPIO功能
--实际上是恢复为默认状态（配置为输入）

--gpio_id：number类型；
--         表示AirGPIO_1000上的扩展GPIO ID；
--         取值范围：0x00到0x07，0x10到0x17，一共16种，分别对应16个扩展GPIO引脚；
--         必须传入，不允许为空；

--返回值：成功返回true，失败返回false
function AirGPIO_1000.close(gpio_id)
    local result = AirGPIO_1000.setup(gpio_id)

    if not result then
        log.error("AirGPIO_1000.close", "error", gpio_id)
    end

    return result
end


return AirGPIO_1000
