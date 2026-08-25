# exs_mcp23s17 扩展库

> 作者：沈园园

## **一、概述**

exs_mcp23s17 是 Microchip MCP23S17 16 位 SPI GPIO 扩展芯片的 LuatOS 扩展库。
MCP23S17 提供 16 位并行 I/O 扩展，通过 SPI 串行接口与主控通信，广泛应用于需要额外 GPIO 的场景。

MCP23S17 提供 **2 个 8 位端口（Port A 和 Port B）**，共 **16 个 GPIO**，支持输入、输出和中断三种工作模式，
并内置上拉电阻、极性反转、独立中断使能等高级功能。

### **1.1 主要特性**

- 16 个 I/O 引脚，分为 2 组 8 位端口（Port A: GPA0~GPA7，Port B: GPB0~GPB7）

- 每个 I/O 可独立配置为输入或输出模式

- 支持 **INT 中断引脚**，输入电平变化时触发中断通知主控

- **内置可选上拉电阻**（典型值 100kΩ），可通过寄存器配置启用/禁用

- 支持极性反转寄存器，适应不同硬件设计需求

- 支持独立中断使能寄存器，每个引脚可单独配置中断

- SPI 接口速率最高可达 10MHz，本库默认 1MHz

- 3 个硬件地址引脚（A0、A1、A2），支持 8 种硬件地址（0~7），单条 SPI 总线最多挂载 8 片

- 与 MCP23017（I2C 接口）寄存器完全兼容（Bank 0 模式），上层业务代码可无缝迁移

- 工作电压 1.8V~5.5V

- 工作温度 -40℃~+85℃

### **1.2 加载方式**

```lua
-- 扩展库需要 require 加载后才能调用
local exs_mcp23s17 = require "exs_mcp23s17"
```

### **1.3 注意事项**

- **SPI 接线**：MCP23S17 通过 SPI 总线与主控通信，SI/MOSI、SO/MISO、SCK 需正确连接，CS 片选由软件 GPIO 控制

- **INT 引脚**：MCP23S17 的 INT 引脚为开漏输出，需外接上拉电阻

- **GPIO ID 编码规则**：
  - `0x00` ~ `0x07`：Port A 的 GPA0 ~ GPA7
  - `0x10` ~ `0x17`：Port B 的 GPB0 ~ GPB7

- **中断模式**：使用中断功能时，必须在 `init()` 中传入 `gpio_int_id` 参数，并将 MCP23S17 的 INT 引脚连接到主机的对应 GPIO

- **上拉电阻**：MCP23S17 内置上拉电阻（GPPU 寄存器），但典型值为 100kΩ，如需更强上拉仍需外部电阻

- **多设备支持**：通过 A0、A1、A2 引脚配置不同硬件地址，最多可在同一 SPI 总线上连接 8 个 MCP23S17 设备（各设备 CS 需独立控制）

- **硬件地址**：芯片复位后 HAEN=0，只响应地址 0；使用非 0 地址时，扩展库会自动先以地址 0 使能 IOCON 寄存器的 HAEN 位

- **Bank 模式**：本库使用 Bank 0 模式（寄存器地址线性映射），MCP23S17 默认为此模式

### **1.4 硬件连接**

```
  ┌──────────────┐                    ┌──────────────────┐
  │    主控       │                    │    MCP23S17      │
  │  (Airxxx)    │                    │  GPIO 扩展芯片   │
  │              │                    │                  │
  │ SPI0_MOSI ───┼────────────────────┼──→ SI            │
  │              │                    │                  │
  │ SPI0_MISO ←──┼────────────────────┼──→ SO            │
  │              │                    │                  │
  │ SPI0_SLK  ───┼────────────────────┼──→ SCK           │
  │              │                    │                  │
  │ GPIO8/CS  ───┼────────────────────┼──→ CS            │
  │              │                    │                  │
  │ GPIO_INT ←───┼────────────────────┼──→ INT           │
  │              │                    │  （开漏输出，     │
  │              │                    │   需外接上拉电阻）│
  │              │                    │                  │
  │ VCC 3V3 ─────┼────────────────────┼──→ VDD           │
  │              │                    │                  │
  │ GND      ────┼────────────────────┼──→ GND           │
  │              │                    │                  │
  │              │                    │ A0~A2 ──────────┼──→ 硬件地址配置
  │              │                    │                  │
  │              │                    │ GPA0~GPA7 ──────┼──→ 扩展 GPIO 端口A
  │              │                    │ GPB0~GPB7 ──────┼──→ 扩展 GPIO 端口B
  └──────────────┘                    └──────────────────┘
```

