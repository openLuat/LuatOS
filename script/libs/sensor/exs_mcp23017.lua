--[[
@module  exs_mcp23017
@summary MCP23017 16位 I2C GPIO 扩展芯片驱动扩展库
@version 1.0
@date    2026.07.30
@author  沈园园
@usage
本文件为 MCP23017 I2C GPIO 扩展芯片的 LuatOS 扩展库，核心功能为：
1、初始化 MCP23017，配置 I2C 通信参数，支持自动识别从设备地址；
2、16 个扩展 GPIO 管脚功能配置，支持输出、输入和中断三种模式；
3、支持上拉电阻配置、极性反转、中断使能等高级功能。

本文件的对外接口有 9 个：
1、exs_mcp23017.init(i2c_id, gpio_int_id)：初始化 MCP23017
2、exs_mcp23017.deinit()：关闭 MCP23017 通信
3、exs_mcp23017.setup(gpio_id, gpio_mode)：配置扩展 GPIO 管脚功能
4、exs_mcp23017.set(gpio_id, output_level)：设置输出电平
5、exs_mcp23017.get(gpio_id)：读取输入电平
6、exs_mcp23017.close(gpio_id)：关闭扩展 GPIO 功能
7、exs_mcp23017.set_pullup(gpio_id, enable)：配置上拉电阻
8、exs_mcp23017.set_polarity(gpio_id, invert)：设置极性反转
9、exs_mcp23017.version()：获取版本号

-- 版本更新说明
-- 版本号：202607301200
-- 1、更新时间：2026-07-30 12:00
-- 2、更新内容
  - 第一版，实现 MCP23017 基础驱动功能
  - 自动识别从设备地址功能（扫描 0x20~0x27）
  - 支持 16 个 GPIO 的输入、输出、中断配置
  - 支持上拉电阻配置
  - 支持极性反转
  - 支持中断模式（通过 INT 引脚 + sys.publish 机制）
]]

local exs_mcp23017 = {}

-- ==================== 模块常量 ====================

-- MCP23017 I2C 基地址（A0/A1/A2 全接地时）
-- 地址范围：0x20 ~ 0x27，A0A1A2 对应 000~111
local SLAVE_ADDRESS_BASE = 0x20

-- MCP23017 寄存器地址（Bank 0 模式）
local REG_IODIRA   = 0x00  -- 方向寄存器 A（1=输入，0=输出）
local REG_IODIRB   = 0x01  -- 方向寄存器 B
local REG_IPOLA    = 0x02  -- 极性反转 A
local REG_IPOLB    = 0x03  -- 极性反转 B
local REG_GPINTENA = 0x04  -- 中断使能 A
local REG_GPINTENB = 0x05  -- 中断使能 B
local REG_DEFVALA  = 0x06  -- 默认比较值 A
local REG_DEFVALB  = 0x07  -- 默认比较值 B
local REG_INTCONA  = 0x08  -- 中断控制 A
local REG_INTCONB  = 0x09  -- 中断控制 B
local REG_IOCON    = 0x0A  -- I/O 配置寄存器
local REG_GPPUA    = 0x0C  -- 上拉电阻 A
local REG_GPPUB    = 0x0D  -- 上拉电阻 B
local REG_INTFA    = 0x0E  -- 中断标志 A
local REG_INTFB    = 0x0F  -- 中断标志 B
local REG_INTCAPA  = 0x10  -- 中断捕获 A
local REG_INTCAPB  = 0x11  -- 中断捕获 B
local REG_GPIOA    = 0x12  -- 端口 A（读取引脚状态）
local REG_GPIOB    = 0x13  -- 端口 B
local REG_OLATA    = 0x14  -- 输出锁存 A
local REG_OLATB    = 0x15  -- 输出锁存 B

-- GPIO ID 有效范围
local GPIO_ID_PORT_A_MIN = 0x00
local GPIO_ID_PORT_A_MAX = 0x07
local GPIO_ID_PORT_B_MIN = 0x10
local GPIO_ID_PORT_B_MAX = 0x17

-- ==================== 内部状态 ====================

