--[[
@module  exs_pcf8574
@summary PCF8574 8位 I2C GPIO 扩展芯片驱动扩展库
@version 1.0
@date    2026.07.31
@author  沈园园
@usage
本文件为 PCF8574 I2C GPIO 扩展芯片的 LuatOS 扩展库，核心业务逻辑为：
1、配置主机和 PCF8574 之间的 I2C 通信参数，支持自动识别从设备地址；
2、配置 PCF8574 上 8 个扩展 GPIO 管脚功能；支持配置为输出、输入和中断三种模式；
3、支持批量读写所有 GPIO 端口数据。

本文件的对外接口有 9 个：
1、exs_pcf8574.init(i2c_id, gpio_int_id)：初始化 PCF8574
2、exs_pcf8574.deinit()：关闭 PCF8574 通信
3、exs_pcf8574.setup(gpio_id, gpio_mode)：配置扩展 GPIO 管脚功能
4、exs_pcf8574.set(gpio_id, output_level)：设置输出电平
5、exs_pcf8574.get(gpio_id)：读取输入电平
6、exs_pcf8574.close(gpio_id)：关闭扩展 GPIO 功能
7、exs_pcf8574.read_all()：读取所有 GPIO 端口数据
8、exs_pcf8574.write_all(data)：写入所有 GPIO 端口数据
9、exs_pcf8574.version()：获取版本号

-- 版本更新说明
-- 版本号：202607311200
-- 1、更新时间：2026-07-31 12:00
-- 2、更新内容
  - 第一版，实现 PCF8574 基础驱动功能
  - 自动识别从设备地址功能（扫描 0x20~0x27）
  - 支持 8 个 GPIO 的输入、输出、中断配置
  - 支持批量读写端口数据
  - 支持 GPIO 中断模式（通过 INT 引脚 + sys.publish 机制）
  - 支持准双向 IO 模式（无需单独配置方向）
]]

local exs_pcf8574 = {}

-- ==================== 模块常量 ====================

-- PCF8574 I2C 基地址（A0/A1/A2 全接地时）
-- 地址范围：0x20 ~ 0x27，A0A1A2 对应 000~111
local SLAVE_ADDRESS_BASE = 0x20

-- PCF8574 寄存器地址（仅 2 个寄存器）
local REG_INPUT   = 0x00  -- 输入寄存器（只读，读取引脚实际状态）
local REG_OUTPUT  = 0x01  -- 输出寄存器（写入控制输出状态）

-- GPIO ID 有效范围
local GPIO_ID_MIN = 0x00
local GPIO_ID_MAX = 0x07

-- GPIO 模式定义
local MODE_OUTPUT_LOW  = 0   -- 输出低电平（引脚拉低）
local MODE_OUTPUT_HIGH = 1   -- 输出高电平（引脚高阻 + 内部上拉）
local MODE_INPUT       = nil -- 输入模式（内部上拉，外部驱动）

-- ==================== 内部状态 ====================

-- 运行时状态
exs_pcf8574.i2c_id       = nil    -- 主机 I2C ID
exs_pcf8574.gpio_int_id  = nil    -- 主机中断 GPIO ID（可选）
exs_pcf8574.slave_address = nil  -- 从设备地址
exs_pcf8574.ints         = nil    -- 中断处理表

-- 输出寄存器缓存（用于减少 I2C 读取次数）
exs_pcf8574.output_cache = 0xFF  -- 初始值：全部为 1（输入模式）

-- ==================== I2C 底层操作 ====================

-- 写入 PCF8574 输出寄存器
-- @param value 要写入的数据（0x00~0xFF）
-- @return boolean 成功返回 true
local function write_output(value)
    if not exs_pcf8574.i2c_id or not exs_pcf8574.slave_address then
        log.error("exs_pcf8574", "设备未初始化")
        return false
    end
    local result = i2c.send(exs_pcf8574.i2c_id, exs_pcf8574.slave_address, value)
    if result then
        exs_pcf8574.output_cache = value
    end
    return result
end

-- 读取 PCF8574 输入寄存器
-- @return number 读取到的 1 字节数据，失败返回 nil
local function read_input()
    if not exs_pcf8574.i2c_id or not exs_pcf8574.slave_address then
        log.error("exs_pcf8574", "设备未初始化")
        return nil
    end

    local data = i2c.recv(exs_pcf8574.i2c_id, exs_pcf8574.slave_address, 1)
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
    sys.publish("exs_pcf8574_INT")   