### **1.5 寄存器映射（Bank 0 模式）**

| 寄存器 | 地址 | 功能说明 |
|--------|------|----------|
| IODIRA/IODIRB | 0x00/0x01 | 方向控制（1=输入，0=输出） |
| IPOLA/IPOLB | 0x02/0x03 | 极性反转（1=反转，0=正常） |
| GPINTENA/GPINTENB | 0x04/0x05 | 中断使能（1=使能，0=禁用） |
| DEFVALA/DEFVALB | 0x06/0x07 | 中断默认比较值 |
| INTCONA/INTCONB | 0x08/0x09 | 中断控制（1=与DEFVAL比较，0=边沿触发） |
| IOCON | 0x0A | I/O 配置寄存器（bit3=HAEN 硬件地址使能） |
| GPPUA/GPPUB | 0x0C/0x0D | 内部上拉电阻（1=启用，0=禁用） |
| INTFA/INTFB | 0x0E/0x0F | 中断标志（只读） |
| INTCAPA/INTCAPB | 0x10/0x11 | 中断捕获（只读） |
| GPIOA/GPIOB | 0x12/0x13 | 端口读取（实际引脚状态） |
| OLATA/OLATB | 0x14/0x15 | 输出锁存（输出电平设置） |

> **IODIR 寄存器说明**：1 = 输入模式，0 = 输出模式
>
> **GPPU 寄存器说明**：1 = 启用内部上拉电阻，0 = 禁用
>
> **OLAT 寄存器说明**：设置输出电平，读取实际引脚状态请使用 GPIO 寄存器

### **1.6 SPI 通信协议**

MCP23S17 通过 SPI 总线通信，每次访问需先发送控制字节（opcode）：

| 操作 | 控制字节 | 帧格式 |
|------|----------|--------|
| 写寄存器 | 0b0100 A2 A1 A0 0 → `0x40 \| (hw_addr << 1)` | {opcode, reg, data} |
| 读寄存器 | 0b0100 A2 A1 A0 1 → `0x41 \| (hw_addr << 1)` | {opcode, reg, dummy} + 接收 1 字节 |

> **控制字节说明**：bit7~bit4 固定为 0100；bit3~bit1 为硬件地址 A2A1A0；bit0 为读写位（0=写，1=读）
>
> **SPI 模式说明**：支持 Mode 0（CPOL=0，CPHA=0）与 Mode 3（CPOL=1，CPHA=1），本库默认使用 Mode 0
>
> **波特率说明**：最高支持 10MHz，本库默认 1MHz（杜邦线连接更稳定，PCB 直连可适当提高）

---

## **二、核心示例**

- 核心示例是指：使用本库文件提供的核心 API，开发的基础业务逻辑的演示代码

- 核心示例的作用是：帮助开发者快速理解如何使用本库，所以核心示例的逻辑都比较简单