-- 运行时状态
exs_mcp23017.i2c_id       = nil    -- 主机 I2C ID
exs_mcp23017.gpio_int_id  = nil    -- 主机中断 GPIO ID（可选）
exs_mcp23017.slave_address = nil  -- 从设备地址
exs_mcp23017.ints         = nil    -- 中断处理表

-- ==================== I2C 底层操作 ====================

-- 写入 MCP23017 寄存器
-- @param reg 寄存器地址
-- @param value 要写入的数据
-- @return boolean 成功返回 true
local function write_register(reg, value)
    if not exs_mcp23017.i2c_id or not exs_mcp23017.slave_address then
        log.error("exs_mcp23017", "设备未初始化")
        return false
    end
    local result = i2c.send(exs_mcp23017.i2c_id, exs_mcp23017.slave_address, {reg, value})
    return result
end

-- 读取 MCP23017 寄存器
-- @param reg 寄存器地址
-- @return number 读取到的 1 字节数据，失败返回 nil
local function read_register(reg)
    if not exs_mcp23017.i2c_id or not exs_mcp23017.slave_address then
        log.error("exs_mcp23017", "设备未初始化")
        return nil
    end
    if not i2c.send(exs_mcp23017.i2c_id, exs_mcp23017.slave_address, reg) then
        return nil
    end
    local data = i2c.recv(exs_mcp23017.i2c_id, exs_mcp23017.slave_address, 1)
    if data and #data == 1 then
        return string.byte(data, 1)
    end
    return nil
end

-- ==================== 中断处理 ====================

-- 主机上的中断引脚处理函数
local function gpio_int_callback()
    -- 中断处理函数中不能直接执行耗时操作
    -- publish 消息后在其他位置异步处理
    sys.publish("exs_mcp23017_INT")
end

-- 遍历用户扩展 GPIO 中断函数表，进行处理
local function user_gpio_int_callback()
    if exs_mcp23017.ints then
        for k, v in pairs(exs_mcp23017.ints) do
            if v then
                -- 读取扩展 GPIO 当前输入电平
                local cur_level = exs_mcp23017.get(k)
                -- 输入电平发生变化时执行回调
                if v.old_level ~= cur_level then
                    v.old_level = cur_level
                    if v.cb_func then v.cb_func(k, cur_level) end
                end
            end
        end
    end
end

-- 订阅中断消息
sys.subscribe("exs_mcp23017_INT", user_gpio_int_callback)

-- ==================== GPIO ID 工具函数 ====================

-- 检查 GPIO ID 是否有效
-- @param gpio_id GPIO ID
-- @return boolean 有效返回 true
local function check_gpio_id_valid(gpio_id)
    return (gpio_id >= GPIO_ID_PORT_A_MIN and gpio_id <= GPIO_ID_PORT_A_MAX) or
           (gpio_id >= GPIO_ID_PORT_B_MIN and gpio_id <= GPIO_ID_PORT_B_MAX)
end

-- 根据 GPIO ID 获取对应的端口前缀
-- @param gpio_id GPIO ID
-- @return string "A" 或 "B"
local function get_port_prefix(gpio_id)
    return (gpio_id >> 4) == 0 and "A" or "B"
end

-- 根据 GPIO ID 获取对应的寄存器地址
-- @param gpio_id GPIO ID
-- @param reg_type 寄存器类型
-- @return number 寄存器地址
local function get_reg_addr(gpio_id, reg_type)
    local is_port_a = (gpio_id >> 4) == 0
    local reg_map = {
        config      = {[true] = REG_IODIRA,   [false] = REG_IODIRB},
        polarity    = {[true] = REG_IPOLA,    [false] = REG_IPOLB},
        interrupt   = {[true] = REG_GPINTENA, [false] = REG_GPINTENB},
        defval      = {[true] = REG_DEFVALA,  [false] = REG_DEFVALB},
        intcon      = {[true] = REG_INTCONA,  [false] = REG_INTCONB},
        pullup      = {[true] = REG_GPPUA,    [false] = REG_GPPUB},
        intf        = {[true] = REG_INTFA,     [false] = REG_INTFB},
        intcap      = {[true] = REG_INTCAPA,  [false] = REG_INTCAPB},
        input       = {[true] = REG_GPIOA,     [false] = REG_GPIOB},
        output      = {[true] = REG_OLATA,    [false] = REG_OLATB},
    }
    if reg_map[reg_type] then
        return reg_map[reg_type][is_port_a]
    end
    return nil