end

-- 遍历用户扩展 GPIO 中断函数表，进行处理
local function user_gpio_int_callback()
    if exs_pcf8574.ints then
        for k, v in pairs(exs_pcf8574.ints) do
            if v then
                -- 读取扩展 GPIO 当前输入电平
                local cur_level = exs_pcf8574.get(k) 
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
sys.subscribe("exs_pcf8574_INT", user_gpio_int_callback)

-- ==================== GPIO ID 工具函数 ====================

-- 检查 GPIO ID 是否有效
-- @param gpio_id GPIO ID
-- @return boolean 有效返回 true
local function check_gpio_id_valid(gpio_id)
    return (gpio_id >= GPIO_ID_MIN and gpio_id <= GPIO_ID_MAX)
end

-- 根据 GPIO ID 获取位掩码
-- @param gpio_id GPIO ID (0x00~0x07)
-- @return number 位掩码（0x01~0x80）
local function get_gpio_mask(gpio_id)
    return 1 << (gpio_id & 0x07)
end

-- ==================== 外部 API ====================

--[[
初始化 PCF8574，配置 I2C 通信参数，自动识别从设备地址

@api exs_pcf8574.init(i2c_id, gpio_int_id)

i2c_id
参数含义：主机使用的 I2C ID，用来控制 PCF8574
数据类型：number
取值范围：仅支持 0 和 1
是否必选：必选

gpio_int_id
参数含义：主机使用的中断引脚 GPIO ID，与 PCF8574 的 INT 引脚相连；
PCF8574 上任意配置为输入模式的 GPIO 状态发生变化时，会通过 INT 引脚通知主机；
主机可通过 I2C 立即读取扩展 GPIO 电平状态，判断哪些 GPIO 电平发生了变化；
此参数可选，不传则不使用中断通知功能
数据类型：number
取值范围：GPIO 编号
是否必选：可选

@return boolean
初始化成功返回 true，失败返回 false

@usage
-- 基础初始化（不使用中断）
local result = exs_pcf8574.init(1)

-- 使用中断功能
local result = exs_pcf8574.init(1, 2)
]]
function exs_pcf8574.init(i2c_id, gpio_int_id)
    -- 参数检查
    if i2c_id ~= 0 and i2c_id ~= 1 then
        log.error("exs_pcf8574.init", "参数错误：i2c_id 应为 0 或 1")
        return false
    end

    exs_pcf8574.i2c_id = i2c_id
    exs_pcf8574.gpio_int_id = gpio_int_id

    -- 初始化 I2C
    if i2c.setup(i2c_id, i2c.FAST) ~= 1 then
        log.error("exs_pcf8574.init", "I2C 初始化失败", i2c_id)
        return false
    end

    -- 自动识别从设备地址
    -- PCF8574 的 A2 A1 A0 可配置 8 种地址（0x20 ~ 0x27）
    for i = 0, 7 do
        local addr = SLAVE_ADDRESS_BASE + i
        i2c.send(i2c_id, addr, REG_INPUT)
        local data = i2c.recv(i2c_id, addr, 1)
        if data ~= nil then
            exs_pcf8574.slave_address = addr
            log.info("exs_pcf8574.init", "从设备地址识别成功:", addr)
            break
        end
    end

    -- 识别失败
    if not exs_pcf8574.slave_address then
        log.error("exs_pcf8574.init", "从设备地址识别失败")
        i2c.close(i2c_id)
        exs_pcf8574.i2c_id = nil
        return false
    end

    -- 初始化输出寄存器缓存为 0xFF（全部输入模式，内部上拉）
    write_output(0xFF)

    -- 配置中断 GPIO（可选）
    if gpio_int_id then
        gpio.setup(gpio_int_id, gpio_int_callback, gpio.PULLUP, gpio.FALLING)
        log.info("exs_pcf8574.init", "中断 GPIO 已配置:", gpio_int_id)
    end

    log.info("exs_pcf8574.init", string.format("初始化完成, i2c=%d addr=0x%02X",
        i2c_id, exs_pcf8574.slave_address))

    return true
end

