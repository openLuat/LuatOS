# QMC5883L 三轴地磁传感器演示

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口
2. **qmc5883l_demo.lua** - QMC5883L 功能演示模块

### 1.2 扩展库模块

1. **exs_qmc5883l** - QMC5883L 扩展库

## 二、演示流程介绍

本 demo 按顺序演示 exs_qmc5883l 扩展库的 3 项功能：HELLO → [1/3] → [2/3] → [3/3] → End

### 2.1 功能演示项说明

1. **[1/3] 初始化与数据读取**
2. **[2/3] 量程切换演示** - ±2G / ±8G
3. **[3/3] 输出速率切换** - 10 / 50 / 100 / 200Hz

## 三、演示硬件环境

### 3.1 硬件清单

- Air8000 核心板 × 1
- QMC5883L 传感器模块 × 1
- 母对母杜邦线 × 5
- TYPE-C 数据线 × 1

### 3.2 接线配置

#### 3.2.1 QMC5883L 模块接线

<table>
<tr>
<td>Air8000 核心板<br/></td><td>QMC5883L 模块<br/></td></tr>
<tr>
<td>1/GPIO1<br/></td><td>SCL<br/></td></tr>
<tr>
<td>2/GPIO2<br/></td><td>SDA<br/></td></tr>
<tr>
<td>VDD_EXT<br/></td><td>VCC<br/></td></tr>
<tr>
<td>GND<br/></td><td>GND<br/></td></tr>
</table>

> 说明：接线表参考同型号 tm1638 的 readme。

## 四、演示软件环境

### 4.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)

### 4.2 内核固件

- [点击下载Air8000固件](https://docs.openluat.com/air8000/luatos/firmware/)，demo使用 LuatOS-SoC_V2046_Air8000 1号固件

### 4.3 脚本文件

- **main.lua** - 程序入口
- **qmc5883l_demo.lua** - 演示模块
- **exs_qmc5883l** - 扩展库

## 五、演示核心步骤

### 5.1 软件配置

在 `main.lua` 中加载演示模块：

```lua
require "qmc5883l_demo"
```

### 5.2 软件烧录

1. 使用 Luatools 选择最新内核固件
2. 下载本项目所有脚本文件
3. 烧录到设备后自动重启运行

### 5.3 故障排除

1. **初始化失败**：检查接线和 I2C 地址（0x0D）
2. **数据始终为零**：检查供电和接线
3. **I2C 总线锁死**：推荐使用软件 I2C，可自动恢复