end

-- 根据 GPIO ID 获取位掩码
-- @param gpio_id GPIO ID
-- @return number 位掩码（0x01~0x80）
local function get_gpio_mask(gpio_id)
    return 1 << (gpio_id & 0x0F)
end

-- ==================== 外部 API ====================

--[[
初始化 MCP23017，配置 I2C 通信参数，自动识别从设备地址

@api exs_mcp23017.init(i2c_id, gpio_int_id)

i2c_id
参数含义：主机使用的 I2C ID，用来控制 MCP23017
数据类型：number
取值范围：仅支持 0 和 1
是否必选：必选

gpio_int_id
参数含义：主机使用的中断引脚 GPIO ID，与 MCP23017 的 INT 引脚相连；
MCP23017 上任意配置为输入模式的 GPIO 状态发生变化时，会通过 INT 引脚通知主机；
主机可通过 I2C 立即读取扩展 GPIO 电平状态，判断哪些 GPIO 电平发生了变化；
此参数可选，不传则不使用中断通知功能
数据类型：number
取值范围：GPIO 编号
是否必选：可选

@return boolean
初始化成功返回 true，失败返回 false

@usage
-- 基础初始化（不使用中断）
local result = exs_mcp23017.init(1)

-- 使用中断功能
local result = exs_mcp23017.init(1, 2)
]]
function exs_mcp23017.init(i2c_id, gpio_int_id)
    -- 参数检查
    if i2c_id ~= 0 and i2c_id ~= 1 then
        log.error("exs_mcp23017.init", "参数错误：i2c_id 应为 0 或 1")
        return false
    end

    exs_mcp23017.i2c_id = i2c_id
    exs_mcp23017.gpio_int_id = gpio_int_id

    -- 初始化 I2C
    if i2c.setup(i2c_id, i2c.FAST) ~= 1 then
        log.error("exs_mcp23017.init", "I2C 初始化失败", i2c_id)
        return false
    end

    -- 自动识别从设备地址
    -- MCP23017 的 A2 A1 A0 可配置 8 种地址（0x20 ~ 0x27）
    for i = 0, 7 do
        local addr = SLAVE_ADDRESS_BASE + i
        i2c.send(i2c_id, addr, REG_IODIRA)
        local data = i2c.recv(i2c_id, addr, 1)
        if data ~= nil then
            exs_mcp23017.slave_address = addr
            log.info("exs_mcp23017.init", "从设备地址识别成功:", addr)
            break
        end
    end

    -- 识别失败
    if not exs_mcp23017.slave_address then
        log.error("exs_mcp23017.init", "从设备地址识别失败")
        i2c.close(i2c_id)
        exs_mcp23017.i2c_id = nil
        return false
    end

    -- 配置 IOCON 寄存器（设置为 Bank 0 模式）
    -- MCP23017 默认是 Bank 0 模式，此处确保配置正确
    write_register(REG_IOCON, 0x00)

    -- 配置中断 GPIO（可选）
    if gpio_int_id then
        gpio.setup(gpio_int_id, gpio_int_callback, gpio.PULLUP, gpio.FALLING)
        log.info("exs_mcp23017.init", "中断 GPIO 已配置:", gpio_int_id)
    end

    log.info("exs_mcp23017.init", string.format("初始化完成, i2c=%d addr=0x%02X",
        i2c_id, exs_mcp23017.slave_address))

    return true
end