- 更加完整和详细的 demo，请参考 [LuatOS 仓库](https://gitee.com/openLuat/LuatOS/tree/master/module) 中各个产品目录下的 demo/sensor/mcp23s17

### **2.1 GPIO 输出示例**

```lua
-- 加载扩展库
local exs_mcp23s17 = require "exs_mcp23s17"

-- 应用主函数
local function mcp23s17_output_demo()
    -- 初始化 MCP23S17（使用 SPI0，CS=GPIO8）
    local result = exs_mcp23s17.init(0, 8)

    if not result then
        log.error("exs_mcp23s17", "MCP23S17 初始化失败")
        return
    end
    log.info("exs_mcp23s17", "MCP23S17 初始化成功")

    -- 配置 PA0 (0x00) 为输出模式，初始输出低电平
    exs_mcp23s17.setup(0x00, 0)

    -- 循环切换 PA0 电平
    while true do
        exs_mcp23s17.set(0x00, 0)  -- 输出低电平
        sys.wait(1000)
        exs_mcp23s17.set(0x00, 1)  -- 输出高电平
        sys.wait(1000)
    end
end

-- 启动任务
sys.taskInit(mcp23s17_output_demo)
```

### **2.2 GPIO 输入示例**

```lua
-- 加载扩展库
local exs_mcp23s17 = require "exs_mcp23s17"

-- 应用主函数
local function mcp23s17_input_demo()
    -- 初始化 MCP23S17
    local result = exs_mcp23s17.init(0, 8)

    if not result then
        log.error("exs_mcp23s17", "MCP23S17 初始化失败")
        return
    end

    -- 配置 PA1 (0x01) 为输出模式（用于产生测试信号）
    exs_mcp23s17.setup(0x01, 0)

    -- 配置 PA2 (0x02) 为输入模式，启用内部上拉
    exs_mcp23s17.setup(0x02)
    exs_mcp23s17.set_pullup(0x02, true)

    -- 循环读取 PA2 电平
    -- 注意：需将 PA1 和 PA2 短接
    while true do
        exs_mcp23s17.set(0x01, 0)
        sys.wait(1000)
        local level = exs_mcp23s17.get(0x02)
        log.info("exs_mcp23s17", "PA2 电平:", level)

        exs_mcp23s17.set(0x01, 1)
        sys.wait(1000)
        level = exs_mcp23s17.get(0x02)
        log.info("exs_mcp23s17", "PA2 电平:", level)
    end
end

sys.taskInit(mcp23s17_input_demo)
```

### **2.3 GPIO 中断示例**

```lua
-- 加载扩展库
local exs_mcp23s17 = require "exs_mcp23s17"

-- PA4 中断回调函数
-- id：触发中断的 GPIO ID
-- level：触发中断后读取到的电平（0=低，1=高）
local function PA4_int_cbfunc(id, level)
    log.info("exs_mcp23s17", "PA4 中断触发，ID:", id, "电平:", level)
end

-- 应用主函数
local function mcp23s17_int_demo()
    -- 初始化 MCP23S17，使用 GPIO2 作为中断引脚
    local result = exs_mcp23s17.init(0, 8, 2)

    if not result then
        log.error("exs_mcp23s17", "MCP23S17 初始化失败")
        return
    end

    -- 配置 PA3 (0x03) 为输出模式（用于触发 PA4 中断）
    exs_mcp23s17.setup(0x03, 0)

    -- 配置 PA4 (0x04) 为中断模式
    -- 注意：需将 PA3 和 PA4 短接
    exs_mcp23s17.setup(0x04, PA4_int_cbfunc)

    -- 循环切换 PA3 电平，触发 PA4 中断
    while true do
        exs_mcp23s17.set(0x03, 0)
        sys.wait(1000)
        exs_mcp23s17.set(0x03, 1)
        sys.wait(1000)
    end
end

sys.taskInit(mcp23s17_int_demo)
```

### **2.4 上拉电阻示例**

```lua
local exs_mcp23s17 = require "exs_mcp23s17"

exs_mcp23s17.init(0, 8)

-- 批量配置 Port A 为输出，Port B 为输入
for i = 0, 7 do
    exs_mcp23s17.setup(0x00 + i, 0)  -- PA0~PA7 输出模式
    exs_mcp23s17.setup(0x10 + i)     -- PB0~PB7 输入模式
    exs_mcp23s17.set_pullup(0x10 + i, true)  -- PB 口启用上拉
end

-- 读取 PB 口所有引脚电平
local function read_port_b()
    for i = 0, 7 do
        local level = exs_mcp23s17.get(0x10 + i)
        log.info("exs_mcp23s17", string.format("PB%d 电平: %d", i, level))
    end
end

-- 流水灯效果
local function led_chase()
    while true do
        for i = 0, 7 do
            exs_mcp23s17.set(0x00 + i, 1)
            sys.wait(100)
            exs_mcp23s17.set(0x00 + i, 0)
        end
    end
end

sys.taskInit(led_chase)
sys.taskInit(function()
    while true do
        read_port_b()
        sys.wait(2000)
    end
end)
```

---

## **三、常量解释**

扩展库常量，顾名思义是由合宙 LuatOS 扩展库中定义的、不可重新赋值或修改的固定值，在脚本代码中不需要声明，可直接调用，本扩展库没有常量。

---

## **四、函数详解**

### **4.1 初始化与控制**

#### **4.1.1 exs_mcp23s17.init(spi_id, cs_pin, gpio_int_id, bandrate, hw_addr)**

**功能**

初始化 MCP23S17，配置 SPI 通信参数，支持硬件地址（A2A1A0）配置

**参数**

spi_id

```
参数含义：主机使用的 SPI ID，用来控制 MCP23S17
数据类型：number
取值范围：仅支持 0 和 1
是否必选：是
注意事项：平台有效的 SPI 总线编号（如 0）
参数示例：0
```

cs_pin

```
参数含义：主机使用的片选引脚 GPIO ID，与 MCP23S17 的 CS 引脚相连
数据类型：number
取值范围：有效的 GPIO 编号
是否必选：是
注意事项：片选由软件 GPIO 控制，拉低选中、拉高释放
参数示例：8
```

gpio_int_id

```
参数含义：主机使用的中断引脚 GPIO ID，与 MCP23S17 的 INT 引脚相连
数据类型：number
取值范围：有效的 GPIO 编号
是否必选：否
注意事项：可选，不传则不使用中断通知功能。传入后，MCP23S17 上配置为中断模式的 GPIO 电平变化时，会通过 INT 引脚触发主机中断
参数示例：2
```

bandrate

```
参数含义：SPI 通信波特率
数据类型：number
取值范围：1 ~ 10000000（MCP23S17 最高支持 10MHz）
是否必选：否
注意事项：可选，默认 1000000（1MHz）。杜邦线连接建议保持 1MHz，PCB 直连可适当提高
参数示例：1000000
```

hw_addr

```
参数含义：MCP23S17 硬件地址（A2A1A0）
数据类型：number
取值范围：0 ~ 7
是否必选：否
注意事项：可选，默认 0（A0/A1/A2 全部接地）。使用非 0 地址时，扩展库会自动先以地址 0 使能 IOCON 寄存器的 HAEN 位
参数示例：0
```

**返回值**

local init_result = exs_mcp23s17.init(spi_id, cs_pin, gpio_int_id, bandrate, hw_addr)

init_result

```
含义说明：初始化是否成功
数据类型：boolean
取值范围：true（成功）, false（失败）
注意事项：初始化失败时请检查接线、供电和硬件地址配置
返回示例：true
```

**示例**

```lua
-- 基础初始化（不使用中断）
local result = exs_mcp23s17.init(0, 8)

-- 使用中断功能（主机 GPIO2 作为中断引脚）
local result = exs_mcp23s17.init(0, 8, 2)

-- 完整参数：2MHz 波特率，硬件地址 3
local result = exs_mcp23s17.init(0, 8, 2, 2000000, 3)
```

---

#### **4.1.2 exs_mcp23s17.deinit()**

**功能**

关闭 MCP23S17 通信，释放所有资源（SPI、GPIO、中断表）

**参数**

无

**返回值**

local result = exs_mcp23s17.deinit()

result

```
含义说明：释放是否成功
数据类型：boolean
取值范围：true（成功）
注意事项：释放后所有 GPIO 配置将失效，如需使用需重新 init
返回示例：true
```

**示例**

```lua
exs_mcp23s17.deinit()
```

---

### **4.2 GPIO 配置与操作**

#### **4.2.1 exs_mcp23s17.setup(gpio_id, gpio_mode)**

**功能**

配置 MCP23S17 扩展 GPIO 管脚功能，支持输出、输入和中断三种模式

**参数**

gpio_id

```
参数含义：MCP23S17 上的扩展 GPIO ID
数据类型：number
取值范围：
  - 0x00 ~ 0x07：Port A 的 GPA0 ~ GPA7
  - 0x10 ~ 0x17：Port B 的 GPB0 ~ GPB7
是否必选：是
注意事项：超出范围将返回错误
参数示例：0x00
```

gpio_mode

```
参数含义：GPIO 工作模式，支持三种类型
数据类型：number | function | nil
取值说明：
  - number (0)：输出模式，默认输出低电平
  - number (1)：输出模式，默认输出高电平
  - nil 或不传：输入模式
  - function：中断模式，参数为回调函数
    回调函数格式：function cb_func(id, level) end
    - id：触发中断的 GPIO ID（number 类型）
    - level：触发中断后读取到的电平（0=低，1=高）
是否必选：是
注意事项：中断模式需要在 init() 中传入 gpio_int_id 参数
参数示例：0
```

**返回值**

local result = exs_mcp23s17.setup(gpio_id, gpio_mode)

result

```
含义说明：配置是否成功
数据类型：boolean
取值范围：true（成功）, false（失败）
注意事项：配置中断模式时，需确保 init() 已配置 gpio_int_id
返回示例：true
```

**示例**

```lua
-- GPIO 0x00 配置为输出模式，默认输出低电平
exs_mcp23s17.setup(0x00, 0)

-- GPIO 0x11 配置为输入模式
exs_mcp23s17.setup(0x11)

-- GPIO 0x04 配置为中断模式
local function PA4_int_cbfunc(id, level)
    log.info("PA4_int_cbfunc", id, level)
end
exs_mcp23s17.setup(0x04, PA4_int_cbfunc)
```

---

#### **4.2.2 exs_mcp23s17.set(gpio_id, output_level)**

**功能**

设置 MCP23S17 扩展 GPIO 的输出电平

**参数**

gpio_id

```
参数含义：MCP23S17 上的扩展 GPIO ID
数据类型：number
取值范围：0x00~0x07 或 0x10~0x17
是否必选：是
注意事项：必须先通过 setup() 配置为输出模式
参数示例：0x03
```

output_level

```
参数含义：输出电平
数据类型：number
取值范围：0（低电平）或 1（高电平）
是否必选：是
注意事项：只有配置为输出模式的 GPIO 才能设置电平
参数示例：1
```

**返回值**

local result = exs_mcp23s17.set(gpio_id, output_level)

result

```
含义说明：设置是否成功
数据类型：boolean
取值范围：true（成功）, false（失败）
注意事项：
返回示例：true
```

**示例**

```lua
-- GPIO 0x03 输出高电平
exs_mcp23s17.set(0x03, 1)

-- GPIO 0x13 输出低电平
exs_mcp23s17.set(0x13, 0)
```

---

#### **4.2.3 exs_mcp23s17.get(gpio_id)**

**功能**

读取 MCP23S17 扩展 GPIO 的输入电平

**参数**

gpio_id

```
参数含义：MCP23S17 上的扩展 GPIO ID
数据类型：number
取值范围：0x00~0x07 或 0x10~0x17
是否必选：是
注意事项：
参数示例：0x11
```

**返回值**

local level = exs_mcp23s17.get(gpio_id)

level

```
含义说明：GPIO 输入电平
数据类型：number
取值范围：0（低电平），1（高电平）；读取失败返回 nil
注意事项：读取的是实际引脚状态（GPIO 寄存器），而非输出锁存值
返回示例：1
```

**示例**

```lua
-- 读取 GPIO 0x11 的输入电平
local level = exs_mcp23s17.get(0x11)
if level ~= nil then
    log.info("exs_mcp23s17", "GPIO 0x11 电平:", level)
end
```

---

#### **4.2.4 exs_mcp23s17.close(gpio_id)**

**功能**

关闭 MCP23S17 扩展 GPIO 功能，恢复为默认输入模式

**参数**

gpio_id

```
参数含义：MCP23S17 上的扩展 GPIO ID
数据类型：number
取值范围：0x00~0x07 或 0x10~0x17
是否必选：是
注意事项：
参数示例：0x03
```

**返回值**

local result = exs_mcp23s17.close(gpio_id)

result

```
含义说明：关闭是否成功
数据类型：boolean
取值范围：true（成功）, false（失败）
注意事项：
返回示例：true
```

**示例**

```lua
exs_mcp23s17.close(0x03)
```

---

### **4.3 上拉电阻与极性反转**

#### **4.3.1 exs_mcp23s17.set_pullup(gpio_id, enable)**

**功能**

配置 MCP23S17 扩展 GPIO 的内部上拉电阻

MCP23S17 内置可选的上拉电阻（典型值 100kΩ），启用后可减少外部上拉电阻需求。

**参数**

gpio_id

```
参数含义：MCP23S17 上的扩展 GPIO ID
数据类型：number
取值范围：0x00~0x07 或 0x10~0x17
是否必选：是
注意事项：
参数示例：0x02
```

enable

```
参数含义：是否启用内部上拉电阻
数据类型：boolean
取值范围：true（启用）、false（禁用）
是否必选：是
注意事项：内部上拉电阻典型值为 100kΩ，如需更强上拉仍需外部电阻
参数示例：true
```

**返回值**

local result = exs_mcp23s17.set_pullup(gpio_id, enable)

result

```
含义说明：设置是否成功
数据类型：boolean
取值范围：true（成功）, false（失败）
注意事项：
返回示例：true
```

**示例**

```lua
-- 启用 GPIO 0x02 的内部上拉电阻
exs_mcp23s17.set_pullup(0x02, true)

-- 禁用 GPIO 0x02 的内部上拉电阻
exs_mcp23s17.set_pullup(0x02, false)
```

---

#### **4.3.2 exs_mcp23s17.set_polarity(gpio_id, invert)**

**功能**

设置 MCP23S17 扩展 GPIO 的极性反转

极性反转后，引脚实际为高电平时读取为 0，实际为低电平时读取为 1。适用于需要反相读取的硬件设计场景。

**参数**

gpio_id

```
参数含义：MCP23S17 上的扩展 GPIO ID
数据类型：number
取值范围：0x00~0x07 或 0x10~0x17
是否必选：是
注意事项：
参数示例：0x02
```

invert

```
参数含义：是否反转极性
数据类型：boolean
取值范围：true（反转）、false（正常）
是否必选：是
注意事项：极性反转仅影响输入读取，不影响输出
参数示例：true
```

**返回值**

local result = exs_mcp23s17.set_polarity(gpio_id, invert)

result

```
含义说明：设置是否成功
数据类型：boolean
取值范围：true（成功）, false（失败）
注意事项：
返回示例：true
```

**示例**

```lua
-- 反转 GPIO 0x02 的极性
exs_mcp23s17.set_polarity(0x02, true)

-- 恢复正常极性
exs_mcp23s17.set_polarity(0x02, false)
```

---

### **4.4 版本管理**

#### **4.4.1 exs_mcp23s17.version()**

**功能**

获取 exs_mcp23s17 库的版本号

**参数**

无

**返回值**

local ver = exs_mcp23s17.version()

ver

```
含义说明：版本号字符串
数据类型：string
取值范围：格式 "yyyymmddhhmm"，表示 yyyy年mm月dd日hh时mm分发布的版本
注意事项：无
返回示例："202608241200"
```

**示例**

```lua
local ver = exs_mcp23s17.version()
log.info("exs_mcp23s17", "版本号:", ver)
```

---

## **五、版本更新说明**

### 版本号：202608241200

1. 更新时间：2026-08-24
2. 更新内容：

    - 第一版，实现 MCP23S17 基础驱动功能
- SPI 通信方式驱动（与 MCP23017 的 I2C 方式不同，本库使用 SPI 总线）
    - 支持硬件地址配置（A2A1A0，0~7），单条 SPI 总线最多挂载 8 片
- 支持 16 个 GPIO 的输入、输出、中断配置（0x00-0x07 Port A，0x10-0x17 Port B）
    - 支持上拉电阻配置
- 支持极性反转
    - 支持 GPIO 中断模式（通过 INT 引脚 + sys.publish 机制）

---

## **六、产品支持说明**

所有支持 luatos 二次开发的模块，具体可以查看[选型手册](https://docs.openluat.com/air780epm/common/product/)。
