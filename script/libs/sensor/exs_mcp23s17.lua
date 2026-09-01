--[[
@module  exs_mcp23s17
@summary MCP23S17 16位 SPI GPIO 扩展芯片驱动扩展库
@version 1.0
@date    2026.08.24
@author  嵌入式软件设计开发代理
@usage
本文件为 MCP23S17 SPI GPIO 扩展芯片的 LuatOS 扩展库，核心功能为：
1、初始化 MCP23S17，配置 SPI 通信参数，支持硬件地址 A2A1A0（0~7）；
2、16 个扩展 GPIO 管脚功能配置，支持输出、输入和中断三种模式；
3、支持上拉电阻配置、极性反转、中断使能等高级功能。

本文件的对外接口有 9 个：
1、exs_mcp23s17.init(spi_id, cs_pin, gpio_int_id, bandrate, hw_addr)：初始化 MCP23S17
2、exs_mcp23s17.deinit()：关闭 MCP23S17 通信
3、exs_mcp23s17.setup(gpio_id, gpio_mode)：配置扩展 GPIO 管脚功能
4、exs_mcp23s17.set(gpio_id, output_level)：设置输出电平
5、exs_mcp23s17.get(gpio_id)：读取输入电平
6、exs_mcp23s17.close(gpio_id)：关闭扩展 GPIO 功能
7、exs_mcp23s17.set_pullup(gpio_id, enable)：配置上拉电阻
8、exs_mcp23s17.set_polarity(gpio_id, invert)：设置极性反转
9、exs_mcp23s17.version()：获取版本号

-- 版本更新说明
-- 版本号：202608241200
-- 1、更新时间：2026-08-24 12:00
-- 2、更新内容
  - 第一版，实现 MCP23S17 基础驱动功能
  - SPI 通信方式（与 MCP23017 的 I2C 方式不同，本库使用 SPI 总线）
  - 支持 16 个 GPIO 的输入、输出、中断配置
  - 支持硬件地址 A2A1A0（0~7）
  - 支持上拉电阻配置
  - 支持极性反转
  - 支持中断模式（通过 INT 引脚 + sys.publish 机制）
]]

local exs_mcp23s17 = {}

-- ==================== 模块常量 ====================

-- MCP23S17 SPI 控制字节（opcode）基地址
-- 控制字节格式：0b0100 A2 A1 A0 R/W
-- bit7~bit4：0100 固定；bit3~bit1：硬件地址 A2A1A0；bit0：读写位（0=写，1=读）
local OPCODE_WRITE_BASE = 0x40  -- 0100 A2 A1 A0 0（写操作）
local OPCODE_READ_BASE  = 0x41  -- 0100 A2 A1 A0 1（读操作）

-- MCP23S17 寄存器地址（Bank 0 模式，与 MCP23017 完全一致）
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

-- IOCON 寄存器位定义
local IOCON_HAEN_BIT = 0x08  -- bit3：硬件地址使能（MCP23S17 特有）

-- GPIO ID 有效范围
-- A 端口：0x00~0x07（GPA0~GPA7）
-- B 端口：0x10~0x17（GPB0~GPB7）
local GPIO_ID_PORT_A_MIN = 0x00
local GPIO_ID_PORT_A_MAX = 0x07
local GPIO_ID_PORT_B_MIN = 0x10
local GPIO_ID_PORT_B_MAX = 0x17

-- 默认 SPI 波特率（MCP23S17 最高支持 10MHz，默认 1MHz 兼容杜邦线连接）
local DEFAULT_BANDRATE = 1000000

-- ==================== 内部状态 ====================

-- 运行时状态
exs_mcp23s17.spi_id       = nil    -- 主机 SPI 总线 ID
exs_mcp23s17.cs_pin       = nil    -- 片选引脚 GPIO ID
exs_mcp23s17.cs_ctrl      = nil    -- 片选控制函数（gpio.setup 返回值）
exs_mcp23s17.gpio_int_id  = nil    -- 主机中断 GPIO ID（可选）
exs_mcp23s17.hw_addr      = 0      -- 硬件地址 A2A1A0（0~7）
exs_mcp23s17.bandrate     = DEFAULT_BANDRATE  -- SPI 波特率
exs_mcp23s17.ints         = nil    -- 中断处理表（key=gpio_id，value=回调函数）

-- ==================== SPI 底层操作 ====================

-- 获取写操作控制字节
-- @return number 写 opcode（0100A2A1A0 0）
local function get_write_opcode()
    return bit.bor(OPCODE_WRITE_BASE, bit.lshift(exs_mcp23s17.hw_addr, 1))