--[[
关闭 MCP23017 通信，释放所有资源（I2C、GPIO、中断表）

@api exs_mcp23017.deinit()

@return boolean
成功返回 true，失败返回 false

@usage
exs_mcp23017.deinit()
]]
function exs_mcp23017.deinit()
    -- 关闭 I2C
    if exs_mcp23017.i2c_id then
        i2c.close(exs_mcp23017.i2c_id)
        exs_mcp23017.i2c_id = nil
        exs_mcp23017.slave_address = nil
    end

    -- 关闭中断 GPIO
    if exs_mcp23017.gpio_int_id then
        gpio.close(exs_mcp23017.gpio_int_id)
        exs_mcp23017.gpio_int_id = nil
    end

    -- 清空中断处理表
    if type(exs_mcp23017.ints) == "table" then
        for k, v in pairs(exs_mcp23017.ints) do
            exs_mcp23017.ints[k] = nil
        end
        exs_mcp23017.ints = nil
    end

    log.info("exs_mcp23017.deinit", "已释放所有资源")
    return true
end

--[[
配置 MCP23017 扩展 GPIO 管脚功能，支持输出、输入和中断三种模式

@api exs_mcp23017.setup(gpio_id, gpio_mode)

gpio_id
参数含义：MCP23017 上的扩展 GPIO ID
数据类型：number
取值范围：
  - 0x00 ~ 0x07：端口 A 的 GPA0 ~ GPA7
  - 0x10 ~ 0x17：端口 B 的 GPB0 ~ GPB7
是否必选：必选

gpio_mode
参数含义：GPIO 工作模式，支持三种类型
数据类型：number | function | nil
取值说明：
  - number (0)：输出模式，默认输出低电平
  - number (1)：输出模式，默认输出高电平
  - nil 或不传：输入模式
  - function：中断模式，参数为回调函数
    回调函数格式：function cb_func(id, level) end
    - id：触发中断的 GPIO ID
    - level：触发中断后读取到的电平（0=低，1=高）
是否必选：必选

@return boolean
配置成功返回 true，失败返回 false

@usage
-- GPIO 0x00 配置为输出模式，默认输出低电平
exs_mcp23017.setup(0x00, 0)

-- GPIO 0x11 配置为输入模式
exs_mcp23017.setup(0x11)

-- GPIO 0x04 配置为中断模式
local function PA4_int_cbfunc(id, level)
    log.info("PA4_int_cbfunc", id, level)
end
exs_mcp23017.setup(0x04, PA4_int_cbfunc)
]]
function exs_mcp23017.setup(gpio_id, gpio_mode)
    -- 参数检查
    if not check_gpio_id_valid(gpio_id) then
        log.error("exs_mcp23017.setup", "参数错误：gpio_id 应为 0x00~0x07 或 0x10~0x17")
        return false
    end

    if gpio_mode ~= 0 and gpio_mode ~= 1 and gpio_mode ~= nil and type(gpio_mode) ~= "function" then
        log.error("exs_mcp23017.setup", "参数错误：gpio_mode 类型无效")
        return false
    end

    -- 获取方向寄存器地址
    local config_reg = get_reg_addr(gpio_id, "config")
    local reg_data = read_register(config_reg)

    if reg_data == nil then
        log.error("exs_mcp23017.setup", "读取方向寄存器失败", config_reg)
        return false
    end

    local mask = get_gpio_mask(gpio_id)
    local value

    -- 根据模式计算新的寄存器值
    if gpio_mode == 0 or gpio_mode == 1 then
        -- 输出模式：对应位清零（0=输出）
        value = reg_data & (~mask)
    else
        -- 输入模式或中断模式：对应位置1（1=输入）
        value = reg_data | mask
    end

    -- 配置值变化时写入寄存器
    if reg_data ~= value then
        if not write_register(config_reg, value) then
            log.error("exs_mcp23017.setup", "写入方向寄存器失败", config_reg, value)
            return false
        end
    end

    -- 中断模式：注册回调函数并启用中断
    if type(gpio_mode) == "function" then
        if exs_mcp23017.ints == nil then
            exs_mcp23017.ints = {}
        end
        if exs_mcp23017.ints[gpio_id] == nil then
            exs_mcp23017.ints[gpio_id] = {}
        end
        exs_mcp23017.ints[gpio_id].cb_func = gpio_mode
        exs_mcp23017.ints[gpio_id].old_level = exs_mcp23017.get(gpio_id)

        -- 启用该引脚的中断使能
        local int_reg = get_reg_addr(gpio_id, "interrupt")
        local int_data = read_register(int_reg)
        if int_data then
            write_register(int_reg, int_data | mask)
        end

        -- 配置中断控制（与 DEFVAL 寄存器比较）
        local intcon_reg = get_reg_addr(gpio_id, "intcon")
        local intcon_data = read_register(intcon_reg)
        if intcon_data then
            write_register(intcon_reg, intcon_data | mask)
        end
    end

    -- 输入/中断模式到此返回
    if gpio_mode ~= 0 and gpio_mode ~= 1 then
        return true
    end

    -- 输出模式：设置初始电平
    if not exs_mcp23017.set(gpio_id, gpio_mode) then
        log.error("exs_mcp23017.setup", "设置输出电平失败")
        return false
    end

    return true