--[[
关闭 PCF8574 通信，释放所有资源（I2C、GPIO、中断表）

@api exs_pcf8574.deinit()

@return boolean
成功返回 true，失败返回 false

@usage
exs_pcf8574.deinit()
]]
function exs_pcf8574.deinit()
    -- 关闭 I2C
    if exs_pcf8574.i2c_id then
        i2c.close(exs_pcf8574.i2c_id)
        exs_pcf8574.i2c_id = nil
        exs_pcf8574.slave_address = nil
    end

    -- 关闭中断 GPIO
    if exs_pcf8574.gpio_int_id then
        gpio.close(exs_pcf8574.gpio_int_id)
        exs_pcf8574.gpio_int_id = nil
    end

    -- 清空中断处理表
    if type(exs_pcf8574.ints) == "table" then
        for k, v in pairs(exs_pcf8574.ints) do
            exs_pcf8574.ints[k] = nil
        end
        exs_pcf8574.ints = nil
    end

    -- 重置输出缓存
    exs_pcf8574.output_cache = 0xFF

    log.info("exs_pcf8574.deinit", "已释放所有资源")
    return true
end

--[[
配置 PCF8574 扩展 GPIO 管脚功能，支持输出、输入和中断三种模式

@api exs_pcf8574.setup(gpio_id, gpio_mode)

gpio_id
参数含义：PCF8574 上的扩展 GPIO ID
数据类型：number
取值范围：0x00 ~ 0x07，对应 P0 ~ P7
是否必选：必选

gpio_mode
参数含义：GPIO 工作模式，支持三种类型
数据类型：number | function | nil
取值说明：
  - number (0)：输出模式，输出低电平
  - number (1)：输出模式，输出高电平（准双向，内部上拉）
  - nil 或不传：输入模式（内部上拉，外部驱动）
  - function：中断模式，参数为回调函数
    回调函数格式：function cb_func(id, level) end
    - id：触发中断的 GPIO ID
    - level：触发中断后读取到的电平（0=低，1=高）
是否必选：必选

@return boolean
配置成功返回 true，失败返回 false

@usage
-- GPIO 0x00 配置为输出模式，输出低电平
exs_pcf8574.setup(0x00, 0)

-- GPIO 0x01 配置为输入模式
exs_pcf8574.setup(0x01)

-- GPIO 0x04 配置为中断模式
local function P04_int_cbfunc(id, level)
    log.info("P04_int_cbfunc", id, level)
end
exs_pcf8574.setup(0x04, P04_int_cbfunc)
]]
function exs_pcf8574.setup(gpio_id, gpio_mode)
    -- 参数检查
    if not check_gpio_id_valid(gpio_id) then
        log.error("exs_pcf8574.setup", "参数错误：gpio_id 应为 0x00~0x07")
        return false
    end

    if gpio_mode ~= 0 and gpio_mode ~= 1 and gpio_mode ~= nil and type(gpio_mode) ~= "function" then
        log.error("exs_pcf8574.setup", "参数错误：gpio_mode 类型无效")
        return false
    end

    local mask = get_gpio_mask(gpio_id)
    local new_output = exs_pcf8574.output_cache

    -- 根据模式计算新的输出寄存器值
    if gpio_mode == 0 then
        -- 输出低电平：对应位清零（引脚拉低）
        new_output = new_output & (~mask)
    elseif gpio_mode == 1 then
        -- 输出高电平：对应位置1（准双向，内部上拉）
        new_output = new_output | mask
    else
        -- 输入模式或中断模式：对应位置1（准双向，内部上拉）
        new_output = new_output | mask
    end

    -- 值变化时写入
    if new_output ~= exs_pcf8574.output_cache then
        if not write_output(new_output) then
            log.error("exs_pcf8574.setup", "写入输出寄存器失败")
            return false
        end
    end

    -- 中断模式：注册回调函数
    if type(gpio_mode) == "function" then
        if exs_pcf8574.ints == nil then
            exs_pcf8574.ints = {}
        end
        if exs_pcf8574.ints[gpio_id] == nil then
            exs_pcf8574.ints[gpio_id] = {}
        end
        exs_pcf8574.ints[gpio_id].cb_func = gpio_mode
        exs_pcf8574.ints[gpio_id].old_level = exs_pcf8574.get(gpio_id)
    end

    return true
end