end

-- 获取读操作控制字节
-- @return number 读 opcode（0100A2A1A0 1）
local function get_read_opcode()
    return bit.bor(OPCODE_READ_BASE, bit.lshift(exs_mcp23s17.hw_addr, 1))
end

-- 写入 MCP23S17 寄存器
-- @param reg 寄存器地址
-- @param value 要写入的数据
-- @return boolean 成功返回 true
local function write_register(reg, value)
    if not exs_mcp23s17.spi_id or not exs_mcp23s17.cs_ctrl then
        log.error("exs_mcp23s17", "设备未初始化")
        return false
    end
    local opcode = get_write_opcode()
    exs_mcp23s17.cs_ctrl(0)
    local result = spi.send(exs_mcp23s17.spi_id, string.char(opcode, reg, value))
    exs_mcp23s17.cs_ctrl(1)
    if result then
        return true
    else
        log.error("exs_mcp23s17", "SPI 写寄存器失败", string.format("reg=0x%02X", reg))
        return false
    end
end

-- 读取 MCP23S17 寄存器
-- @param reg 寄存器地址
-- @return number 读取到的 1 字节数据，失败返回 nil
local function read_register(reg)
    if not exs_mcp23s17.spi_id or not exs_mcp23s17.cs_ctrl then
        log.error("exs_mcp23s17", "设备未初始化")
        return nil
    end
    local opcode = get_read_opcode()
    exs_mcp23s17.cs_ctrl(0)
    -- 发送 3 字节（读 opcode + 寄存器地址 + dummy），同时接收 3 字节
    -- MCP23S17 在收到 opcode 和地址后，第 3 个字节周期在 SO 上输出寄存器值
    local recv = spi.transfer(exs_mcp23s17.spi_id, string.char(opcode, reg, 0x00), 3, 3)
    exs_mcp23s17.cs_ctrl(1)
    if recv and #recv == 3 then
        return recv:byte(3)
    else
        log.error("exs_mcp23s17", "SPI 读寄存器失败", string.format("reg=0x%02X", reg))
        return nil
    end
end

-- ==================== 中断处理 ====================

-- GPIO 中断回调函数（INT 引脚下降沿触发）
-- 通过 sys.publish 发布中断消息，由订阅回调处理
local function gpio_int_callback()
    sys.publish("exs_mcp23s17_INT")
end

-- 中断分发回调函数（订阅 exs_mcp23s17_INT 消息）
-- 读取中断标志寄存器与捕获寄存器，定位触发引脚，分发用户回调
local function user_gpio_int_callback()
    -- 读取中断标志与捕获寄存器（读取 INTCAP 会自动清除中断标志）
    local intf_a = read_register(REG_INTFA)
    local intf_b = read_register(REG_INTFB)
    local cap_a = read_register(REG_INTCAPA)
    local cap_b = read_register(REG_INTCAPB)

    -- 分发 A 端口中断
    if intf_a then
        for i = 0, 7 do
            local mask = bit.lshift(1, i)
            if bit.band(intf_a, mask) > 0 then
                local gpio_id = i
                local level = 0
                if cap_a and bit.band(cap_a, mask) > 0 then
                    level = 1
                end
                local cb = exs_mcp23s17.ints and exs_mcp23s17.ints[gpio_id]
                if cb then
                    cb(gpio_id, level)
                else
                    log.warn("exs_mcp23s17", "A 端口中断无回调", gpio_id)
                end
            end
        end
    end

    -- 分发 B 端口中断
    if intf_b then
        for i = 0, 7 do
            local mask = bit.lshift(1, i)
            if bit.band(intf_b, mask) > 0 then
                local gpio_id = 0x10 + i
                local level = 0
                if cap_b and bit.band(cap_b, mask) > 0 then
                    level = 1
                end
                local cb = exs_mcp23s17.ints and exs_mcp23s17.ints[gpio_id]
                if cb then
                    cb(gpio_id, level)
                else
                    log.warn("exs_mcp23s17", "B 端口中断无回调", gpio_id)
                end
            end
        end
    end
end

-- ==================== GPIO ID 工具函数 ====================

-- 校验 GPIO ID 是否有效
-- @param gpio_id GPIO ID
-- @return boolean 有效返回 true
local function check_gpio_id_valid(gpio_id)
    if (gpio_id >= GPIO_ID_PORT_A_MIN and gpio_id <= GPIO_ID_PORT_A_MAX)
        or (gpio_id >= GPIO_ID_PORT_B_MIN and gpio_id <= GPIO_ID_PORT_B_MAX) then
        return true
    end
    log.error("exs_mcp23s17", "GPIO ID 无效", gpio_id)
    return false