end

--[[
设置 MCP23017 扩展 GPIO 的输出电平

@api exs_mcp23017.set(gpio_id, output_level)

gpio_id
参数含义：MCP23017 上的扩展 GPIO ID
数据类型：number
取值范围：0x00~0x07 或 0x10~0x17
是否必选：必选

output_level
参数含义：输出电平
数据类型：number
取值范围：0（低电平）或 1（高电平）
是否必选：必选

@return boolean
设置成功返回 true，失败返回 false

@usage
-- GPIO 0x03 输出高电平
exs_mcp23017.set(0x03, 1)

-- GPIO 0x13 输出低电平
exs_mcp23017.set(0x13, 0)
]]
function exs_mcp23017.set(gpio_id, output_level)
    -- 参数检查
    if not check_gpio_id_valid(gpio_id) then
        log.error("exs_mcp23017.set", "参数错误：gpio_id 无效")
        return false
    end

    if output_level ~= 0 and output_level ~= 1 then
        log.error("exs_mcp23017.set", "参数错误：output_level 应为 0 或 1")
        return false
    end

    -- 获取输出锁存寄存器地址
    local output_reg = get_reg_addr(gpio_id, "output")
    local reg_data = read_register(output_reg)

    if reg_data == nil then
        log.error("exs_mcp23017.set", "读取输出锁存寄存器失败", output_reg)
        return false
    end

    local mask = get_gpio_mask(gpio_id)
    local value

    if output_level == 0 then
        value = reg_data & (~mask)
    else
        value = reg_data | mask
    end

    -- 值变化时写入
    if reg_data ~= value then
        if not write_register(output_reg, value) then
            log.error("exs_mcp23017.set", "写入输出锁存寄存器失败", output_reg, value)
            return false
        end
    end

    return true
end

--[[
读取 MCP23017 扩展 GPIO 的输入电平

@api exs_mcp23017.get(gpio_id)

gpio_id
参数含义：MCP23017 上的扩展 GPIO ID
数据类型：number
取值范围：0x00~0x07 或 0x10~0x17
是否必选：必选

@return number
输入电平：0=低电平，1=高电平；读取失败返回 false

@usage
-- 读取 GPIO 0x11 的输入电平
local level = exs_mcp23017.get(0x11)
if level ~= false then
    log.info("MCP23017", "GPIO 0x11 电平:", level)
end
]]
function exs_mcp23017.get(gpio_id)
    -- 参数检查
    if not check_gpio_id_valid(gpio_id) then
        log.error("exs_mcp23017.get", "参数错误：gpio_id 无效")
        return false
    end

    -- 获取端口寄存器地址（读取实际引脚状态）
    local input_reg = get_reg_addr(gpio_id, "input")
    local value = read_register(input_reg)

    if value == nil then
        log.error("exs_mcp23017.get", "读取端口寄存器失败", input_reg)
        return false
    end

    -- 返回对应位的值
    return (value >> (gpio_id & 0x0F)) & 0x01
end

--[[
关闭 MCP23017 扩展 GPIO 功能，恢复为默认输入模式

@api exs_mcp23017.close(gpio_id)

gpio_id
参数含义：MCP23017 上的扩展 GPIO ID
数据类型：number
取值范围：0x00~0x07 或 0x10~0x17
是否必选：必选

@return boolean
关闭成功返回 true，失败返回 false

@usage
exs_mcp23017.close(0x03)
]]
function exs_mcp23017.close(gpio_id)
    local result = exs_mcp23017.setup(gpio_id)
    if not result then
        log.error("exs_mcp23017.close", "关闭失败", gpio_id)
    end
    return result
