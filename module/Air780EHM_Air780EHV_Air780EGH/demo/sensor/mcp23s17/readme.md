# MCP23S17 GPIO 扩展应用功能演示

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责项目初始化、版本定义和任务调度
2. **mcp23s17_demo** - MCP23S17 功能演示模块，包含 GPIO 输出测试、输入测试、GPIO 中断测试、上拉电阻测试功能的演示用例

### 1.2 扩展库模块

1. **exs_mcp23s17** - MCP23S17 扩展库，提供 SPI 初始化、配置扩展 GPIO 管脚功能、设置输出电平、读取输入电平、上拉电阻配置等 API

## 二、演示流程介绍

本 demo 按顺序演示 exs_mcp23s17 扩展库的 4 项功能：GPIO 输出测试、GPIO 输入测试、GPIO 中断测试、上拉电阻测试

### 2.1 功能演示项说明

1. MCP23S17 扩展 GPIO 输出测试
2. MCP23S17 扩展 GPIO 输入测试
3. MCP23S17 扩展 GPIO 中断测试
4. MCP23S17 内部上拉电阻测试

## 三、演示硬件环境

### 3.1 硬件清单

- Air780EHV 核心板 × 1

- MCP23S17 GPIO 扩展模块 × 1，购买链接：[https://e.tb.cn/h.8454O6wnpxKLXEF?tk=x69VgwEa5H8](https://e.tb.cn/h.8454O6wnpxKLXEF?tk=x69VgwEa5H8)

- 母对母杜邦线 × 14

- TYPE-C 数据线 × 1

![](https://docs.openluat.com/osapi/ext/image/780ehv-mcp23s17.png)

### 3.2 接线配置

#### 3.2.1 MCP23S17 模块接线（硬件 SPI）

<table>
<tr>
<td>Air780EHV 核心板</td><td>MCP23S17</td>
</tr>
<tr>
<td>86 / SPI0_SLK</td><td>SCK</td>
</tr>
<tr>
<td>85 / SPI0_MOSI</td><td>SI</td>
</tr>
<tr>
<td>84 / SPI0_MISO</td><td>SO</td>
</tr>
<tr>
<td>83 / SPI0_CS</td><td>CS</td>
</tr>
<tr>
<td>23 / GPIO2</td><td>INT</td>
</tr>
<tr>
<td>3V3</td><td>VDD</td>
</tr>
<tr>
<td>GND</td><td>GND</td>
</tr>
<tr>
<td>GND</td><td>A0/A1/A2</td>
</tr>
</table>


## 四、演示软件环境

### 4.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air780ehv/luatos/common/download/)

### 4.2 内核固件

- [点击下载Air780EHV系列最新版本内核固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)，demo 使用 LuatOS-SoC 最新版 Air780EHV 固件

### 4.3 脚本文件

1. **main.lua** - 程序入口

2. **mcp23s17_demo.lua** - 演示模块

3. **exs_mcp23s17.lua** - 扩展库

## 五、演示核心步骤

### 5.1 硬件准备

1. 按照接线表将 MCP23S17 模块连接到核心板
2. 确保电源连接正确，通过 TYPE-C USB 口供电
3. 检查所有接线无误，避免短路

### 5.2 软件配置

在 `main.lua` 中加载对应的演示模块：

```lua
-- 加载 mcp23s17_demo.lua 演示模块
require "mcp23s17_demo"
```

在 `mcp23s17_demo.lua` 顶部按实际硬件配置演示参数：

```lua
-- SPI 总线 ID（Air780EHV 仅支持 1 路 SPI0，引脚为 PIN83/84/85/86）
local SPI_ID = 0
-- 片选引脚（Air780EHV 的 SPI0_CS 默认 GPIO8）
local CS_PIN = 8
-- 中断引脚（Air780EHV GPIO2，可选，不需要中断功能时传 nil）
local INT_PIN = 2
-- SPI 波特率（默认 1MHz，MCP23S17 最高支持 10MHz）
local BANDRATE = 1000000
-- 硬件地址 A2A1A0（默认 0，A0/A1/A2 引脚接地时用 0，范围 0~7）
local HW_ADDR = 0
```

### 5.3 软件烧录

1. 使用 Luatools 选择最新内核固件
2. 下载本项目所有脚本文件
3. 将固件和脚本一起烧录到设备
4. 烧录成功后设备自动重启后开始运行

### 5.4 功能测试

#### 5.4.1 MCP23S17 扩展 GPIO 输出演示

- 扩展 GPIO 输出演示时，无需接线；通过万用表或者示波器检测 MCP23S17 板上的 PA0 电平即可
- 软件上会将 PA0 配置为输出，每隔一秒切换输出一次高低电平（低电平 0 持续 1 秒，高电平 1 持续 1 秒，如此循环输出）

#### 5.4.2 MCP23S17 扩展 GPIO 输入演示

- 扩展 GPIO 输入演示时，将 MCP23S17 板上的 PA1 和 PA2 两个引脚通过杜邦线短接
- 软件上会将 PA1 配置为输出，每隔一秒切换输出一次高低电平
- 将 PA2 配置为输入，每隔一秒调用 `get` 接口读取一次输入的电平，通过检测 PA2 引脚输入电平的状态来演示

#### 5.4.3 MCP23S17 扩展 GPIO 中断演示

- 扩展 GPIO 中断演示时，将 MCP23S17 板上的 PA4 和 PA3 两个引脚通过杜邦线短接
- 将 MCP23S17 板上的 PB4 和 PB3 两个引脚通过杜邦线短接
- 软件上会将 PA4 和 PB4 配置为输出，每隔一秒切换输出一次高低电平
- 将 PA3 配置为中断模式并绑定回调函数 `PA3_int_cbfunc`，将 PB3 配置为中断模式并绑定回调函数 `PB3_int_cbfunc`，通过检测中断函数的触发状态来演示

#### 5.4.4 MCP23S17 内部上拉电阻演示

- 上拉电阻演示时，将 PA5 配置为输入模式并启用内部上拉电阻，将 PB5 配置为输入模式并禁用内部上拉电阻
- 观察两者读取的电平差异（引脚悬空时，启用上拉的 PA5 读为高电平 1，禁用上拉的 PB5 状态不定，典型为 0）

### 5.5 预期效果

- 通过万用表或者示波器检测 MCP23S17 板上的 PA0 电平，持续 1 秒输出 0V 的低电平，持续 1 秒输出 3.3V 的高电平，循环输出，表示 GPIO 输出测试正常；
- 通过观察 Luatools 的运行日志，首先打印 `mcp23s17.get(0x02) 0`，再隔一秒打印 `mcp23s17.get(0x02) 1`，再隔一秒打印 `mcp23s17.get(0x02) 0`，如此循环输出，表示 GPIO 输入测试正常；
- 通过观察 Luatools 的运行日志，首先打印 `PA3_int_cbfunc 3 1 PB3_int_cbfunc 19 1`，再隔一秒打印 `PA3_int_cbfunc 3 0 PB3_int_cbfunc 19 0`，再隔一秒打印 `PA3_int_cbfunc 3 1 PB3_int_cbfunc 19 1`，如此循环输出，表示 GPIO 中断测试正常；
- 通过观察 Luatools 的运行日志，打印 `PA5(上拉):1  PB5(无上拉):0`，表示上拉电阻测试正常；

- **日志如下：**

```lua
[2026-08-24 18:18:26.470][000000000.250] I/user.main MCP23S17_Demo 001.999.000
[2026-08-24 18:18:26.471][000000000.267] SPI_HWInit 445:APB MP 102400000
[2026-08-24 18:18:26.471][000000000.267] SPI_HWInit 556:spi0 speed 1000000,984615,13
[2026-08-24 18:18:26.472][000000000.268] I/user.exs_mcp23s17 中断引脚已配置 2
[2026-08-24 18:18:26.472][000000000.269] I/user.exs_mcp23s17 初始化成功 spi_id=0 cs_pin=8 hw_addr=0 bandrate=1000000
[2026-08-24 18:18:26.505][000000000.269] I/user.mcp23s17 扩展库初始化成功
[2026-08-24 18:18:26.507][000000000.285] I/user.mcp23s17.get(0x05) 1
[2026-08-24 18:18:26.514][000000000.286] I/user.mcp23s17.get(0x15) 0
[2026-08-24 18:18:27.110][000000001.274] I/user.mcp23s17.get(0x02) 0
[2026-08-24 18:18:27.112][000000001.285] I/user.PA3_int_cbfunc 3 1
[2026-08-24 18:18:27.115][000000001.286] I/user.PB3_int_cbfunc 19 1
[2026-08-24 18:18:28.109][000000002.275] I/user.mcp23s17.get(0x02) 1
[2026-08-24 18:18:28.127][000000002.286] I/user.PA3_int_cbfunc 3 0
[2026-08-24 18:18:28.132][000000002.286] I/user.PB3_int_cbfunc 19 0
[2026-08-24 18:18:28.136][000000002.288] I/user.mcp23s17.get(0x05) 1
[2026-08-24 18:18:28.140][000000002.289] I/user.mcp23s17.get(0x15) 0
```