end

-- 获取 GPIO ID 对应的端口标识
-- @param gpio_id GPIO ID
-- @return number 0=A 端口，1=B 端口
local function get_port_prefix(gpio_id)
    if gpio_id >= GPIO_ID_PORT_B_MIN then
        return 1
    else
        return 0
    end
end

-- 获取 GPIO ID 对应的寄存器地址
-- @param gpio_id GPIO ID
-- @param reg_type A 端口寄存器基地址（如 REG_IODIRA）
-- @return number 实际寄存器地址（B 端口时 +1）
local function get_reg_addr(gpio_id, reg_type)
    local port = get_port_prefix(gpio_id)
    return reg_type + port
end

-- 获取 GPIO ID 对应的位掩码
-- @param gpio_id GPIO ID
-- @return number 位掩码（1 << pin）
local function get_gpio_mask(gpio_id)
    local pin = bit.band(gpio_id, 0x0F)
    return bit.lshift(1, pin)
end

-- ==================== 对外 API ====================

-- 初始化 MCP23S17
-- @param spi_id SPI 总线 ID（0/1，Air780EHV 仅支持 SPI0）
-- @param cs_pin 片选引脚 GPIO ID
-- @param gpio_int_id 中断引脚 GPIO ID（可选，默认 nil）
-- @param bandrate SPI 波特率（可选，默认 1000000）
-- @param hw_addr 硬件地址 A2A1A0（可选，默认 0，范围 0~7）
-- @return boolean 初始化成功返回 true
function exs_mcp23s17.init(spi_id, cs_pin, gpio_int_id, bandrate, hw_addr)
    -- 参数默认值与校验
    bandrate = bandrate or DEFAULT_BANDRATE
    hw_addr = hw_addr or 0
    if hw_addr < 0 or hw_addr > 7 then
        log.error("exs_mcp23s17", "硬件地址无效（范围 0~7）", hw_addr)
        return false
    end
    if not spi_id or not cs_pin then
        log.error("exs_mcp23s17", "spi_id 和 cs_pin 不能为空")
        return false
    end

    -- 保存运行时状态
    exs_mcp23s17.spi_id = spi_id
    exs_mcp23s17.cs_pin = cs_pin
    exs_mcp23s17.gpio_int_id = gpio_int_id
    exs_mcp23s17.bandrate = bandrate
    exs_mcp23s17.hw_addr = hw_addr

    -- 初始化 SPI 总线（Mode 0：CPOL=0，CPHA=0；8 位数据；MSB 先行；全双工）
    -- cs 传 nil：片选由软件 GPIO 手动控制
    local spi_device = spi.setup(spi_id, nil, 0, 0, 8, bandrate, spi.MSB, spi.master, spi.full)
    if not spi_device then
        log.error("exs_mcp23s17", "SPI 初始化失败", spi_id)
        return false
    end

    -- 初始化片选引脚（默认输出高电平，释放片选）
    local cs_ctrl = gpio.setup(cs_pin, 1)
    if not cs_ctrl then
        log.error("exs_mcp23s17", "片选引脚初始化失败", cs_pin)
        return false
    end
    exs_mcp23s17.cs_ctrl = cs_ctrl

    -- 如果硬件地址非 0，需要先使能 IOCON 寄存器的 HAEN 位
    -- 注意：复位后 HAEN=0，芯片只响应地址 000，因此必须先以地址 000 访问
    if hw_addr > 0 then
        -- 临时使用地址 0 读取并修改 IOCON
        exs_mcp23s17.hw_addr = 0
        local iocon_value = read_register(REG_IOCON)
        if iocon_value then
            iocon_value = bit.bor(iocon_value, IOCON_HAEN_BIT)
            write_register(REG_IOCON, iocon_value)
            log.info("exs_mcp23s17", "已使能硬件地址 HAEN")
        else
            log.error("exs_mcp23s17", "读取 IOCON 寄存器失败")
            return false
        end
        -- 恢复实际硬件地址
        exs_mcp23s17.hw_addr = hw_addr
    end

    -- 验证芯片通信（读取 GPIOA 寄存器，能读到值说明通信正常）
    local verify = read_register(REG_GPIOA)
    if verify == nil then
        log.error("exs_mcp23s17", "芯片通信验证失败，请检查 SPI 接线与硬件地址")
        return false
    end

    -- 初始化中断回调表
    exs_mcp23s17.ints = {}

    -- 配置中断引脚（MCP23S17 INT 引脚为开漏输出，低有效，需上拉 + 下降沿触发）
    if gpio_int_id then
        gpio.setup(gpio_int_id, gpio_int_callback, gpio.PULLUP, gpio.FALLING)
        sys.subscribe("exs_mcp23s17_INT", user_gpio_int_callback)
        log.info("exs_mcp23s17", "中断引脚已配置", gpio_int_id)
    end

    log.info("exs_mcp23s17", "初始化成功", string.format("spi_id=%d cs_pin=%d hw_addr=%d bandrate=%d", spi_id, cs_pin, hw_addr, bandrate))
    return true
