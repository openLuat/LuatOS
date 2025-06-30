# 第一层：应用层 (Lua脚本)

## 层级定位
应用层是LuatOS架构的最顶层，开发者主要在这一层编写业务逻辑代码。这一层使用Lua脚本语言，提供了简洁易懂的开发体验。

## 主要特点

### 1. 脚本化开发
- **语言**: Lua 5.3.5
- **特点**: 动态类型、自动内存管理、协程支持
- **优势**: 降低嵌入式开发门槛，快速原型开发

### 2. 事件驱动模型
应用层基于事件驱动模型，通过sys库提供的任务调度机制运行：

```lua
-- 典型的应用层代码结构
local sys = require "sys"

-- 任务函数
sys.taskInit(function()
    while true do
        -- 业务逻辑
        log.info("应用运行中")
        sys.wait(1000) -- 等待1秒
    end
end)

-- 启动系统
sys.run()
```

### 3. 丰富的API库
应用层可以调用74个核心库和55个扩展库：

```lua
-- GPIO操作
gpio.setup(1, 0, gpio.PULLUP)
gpio.set(1, 1)

-- SPI通信
local spi_device = spi.deviceSetup(0, 8, 0, 0, 8, 20000000, spi.MSB, 1, 0)
spi.deviceSend(spi_device, "test")

-- 网络操作
http.request("GET", "http://httpbin.org/get", nil, nil, {}, function(code, headers, body)
    log.info("HTTP响应", code, body)
end)
```

## 核心组件分析

### 1. sys库 - 系统核心
```lua
-- 位置: script/corelib/sys.lua
-- 功能: 提供任务调度、定时器、消息订阅发布机制

-- 任务创建
sys.taskInit(task_function, ...)

-- 定时器
sys.timerStart(callback, timeout, ...)

-- 消息机制
sys.publish("EVENT_NAME", data)
sys.subscribe("EVENT_NAME", callback)
```

### 2. 库调用机制
应用层通过require机制加载库：

```lua
-- 核心库加载（C实现）
local gpio = require "gpio"
local spi = require "spi"

-- 扩展库加载（Lua实现）
local sensor = require "libs.sensor"
local http = require "libs.http"
```

### 3. 主程序入口
每个LuatOS应用都从`main.lua`开始执行：

```lua
-- main.lua - 应用程序入口
PROJECT = "demo"
VERSION = "1.0.0"

-- 系统库加载
sys = require("sys")

-- 初始化代码
-- ...

-- 启动系统调度
sys.run()
```

## 与下层的接口

### 1. 库函数调用
应用层通过库函数调用与LuatOS框架层交互：

```lua
-- Lua调用 -> C函数 -> 硬件操作
gpio.set(1, 1) -- Lua代码
-- ↓
-- luat_lib_gpio.c: l_gpio_set() -- C函数
-- ↓  
-- luat_gpio_set() -- 硬件抽象层
```

### 2. 事件回调
硬件事件通过回调机制传递到应用层：

```lua
-- GPIO中断回调
gpio.setup(1, gpio.IRQ, gpio.RISING, function(pin, level)
    log.info("GPIO中断", pin, level)
end)
```

### 3. 消息总线
应用层通过消息总线与系统其他部分通信：

```lua
-- 发布系统消息
sys.publish("NET_READY")

-- 订阅系统事件
sys.subscribe("SIM_READY", function()
    log.info("SIM卡就绪")
end)
```

## 开发模式

### 1. 任务模式
```lua
-- 协程任务，支持阻塞等待
sys.taskInit(function()
    while true do
        local result = sys.waitUntil("NETWORK_READY", 30000)
        if result then
            -- 网络就绪，执行网络操作
        end
    end
end)
```

### 2. 回调模式
```lua
-- 事件驱动回调
uart.setup(1, 115200, 8, 1, uart.None, uart.LSB)
uart.on(1, "receive", function(id, len)
    local data = uart.read(id, len)
    log.info("收到数据", data)
end)
```

### 3. 定时器模式
```lua
-- 定时执行
sys.timerLoopStart(function()
    log.info("定时任务执行")
end, 5000) -- 每5秒执行一次
```

## 典型应用示例

### 1. LED闪烁
```lua
local sys = require "sys"

-- LED控制任务
sys.taskInit(function()
    gpio.setup(1, 0) -- 配置为输出
    while true do
        gpio.set(1, 1) -- 点亮
        sys.wait(500)
        gpio.set(1, 0) -- 熄灭
        sys.wait(500)
    end
end)

sys.run()
```

### 2. 传感器数据采集
```lua
local sys = require "sys"
local sensor = require "libs.aht10"

sys.taskInit(function()
    sensor.init(0) -- I2C0初始化传感器
    while true do
        local temp, humi = sensor.get_data()
        log.info("温湿度", temp, humi)
        sys.wait(2000)
    end
end)

sys.run()
```

## 调试和开发工具

### 1. 日志系统
```lua
-- 不同级别的日志
log.trace("trace", "详细调试信息")
log.debug("debug", "调试信息") 
log.info("info", "一般信息")
log.warn("warn", "警告信息")
log.error("error", "错误信息")
```

### 2. 内存监控
```lua
-- 内存使用情况
log.info("内存使用", rtos.meminfo())
collectgarbage("collect") -- 手动垃圾回收
```

### 3. 错误处理
```lua
-- 异常处理
local ok, err = pcall(function()
    -- 可能出错的代码
end)
if not ok then
    log.error("执行出错", err)
end
```

## 性能优化

### 1. 内存管理
- 及时释放大对象
- 避免创建过多临时变量
- 合理使用collectgarbage()

### 2. 任务调度
- 避免长时间阻塞任务
- 合理使用sys.wait()
- 分解复杂任务

### 3. 资源使用
- 及时关闭不用的外设
- 合理配置缓冲区大小
- 避免频繁的硬件操作

应用层作为用户直接接触的层面，提供了简洁而强大的开发接口，让开发者能够专注于业务逻辑的实现，而无需关心底层硬件的复杂性。 