--[[
设置 PCF8574 扩展 GPIO 的输出电平

@api exs_pcf8574.set(gpio_id, output_level)

gpio_id
参数含义：PCF8574 上的扩展 GPIO ID
数据类型：number
取值范围：0x00~0x07
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
exs_pcf8574.set(0x03, 1)

-- GPIO 0x05 输出低电平
exs_pcf8574.set(0x05, 0)
]]
function exs_pcf8574.set(gpio_id, output_level)
    -- 参数检查
    if not check_gpio_id_valid(gpio_id) then
        log.error("exs_pcf8574.set", "参数错误：gpio_id 无效")
        return false
    end

    if output_level ~= 0 and output_level ~= 1 then
        log.error("exs_pcf8574.set", "参数错误：output_level 应为 0 或 1")
        return false
    end

    local mask = get_gpio_mask(gpio_id)
    local new_output

    if output_level == 0 then
        new_output = exs_pcf8574.output_cache & (~mask)
    else
        new_output = exs_pcf8574.output_cache | mask
    end

    -- 值变化时写入
    if new_output ~= exs_pcf8574.output_cache then
        if not write_output(new_output) then
            log.error("exs_pcf8574.set", "写入输出寄存器失败")
            return false
        end
    end

    return true
end

--[[
读取 PCF8574 扩展 GPIO 的输入电平

@api exs_pcf8574.get(gpio_id)

gpio_id
参数含义：PCF8574 上的扩展 GPIO ID
数据类型：number
取值范围：0x00~0x07
是否必选：必选

@return number
输入电平：0=低电平，1=高电平；读取失败返回 false

@usage
-- 读取 GPIO 0x02 的输入电平
local level = exs_pcf8574.get(0x02)
if level ~= false then
    log.info("PCF8574", "GPIO 0x02 电平:", level)
end
]]
function exs_pcf8574.get(gpio_id)
    -- 参数检查
    if not check_gpio_id_valid(gpio_id) then
        log.error("exs_pcf8574.get", "参数错误：gpio_id 无效")
        return false
    end

    -- 读取输入寄存器
    local value = read_input()

    if value == nil then
        log.error("exs_pcf8574.get", "读取输入寄存器失败")
        return false
    end

    -- 返回对应位的值
    return (value >> (gpio_id & 0x07)) & 0x01
end

--[[
关闭 PCF8574 扩展 GPIO 功能，恢复为默认输入模式

@api exs_pcf8574.close(gpio_id)

gpio_id
参数含义：PCF8574 上的扩展 GPIO ID
数据类型：number
取值范围：0x00~0x07
是否必选：必选

@return boolean
关闭成功返回 true，失败返回 false

@usage
exs_pcf8574.close(0x03)
]]
function exs_pcf8574.close(gpio_id)
    local result = exs_pcf8574.setup(gpio_id)
    if not result then
        log.error("exs_pcf8574.close", "关闭失败", gpio_id)
    end
    return result
end

--[[
读取 PCF8574 所有 GPIO 端口数据

@api exs_pcf8574.read_all()

@return number
8 位端口数据，每位对应一个 GPIO（bit0=P0, bit7=P7）；
读取失败返回 false

@usage
local port_data = exs_pcf8574.read_all()
if port_data ~= false then
    log.info("PCF8574", "端口数据:", string.format("0x%02X", port_data))
end
]]
function exs_pcf8574.read_all()
    local value = read_input()
    if value == nil then
        log.error("exs_pcf8574.read_all", "读取输入寄存器失败")
        return false
    end
    return value
end

--[[
写入 PCF8574 所有 GPIO 端口数据

@api exs_pcf8574.write_all(data)

data
参数含义：8 位端口数据，每位对应一个 GPIO（bit0=P0, bit7=P7）
数据类型：number
取值范围：0x00~0xFF
是否必选：必选

@return boolean
写入成功返回 true，失败返回 false

@usage
-- 设置 P0~P3 输出低，P4~P7 输出高
exs_pcf8574.write_all(0xF0)
]]
function exs_pcf8574.write_all(data)
    if data < 0x00 or data > 0xFF then
        log.error("exs_pcf8574.write_all", "参数错误：data 范围 0x00~0xFF")
        return false
    end

    if not write_output(data) then
        log.error("exs_pcf8574.write_all", "写入输出寄存器失败")
        return false
    end

    return true
end

--[[
获取 exs_pcf8574 库的版本号

@api exs_pcf8574.version()

@return string
版本号字符串，格式为 "yyyymmddhhmm"

@usage
local ver = exs_pcf8574.version()
log.info("exs_pcf8574", "版本号:", ver)
]]
function exs_pcf8574.version()
    return "202607311200"
end

log.debug("exs_pcf8574", "version -> " .. exs_pcf8574.version())

return exs_pcf8574