end

--[[
配置 MCP23017 扩展 GPIO 的上拉电阻

MCP23017 内置可选的上拉电阻（典型值 100kΩ），启用后可减少外部上拉电阻需求。

@api exs_mcp23017.set_pullup(gpio_id, enable)

gpio_id
参数含义：MCP23017 上的扩展 GPIO ID
数据类型：number
取值范围：0x00~0x07 或 0x10~0x17
是否必选：必选

enable
参数含义：是否启用内部上拉电阻
数据类型：boolean
取值范围：true（启用）、false（禁用）
是否必选：必选

@return boolean
设置成功返回 true，失败返回 false

@usage
-- 启用 GPIO 0x02 的内部上拉电阻
exs_mcp23017.set_pullup(0x02, true)

-- 禁用 GPIO 0x02 的内部上拉电阻
exs_mcp23017.set_pullup(0x02, false)
]]
function exs_mcp23017.set_pullup(gpio_id, enable)
    if not check_gpio_id_valid(gpio_id) then
        log.error("exs_mcp23017.set_pullup", "参数错误：gpio_id 无效")
        return false
    end

    local pullup_reg = get_reg_addr(gpio_id, "pullup")
    local reg_data = read_register(pullup_reg)

    if reg_data == nil then
        log.error("exs_mcp23017.set_pullup", "读取上拉寄存器失败", pullup_reg)
        return false
    end

    local mask = get_gpio_mask(gpio_id)
    local value

    if enable then
        value = reg_data | mask
    else
        value = reg_data & (~mask)
    end

    if reg_data ~= value then
        if not write_register(pullup_reg, value) then
            log.error("exs_mcp23017.set_pullup", "写入上拉寄存器失败", pullup_reg, value)
            return false
        end
    end

    return true
end

--[[
设置 MCP23017 扩展 GPIO 的极性反转

极性反转后，引脚实际为高电平时读取为 0，实际为低电平时读取为 1。
适用于需要反相读取的硬件设计场景。

@api exs_mcp23017.set_polarity(gpio_id, invert)

gpio_id
参数含义：MCP23017 上的扩展 GPIO ID
数据类型：number
取值范围：0x00~0x07 或 0x10~0x17
是否必选：必选

invert
参数含义：是否反转极性
数据类型：boolean
取值范围：true（反转）、false（正常）
是否必选：必选

@return boolean
设置成功返回 true，失败返回 false

@usage
-- 反转 GPIO 0x02 的极性
exs_mcp23017.set_polarity(0x02, true)

-- 恢复正常极性
exs_mcp23017.set_polarity(0x02, false)
]]
function exs_mcp23017.set_polarity(gpio_id, invert)
    if not check_gpio_id_valid(gpio_id) then
        log.error("exs_mcp23017.set_polarity", "参数错误：gpio_id 无效")
        return false
    end

    local polarity_reg = get_reg_addr(gpio_id, "polarity")
    local reg_data = read_register(polarity_reg)

    if reg_data == nil then
        log.error("exs_mcp23017.set_polarity", "读取极性寄存器失败", polarity_reg)
        return false
    end

    local mask = get_gpio_mask(gpio_id)
    local value

    if invert then
        value = reg_data | mask
    else
        value = reg_data & (~mask)
    end

    if reg_data ~= value then
        if not write_register(polarity_reg, value) then
            log.error("exs_mcp23017.set_polarity", "写入极性寄存器失败", polarity_reg, value)
            return false
        end
    end

    return true
end

--[[
获取 exs_mcp23017 库的版本号

@api exs_mcp23017.version()

@return string
版本号字符串，格式为 "yyyymmddhhmm"

@usage
local ver = exs_mcp23017.version()
log.info("exs_mcp23017", "版本号:", ver)
]]
function exs_mcp23017.version()
    return "202607301200"
end

log.debug("exs_mcp23017", "version -> " .. exs_mcp23017.version())

return exs_mcp23017