end

-- 关闭 MCP23S17
-- @return boolean 成功返回 true
function exs_mcp23s17.deinit()
    -- 取消中断消息订阅
    if exs_mcp23s17.gpio_int_id then
        sys.unsubscribe("exs_mcp23s17_INT", user_gpio_int_callback)
        gpio.close(exs_mcp23s17.gpio_int_id)
    end

    -- 关闭 SPI 总线
    if exs_mcp23s17.spi_id then
        spi.close(exs_mcp23s17.spi_id)
    end

    -- 释放片选引脚
    if exs_mcp23s17.cs_pin then
        gpio.close(exs_mcp23s17.cs_pin)
    end

    -- 清除运行时状态
    exs_mcp23s17.spi_id = nil
    exs_mcp23s17.cs_pin = nil
    exs_mcp23s17.cs_ctrl = nil
    exs_mcp23s17.gpio_int_id = nil
    exs_mcp23s17.hw_addr = 0
    exs_mcp23s17.bandrate = DEFAULT_BANDRATE
    exs_mcp23s17.ints = nil

    log.info("exs_mcp23s17", "已关闭")
    return true
end

-- 配置扩展 GPIO 管脚功能
-- @param gpio_id GPIO ID（A 口：0x00~0x07，B 口：0x10~0x17）
-- @param gpio_mode 配置模式：
--   number（0/1）：输出模式，并设置初始输出电平
--   nil：输入模式
--   function：中断模式，传入中断回调函数（回调参数：id, level）
-- @return boolean 配置成功返回 true
function exs_mcp23s17.setup(gpio_id, gpio_mode)
    if not check_gpio_id_valid(gpio_id) then
        return false
    end

    local iodir_reg = get_reg_addr(gpio_id, REG_IODIRA)
    local mask = get_gpio_mask(gpio_id)
    local reg_value = read_register(iodir_reg)
    if reg_value == nil then
        log.error("exs_mcp23s17", "读取方向寄存器失败")
        return false
    end

    if gpio_mode == nil then
        -- 输入模式：IODIR 对应位置 1
        write_register(iodir_reg, bit.bor(reg_value, mask))
    elseif type(gpio_mode) == "number" then
        -- 输出模式：IODIR 对应位清 0，并设置初始电平
        write_register(iodir_reg, bit.band(reg_value, bit.bnot(mask)))
        exs_mcp23s17.set(gpio_id, gpio_mode)
    elseif type(gpio_mode) == "function" then
        -- 中断模式：方向设为输入，使能中断，边沿触发，保存回调
        write_register(iodir_reg, bit.bor(reg_value, mask))

        -- GPINTEN 对应位置 1（使能中断）
        local inten_reg = get_reg_addr(gpio_id, REG_GPINTENA)
        local inten_value = read_register(inten_reg)
        if inten_value then
            write_register(inten_reg, bit.bor(inten_value, mask))
        end

        -- INTCON 对应位清 0（电平变化触发，而非与 DEFVAL 比较）
        local intcon_reg = get_reg_addr(gpio_id, REG_INTCONA)
        local intcon_value = read_register(intcon_reg)
        if intcon_value then
            write_register(intcon_reg, bit.band(intcon_value, bit.bnot(mask)))
        end

        -- 保存中断回调函数
        if not exs_mcp23s17.ints then
            exs_mcp23s17.ints = {}
        end
        exs_mcp23s17.ints[gpio_id] = gpio_mode
    else
        log.error("exs_mcp23s17", "GPIO 模式参数无效", gpio_mode)
        return false
    end

    return true
end

-- 设置扩展 GPIO 输出电平
-- @param gpio_id GPIO ID
-- @param output_level 输出电平（0=低电平，1=高电平）
-- @return boolean 设置成功返回 true
function exs_mcp23s17.set(gpio_id, output_level)
    if not check_gpio_id_valid(gpio_id) then
        return false
    end

    local olat_reg = get_reg_addr(gpio_id, REG_OLATA)
    local mask = get_gpio_mask(gpio_id)
    local reg_value = read_register(olat_reg)
    if reg_value == nil then
        log.error("exs_mcp23s17", "读取输出锁存寄存器失败")
        return false
    end

    if output_level and output_level ~= 0 then
        write_register(olat_reg, bit.bor(reg_value, mask))
    else
        write_register(olat_reg, bit.band(reg_value, bit.bnot(mask)))
    end

    return true
