--[[
@module  exs_pcf8574
@summary PCF8574 8位 I2C GPIO 扩展芯片驱动扩展库
@version 1.0
@date    2026.08.06
@author  沈园园
@usage
本扩展库提供 PCF8574 的 LuatOS 驱动，功能包括：
1、初始化（I2C 通信建立、地址自动探测、中断引脚配置）
2、GPIO 读写（单引脚/批量读写、输入/输出/中断三种模式）

对外接口 4 个：
- exs_pcf8574.setup(config)：初始化
- exs_pcf8574.get_data()：读取所有引脚状态
- exs_pcf8574.close()：释放资源
- exs_pcf8574.version()：获取版本号

可选接口：
- exs_pcf8574.set(pin, level)：设置单引脚输出电平
- exs_pcf8574.get(pin)：读取单引脚输入电平
- exs_pcf8574.read_all()：读取所有引脚状态（字节）
- exs_pcf8574.write_all(data)：写入所有引脚状态（字节）
- exs_pcf8574.pin_setup(pin, mode)：配置引脚模式
- exs_pcf8574.pin_close(pin)：关闭引脚
- exs_pcf8574.process_int()：处理中断事件（需配合 int_gpio 参数）
- exs_pcf8574.poll_int()：轮询检测引脚变化（适用于无 INT 引脚的模块）

=== 版本更新说明 ===
-- 版本号：202608061000
-- 1、更新时间：2026-08-06
-- 2、更新内容：
--   - 初版实现
--   - 支持 PCF8574T（0x20~0x27）和 PCF8574AT（0x38~0x3F）地址自动探测
--   - 支持硬件 I2C 和软件 I2C
--   - 支持 GPIO 输入/输出/中断三种模式
--   - 支持批量读写
--   - 支持 I2C 总线恢复
]]

-- ==================== 模块表 ====================
local exs_pcf8574 = {}

-- ==================== 常量定义 ====================

-- PCF8574T I2C 地址范围：0x20 ~ 0x27（A0A1A2 = 000 ~ 111）
local ADDR_T_BASE  = 0x20  -- PCF8574T 基地址
-- PCF8574AT I2C 地址范围：0x38 ~ 0x3F（A0A1A2 = 000 ~ 111）
local ADDR_AT_BASE = 0x38  -- PCF8574AT 基地址

-- GPIO ID 有效范围
local PIN_MIN = 0x00  -- P0
local PIN_MAX = 0x07  -- P7

-- ==================== 内部变量 ====================
local g_i2c_id    = nil       -- I2C 总线 id
local g_is_soft   = false     -- 是否软件 I2C
local g_scl_pin   = nil       -- SCL 引脚（总线恢复用）
local g_sda_pin   = nil       -- SDA 引脚（总线恢复用）
local g_i2c_speed = i2c.FAST  -- 保存原始 speed（总线恢复后恢复）
local g_dev_addr  = nil       -- 探测成功后的设备地址
local g_output    = 0xFF      -- 输出寄存器缓存（初始全 1，输入模式）
local g_int_gpio  = nil       -- 中断引脚 GPIO id（可选）
local g_int_cb    = nil       -- 中断回调函数表
local g_last_input = 0xFF     -- 上次输入寄存器值（轮询中断用）
local g_ready     = false     -- 是否已就绪

-- ==================== I2C 总线恢复 ====================

-- I2C 总线硬件恢复：9 个 SCL 脉冲 + 每脉冲检测 SDA 释放 + STOP 信号
local function i2c_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    sys.wait(1)     -- 等待电平稳定，1ms
    for i = 1, 9 do
        gpio.set(g_scl_pin, 0); sys.wait(1)                          -- SCL 拉低
        gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP); sys.wait(1)  -- 检测 SDA 释放
        if gpio.get(g_sda_pin) == 1 then
            gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
            break
        end
        gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
        gpio.set(g_scl_pin, 1); sys.wait(1)                          -- SCL 拉高
    end
    gpio.set(g_sda_pin, 0); sys.wait(1)    -- 起始条件
    gpio.set(g_scl_pin, 1); sys.wait(1)    -- 结束条件前半
    gpio.set(g_sda_pin, 1); sys.wait(1)    -- 结束条件后半
    return true
end

-- 检测总线是否卡死，卡死后调用 i2c_bus_recovery 恢复
-- 锁死判据：SDA=0, SCL=1（从机锁死 SDA）
-- 恢复后恢复硬件 I2C 原始 speed（g_i2c_speed）
local function try_bus_recovery()
    if not g_scl_pin or not g_sda_pin then return false end
    gpio.setup(g_sda_pin, gpio.INPUT, gpio.PULLUP)
    gpio.setup(g_scl_pin, gpio.INPUT, gpio.PULLUP); sys.wait(1)
    local is_stall = (gpio.get(g_sda_pin) == 0 and gpio.get(g_scl_pin) == 1)
    gpio.setup(g_sda_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    gpio.setup(g_scl_pin, gpio.OUTPUT, gpio.PULLUP, 1)
    if not is_stall then return false end  -- 总线未卡死，无需恢复
    log.warn("exs_pcf8574", "检测到 I2C 总线卡死，尝试恢复")
    i2c_bus_recovery()
    if not g_is_soft then i2c.setup(g_i2c_id, g_i2c_speed) end  -- 恢复原始 speed
    return true
end

-- ==================== I2C 操作 ====================

-- 写端口：向 PCF8574 写入 1 字节数据（直接发送，无需寄存器地址）
-- val：要写入的数据（0x00~0xFF）
-- 返回 boolean：成功返回 true
local function wr_output(val)
    if not g_i2c_id or not g_dev_addr then
        log.error("exs_pcf8574", "设备未初始化")
        return false
    end
    local ok = i2c.send(g_i2c_id, g_dev_addr, val)
    if not ok and try_bus_recovery() then
        ok = i2c.send(g_i2c_id, g_dev_addr, val)
    end
    if ok then g_output = val end
    return ok
end

-- 读端口：从 PCF8574 读取 1 字节数据（直接接收，无需寄存器地址）
-- 返回 number：读取到的数据（0x00~0xFF），失败返回 nil
local function rd_input()
    if not g_i2c_id or not g_dev_addr then
        log.error("exs_pcf8574", "设备未初始化")
        return nil
    end
    local d = i2c.recv(g_i2c_id, g_dev_addr, 1)
    if not d or #d < 1 then
        if try_bus_recovery() then
            d = i2c.recv(g_i2c_id, g_dev_addr, 1)
        end
    end
    if not d or #d < 1 then return nil end
    return d:byte(1)
end

-- ==================== GPIO 工具函数 ====================

-- 检查引脚 ID 是否有效
-- pin：引脚 ID（0x00~0x07）
-- 返回 boolean：有效返回 true
local function check_pin_valid(pin)
    return (pin >= PIN_MIN and pin <= PIN_MAX)
end

-- 根据引脚 ID 获取位掩码
-- pin：引脚 ID（0x00~0x07）
-- 返回 number：位掩码（0x01~0x80）
local function get_pin_mask(pin)
    return 1 << (pin & 0x07)
end

-- ==================== 固定对外接口 ====================

--[[
初始化 PCF8574，配置 I2C 通信参数，自动探测设备地址

@api exs_pcf8574.setup(config)

@param table config
参数含义：初始化配置表
数据类型：table
取值说明：
  - i2c_id (number)：硬件 I2C 总线 id，如 0 或 1
  - scl (number)：软件 I2C 的 SCL 引脚号
  - sda (number)：软件 I2C 的 SDA 引脚号
  - addr (number)：指定设备地址（可选，不传则自动探测）
  - int_gpio (number)：中断引脚 GPIO id（可选，不传则不使用中断）
是否必选：是
注意事项：i2c_id 与 scl/sda 二选一，同时传优先硬件 I2C
参数示例：{i2c_id = 1} 或 {scl = 67, sda = 66}

@return boolean
含义说明：初始化是否成功
数据类型：boolean
返回示例：true
]]

-- GPIO 中断回调：发布中断消息（必须在 setup() 之前定义，因为 Lua local 变量必须先声明后使用）
local function gpio_int_publish_func()
    sys.publish("exs_pcf8574_INT")
end

function exs_pcf8574.setup(config)
    if type(config) ~= "table" then
        log.error("exs_pcf8574", "config 必须是 table 类型")
        return false
    end

    -- 保存中断引脚
    g_int_gpio = config.int_gpio  -- 可选

    -- I2C 初始化
    if config.scl and config.sda then
        g_scl_pin = config.scl; g_sda_pin = config.sda
        if config.i2c_id then
            i2c_bus_recovery()
            i2c.setup(config.i2c_id, i2c.FAST)
            g_i2c_id = config.i2c_id; g_is_soft = false; g_i2c_speed = i2c.FAST
        else
            i2c_bus_recovery()
            g_i2c_id = i2c.createSoft(config.scl, config.sda, 5)
            g_is_soft = true
        end
    else
        g_i2c_id = config.i2c_id or 0
        i2c.setup(g_i2c_id, i2c.FAST); g_is_soft = false
    end

    -- 自动探测设备地址
    local addr_list = {}
    if config.addr then
        addr_list = {config.addr}
    else
        -- 扫描 PCF8574T（0x20~0x27）和 PCF8574AT（0x38~0x3F）
        for i = 0, 7 do
            addr_list[#addr_list + 1] = ADDR_T_BASE + i
        end
        for i = 0, 7 do
            addr_list[#addr_list + 1] = ADDR_AT_BASE + i
        end
    end

    local ok_addr = nil
    for i = 1, #addr_list do
        local addr = addr_list[i]
        -- PCF8574 直接接收 1 字节即可探测（无需寄存器地址）
        local d = i2c.recv(g_i2c_id, addr, 1)
        if d and #d == 1 then
            ok_addr = addr
            break
        end
    end

    if not ok_addr then
        log.error("exs_pcf8574", "地址探测失败：未找到 PCF8574 设备")
        log.error("exs_pcf8574", "检查接线: VCC=3.3V GND SCL SDA，A0/A1/A2 地址跳线是否正确")
        if not g_is_soft then i2c.close(g_i2c_id) end
        g_i2c_id = nil
        return false
    end

    g_dev_addr = ok_addr
    log.info("exs_pcf8574", string.format("芯片地址自适应：0x%02X", g_dev_addr))

    -- 初始化输出寄存器为 0xFF（全部输入模式，内部上拉）
    wr_output(0xFF)

    -- 清除可能的虚假中断：wr_output 后 INT 可能被拉低，读取输入寄存器可清除
    rd_input()

    -- 配置中断 GPIO（可选）
    if g_int_gpio then
        gpio.setup(g_int_gpio, gpio_int_publish_func, gpio.PULLUP, gpio.FALLING)
        log.info("exs_pcf8574", string.format("中断 GPIO 已配置: %d", g_int_gpio))
    end

    g_ready = true
    log.info("exs_pcf8574", string.format("初始化完成: i2c=%s addr=0x%02X",
        g_is_soft and "soft" or tostring(g_i2c_id), g_dev_addr))
    return true
end

--[[
读取所有 GPIO 引脚状态

@api exs_pcf8574.get_data()

@return table
含义说明：所有引脚状态
数据类型：table
字段说明：
  - p0~p7 (number)：P0~P7 引脚电平，0=低电平，1=高电平
  - raw (number)：原始字节数据，bit0=P0, bit7=P7
返回示例：{p0=1, p1=0, ..., p7=1, raw=0x81}
]]
function exs_pcf8574.get_data()
    if not g_ready then
        log.error("exs_pcf8574", "设备未初始化")
        return nil
    end
    local val = rd_input()
    if val == nil then return nil end
    local result = {raw = val}
    for i = 0, 7 do
        result["p" .. i] = (val >> i) & 0x01
    end
    return result
end

--[[
关闭 PCF8574，释放所有资源

@api exs_pcf8574.close()

@return nil
含义说明：无返回值
]]
function exs_pcf8574.close()
    if g_i2c_id and not g_is_soft then
        i2c.close(g_i2c_id)
    end
    g_i2c_id = nil
    g_dev_addr = nil
    g_int_gpio = nil
    g_int_cb = nil
    g_output = 0xFF
    g_ready = false
    log.info("exs_pcf8574", "资源已释放")
end

--[[
获取版本号

@api exs_pcf8574.version()

@return string
含义说明：版本号字符串
数据类型：string
返回示例："202608061000"
]]
function exs_pcf8574.version()
    return "202608061000"
end

-- ==================== 可选对外接口 ====================

--[[
配置 PCF8574 单个引脚的工作模式

@api exs_pcf8574.pin_setup(pin, mode)

@param number pin
参数含义：PCF8574 的引脚 ID
数据类型：number
取值范围：0x00 ~ 0x07，对应 P0 ~ P7
是否必选：是
参数示例：0x00

@param number|function|nil mode
参数含义：引脚工作模式
数据类型：number | function | nil
取值说明：
  - number (0)：输出模式，输出低电平（灌电流驱动，可直接驱动 LED）
  - number (1)：输出模式，输出高电平（内部上拉，弱驱动）
  - nil：输入模式（内部上拉，外部驱动）
  - function：中断模式，参数为回调函数
    回调函数格式：function cb_func(pin, level) end
    - pin：触发中断的引脚 ID
    - level：触发中断后读取到的电平（0=低，1=高）
是否必选：是
注意事项：中断模式需要在 setup() 中传入 int_gpio 参数
参数示例：0

@return boolean
含义说明：配置是否成功
数据类型：boolean
返回示例：true
]]
function exs_pcf8574.pin_setup(pin, mode)
    if not check_pin_valid(pin) then
        log.error("exs_pcf8574.pin_setup", "参数错误：pin 应为 0x00~0x07")
        return false
    end

    if mode ~= 0 and mode ~= 1 and mode ~= nil and type(mode) ~= "function" then
        log.error("exs_pcf8574.pin_setup", "参数错误：mode 类型无效")
        return false
    end

    local mask = get_pin_mask(pin)
    local new_output = g_output

    if mode == 0 then
        new_output = new_output & (~mask)   -- 输出低电平
    else
        new_output = new_output | mask      -- 输出高电平 / 输入模式 / 中断模式
    end

    if new_output ~= g_output then
        if not wr_output(new_output) then
            log.error("exs_pcf8574.pin_setup", "写入输出寄存器失败")
            return false
        end
    end

    -- 中断模式：注册回调函数
    if type(mode) == "function" then
        if g_int_cb == nil then g_int_cb = {} end
        g_int_cb[pin] = mode
    end

    return true
end

--[[
关闭 PCF8574 单个引脚，恢复为默认输入模式

@api exs_pcf8574.pin_close(pin)

@param number pin
参数含义：PCF8574 的引脚 ID
数据类型：number
取值范围：0x00 ~ 0x07
是否必选：是
参数示例：0x03

@return boolean
含义说明：关闭是否成功
数据类型：boolean
返回示例：true
]]
function exs_pcf8574.pin_close(pin)
    if not check_pin_valid(pin) then
        log.error("exs_pcf8574.pin_close", "参数错误：pin 应为 0x00~0x07")
        return false
    end
    -- 清除中断回调
    if g_int_cb then g_int_cb[pin] = nil end
    -- 恢复为输入模式（写入 1）
    return exs_pcf8574.pin_setup(pin)
end

--[[
设置 PCF8574 单个引脚的输出电平

@api exs_pcf8574.set(pin, level)

@param number pin
参数含义：PCF8574 的引脚 ID
数据类型：number
取值范围：0x00 ~ 0x07
是否必选：是
参数示例：0x03

@param number level
参数含义：输出电平
数据类型：number
取值范围：0（低电平）或 1（高电平）
是否必选：是
注意事项：0=低电平（灌电流驱动，可直接驱动 LED），1=高电平（内部上拉，弱驱动）
参数示例：0

@return boolean
含义说明：设置是否成功
数据类型：boolean
返回示例：true
]]
function exs_pcf8574.set(pin, level)
    if not check_pin_valid(pin) then
        log.error("exs_pcf8574.set", "参数错误：pin 应为 0x00~0x07")
        return false
    end
    if level ~= 0 and level ~= 1 then
        log.error("exs_pcf8574.set", "参数错误：level 应为 0 或 1")
        return false
    end

    local mask = get_pin_mask(pin)
    local new_output
    if level == 0 then
        new_output = g_output & (~mask)
    else
        new_output = g_output | mask
    end

    if new_output ~= g_output then
        if not wr_output(new_output) then
            log.error("exs_pcf8574.set", "写入输出寄存器失败")
            return false
        end
    end
    return true
end

--[[
读取 PCF8574 单个引脚的输入电平

@api exs_pcf8574.get(pin)

@param number pin
参数含义：PCF8574 的引脚 ID
数据类型：number
取值范围：0x00 ~ 0x07
是否必选：是
注意事项：引脚必须先通过 pin_setup() 配置为输入或中断模式
参数示例：0x02

@return number|boolean
含义说明：引脚输入电平
数据类型：number 或 boolean
取值范围：0（低电平），1（高电平）；读取失败返回 false
返回示例：1
]]
function exs_pcf8574.get(pin)
    if not check_pin_valid(pin) then
        log.error("exs_pcf8574.get", "参数错误：pin 应为 0x00~0x07")
        return false
    end
    local val = rd_input()
    if val == nil then
        log.error("exs_pcf8574.get", "读取输入寄存器失败")
        return false
    end
    return (val >> (pin & 0x07)) & 0x01
end

--[[
读取 PCF8574 所有引脚状态（字节）

@api exs_pcf8574.read_all()

@return number|boolean
含义说明：8 位端口数据
数据类型：number 或 boolean
取值范围：0x00 ~ 0xFF，bit0=P0, bit7=P7；读取失败返回 false
返回示例：0xF0
]]
function exs_pcf8574.read_all()
    local val = rd_input()
    if val == nil then
        log.error("exs_pcf8574.read_all", "读取输入寄存器失败")
        return false
    end
    return val
end

--[[
写入 PCF8574 所有引脚状态（字节）

@api exs_pcf8574.write_all(data)

@param number data
参数含义：8 位端口数据，每位对应一个引脚
数据类型：number
取值范围：0x00 ~ 0xFF，bit0=P0, bit7=P7
是否必选：是
注意事项：写入 0 的引脚输出低电平（灌电流驱动），写入 1 的引脚变为高阻（内部上拉）
参数示例：0xF0

@return boolean
含义说明：写入是否成功
数据类型：boolean
返回示例：true
]]
function exs_pcf8574.write_all(data)
    if data < 0x00 or data > 0xFF then
        log.error("exs_pcf8574.write_all", "参数错误：data 范围 0x00~0xFF")
        return false
    end
    if not wr_output(data) then
        log.error("exs_pcf8574.write_all", "写入输出寄存器失败")
        return false
    end
    return true
end

-- ==================== 中断消息处理 ====================

-- 中断处理函数：读取扩展 GPIO 电平并分发用户回调
-- 必须在协程上下文中调用（I2C 操作不可靠在中断回调中执行）
local function int_process_func()
    if not g_int_cb then return end
    local val = rd_input()
    if val == nil then return end
    for pin, cb in pairs(g_int_cb) do
        if cb then
            local level = (val >> (pin & 0x07)) & 0x01
            cb(pin, level)
        end
    end
end

--[[
处理中断事件：读取引脚状态并分发用户回调

@api exs_pcf8574.process_int()

@return nil
含义说明：无返回值
注意事项：此函数必须在协程上下文中调用（如 sys.waitUntil 返回后）
使用场景：配合 setup() 中的 int_gpio 参数，在监听任务中调用
]]
function exs_pcf8574.process_int()
    int_process_func()
end

--[[
轮询检测引脚变化并分发用户回调（适用于无INT引脚的PCF8574模块）

@api exs_pcf8574.poll_int()

@return nil
含义说明：无返回值
注意事项：此函数需要在定时器中周期性调用（如每100ms）
使用场景：当PCF8574模块未引出INT引脚时，通过轮询检测引脚变化
工作原理：读取输入寄存器并与上次值比较，检测到变化时调用对应回调
]]
function exs_pcf8574.poll_int()
    if not g_ready or not g_int_cb then
        return
    end

    local val = rd_input()
    if val == nil then
        return
    end

    -- 检测变化的引脚
    local changed = val ~ g_last_input
    if changed == 0 then
        g_last_input = val
        return
    end

    -- 分发回调
    for pin, cb in pairs(g_int_cb) do
        if cb then
            local mask = 1 << (pin & 0x07)
            if changed & mask ~= 0 then
                local level = (val >> (pin & 0x07)) & 0x01
                cb(pin, level)
            end
        end
    end

    g_last_input = val
end

return exs_pcf8574