end

-- 读取扩展 GPIO 输入电平
-- @param gpio_id GPIO ID
-- @return number 输入电平（0 或 1），失败返回 nil
function exs_mcp23s17.get(gpio_id)
    if not check_gpio_id_valid(gpio_id) then
        return nil
    end

    local gpio_reg = get_reg_addr(gpio_id, REG_GPIOA)
    local mask = get_gpio_mask(gpio_id)
    local reg_value = read_register(gpio_reg)
    if reg_value == nil then
        log.error("exs_mcp23s17", "读取 GPIO 寄存器失败")
        return nil
    end

    if bit.band(reg_value, mask) > 0 then
        return 1
    else
        return 0
    end
end

-- 关闭扩展 GPIO 功能（恢复默认输入态）
-- @param gpio_id GPIO ID
-- @return boolean 关闭成功返回 true
function exs_mcp23s17.close(gpio_id)
    if not check_gpio_id_valid(gpio_id) then
        return false
    end

    local mask = get_gpio_mask(gpio_id)

    -- 方向设为输入（IODIR 对应位置 1）
    local iodir_reg = get_reg_addr(gpio_id, REG_IODIRA)
    local iodir_value = read_register(iodir_reg)
    if iodir_value then
        write_register(iodir_reg, bit.bor(iodir_value, mask))
    end

    -- 禁用中断（GPINTEN 对应位清 0）
    local inten_reg = get_reg_addr(gpio_id, REG_GPINTENA)
    local inten_value = read_register(inten_reg)
    if inten_value then
        write_register(inten_reg, bit.band(inten_value, bit.bnot(mask)))
    end

    -- 禁用上拉（GPPU 对应位清 0）
    local gppu_reg = get_reg_addr(gpio_id, REG_GPPUA)
    local gppu_value = read_register(gppu_reg)
    if gppu_value then
        write_register(gppu_reg, bit.band(gppu_value, bit.bnot(mask)))
    end

    -- 极性恢复正常（IPOL 对应位清 0）
    local ipol_reg = get_reg_addr(gpio_id, REG_IPOLA)
    local ipol_value = read_register(ipol_reg)
    if ipol_value then
        write_register(ipol_reg, bit.band(ipol_value, bit.bnot(mask)))
    end

    -- 清除中断回调
    if exs_mcp23s17.ints then
        exs_mcp23s17.ints[gpio_id] = nil
    end

    return true
end

-- 配置扩展 GPIO 内部上拉电阻
-- @param gpio_id GPIO ID
-- @param enable 是否启用上拉（true=启用，false=禁用）
-- @return boolean 配置成功返回 true
function exs_mcp23s17.set_pullup(gpio_id, enable)
    if not check_gpio_id_valid(gpio_id) then
        return false
    end

    local gppu_reg = get_reg_addr(gpio_id, REG_GPPUA)
    local mask = get_gpio_mask(gpio_id)
    local reg_value = read_register(gppu_reg)
    if reg_value == nil then
        log.error("exs_mcp23s17", "读取上拉寄存器失败")
        return false
    end

    if enable then
        write_register(gppu_reg, bit.bor(reg_value, mask))
    else
        write_register(gppu_reg, bit.band(reg_value, bit.bnot(mask)))
    end

    return true
end

-- 配置扩展 GPIO 输入极性反转
-- @param gpio_id GPIO ID
-- @param invert 是否反转极性（true=反转，false=正常）
-- @return boolean 配置成功返回 true
function exs_mcp23s17.set_polarity(gpio_id, invert)
    if not check_gpio_id_valid(gpio_id) then
        return false
    end

    local ipol_reg = get_reg_addr(gpio_id, REG_IPOLA)
    local mask = get_gpio_mask(gpio_id)
    local reg_value = read_register(ipol_reg)
    if reg_value == nil then
        log.error("exs_mcp23s17", "读取极性寄存器失败")
        return false
    end

    if invert then
        write_register(ipol_reg, bit.bor(reg_value, mask))
    else
        write_register(ipol_reg, bit.band(reg_value, bit.bnot(mask)))
    end

    return true
end

-- 获取扩展库版本号
-- @return string 版本号（格式：YYYYMMDDHHMM）
function exs_mcp23s17.version()
    return "202608241200"
end

return exs_mcp23s17
