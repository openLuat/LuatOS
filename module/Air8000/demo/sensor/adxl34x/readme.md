# ADXL345/ADXL346 三轴加速度传感器演示

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责项目初始化、版本定义和任务调度
2. **adxl34x_demo.lua** - ADXL345/ADXL346 功能演示模块，包含数据读取、量程切换、输出速率切换等所有功能的演示用例

### 1.2 扩展库模块

1. **exs_adxl34x** - ADXL345/ADXL346 扩展库，提供初始化、三轴加速度数据读取、量程切换、输出速率切换、软件复位等 API

### 1.3 I2C 模式说明

**推荐使用软件 I2C 模式**：ADXL345/ADXL346 在异常 I2C 通信后可能锁死 SDA 总线（拉低 SDA 不放）。软件 I2C 模式可用 GPIO 直接脉冲 SCL 恢复总线，硬件 I2C 模式无法恢复。本 demo 使用软件 I2C 模式演示。

## 二、演示流程介绍

本 demo 按顺序演示 exs_adxl34x 扩展库的 3 项功能：HELLO → [1/3] → [2/3] → [3/3] → End

### 2.1 功能演示项说明

1. **[1/3] 初始化与数据读取** - 初始化 ADXL345/ADXL346 传感器并读取三轴加速度数据（X/Y/Z，单位 g）
2. **[2/3] 量程切换演示** - 在 ±2g（高精度）和 ±4g（宽范围）量程之间切换，观察数据变化
3. **[3/3] 输出速率切换** - 依次切换 25Hz / 50Hz / 100Hz / 200Hz 输出速率


## 三、演示硬件环境

### 3.1 硬件清单

- Air780EHM / Air780EHV / Air780EGH 核心板 × 1
- ADXL345/ADXL346 三轴加速度传感器模块 × 1
  demo所演示的ADXL346 三轴加速度传感器模块[购买链接](https://item.taobao.com/item.htm?abbucket=12&id=674652805487&mi_id=0000HelRiVcJXLoq8Fq6jNLiArUvUR3J2pup2XI5jGtyLC8&ns=1&priceTId=2147849c17839172022585398e11c7&spm=a21n57.1.hoverItem.12&utparam=%7B%22aplus_abtest%22%3A%22418b653a98a5ab0b5f0ba7b791f3d489%22%7D&xxc=taobaoSearch)
- 母对母杜邦线 × 5
- 母对母杜邦线 × 5
- TYPE-C 数据线 × 1

![](https://docs.openluat.com/cdn/image/Air8000_ADXL36X.png)

### 3.2 接线配置

#### 3.2.1 ADXL345/ADXL346 模块接线

<table>
<tr>
<td>Air8000 核心板<br/></td><td>ADXL345/ADXL346 模块<br/></td></tr>
<tr>
<td>GPIO1<br/></td><td>SCL<br/></td></tr>
<tr>
<td>GPIO2<br/></td><td>SDA<br/></td></tr>
<tr>
<td>GPIO17<br/></td><td>INT1<br/></td></tr>
<tr>
<td>VDD_EXT<br/></td><td>VCC<br/></td></tr>
<tr>
<td>GND<br/></td><td>GND<br/></td></tr>
</table>

> 说明：接线时注意杜邦线不宜过长，以免通信不稳定。

## 四、演示软件环境

### 4.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/) - 固件烧录和代码调试

### 4.2 内核固件

- [点击下载Air8000系列最新版本内核固件](https://docs.openluat.com/air8000/luatos/firmware/)，demo所使用的是 LuatOS-SoC_V2046_Air8000_1.soc

### 4.3 脚本文件

1. **main.lua** - 程序入口
2. **adxl34x_demo.lua** - ADXL345/ADXL346 功能演示模块
3. **exs_adxl34x** - ADXL345/ADXL346 扩展库

## 五、演示核心步骤

### 5.1 硬件准备

1. 按照接线表将 ADXL345/ADXL346 模块连接到核心板
2. 确保电源连接正确，通过 TYPE-C USB 口供电
3. 检查所有接线无误，避免短路

### 5.2 软件配置

在 `main.lua` 中加载对应的演示模块：

```lua
-- 加载 adxl34x_demo.lua 演示模块
require "adxl34x_demo"
```

### 5.3 软件烧录

1. 使用 Luatools 选择最新内核固件
2. 下载本项目所有脚本文件
3. 将固件和脚本一起烧录到设备
4. 烧录成功后设备自动重启后开始运行

### 5.4 功能测试

#### 5.4.1 初始化与数据读取演示

1. 设备启动后打印 "HELLO"，随后自动进入 [1/3] 初始化与数据读取
2. 观察日志输出，确认初始化成功
3. 观察三轴加速度数据（X/Y/Z，单位 g）的连续读取

#### 5.4.2 量程切换演示

1. 自动进入 [2/3] 量程切换演示
2. 观察 ±4g 宽范围量程下的数据
3. 观察 ±2g 高精度量程下的数据

#### 5.4.3 输出速率切换演示

1. 自动进入 [3/3] 输出速率切换演示
2. 依次观察 25Hz / 50Hz / 100Hz / 200Hz 下的数据读取
3. 最终恢复为 100Hz

### 5.5 预期效果

- **初始化与数据读取**：ADXL345/ADXL346 初始化成功，三轴加速度数据正常输出
- **量程切换**：量程切换后数据范围随之变化，灵敏度不同
- **输出速率切换**：不同速率下均能正常读取数据

### 5.6 故障排除

1. **传感器初始化失败**：

   - 检查 ADXL345/ADXL346 接线是否正确（SCL、SDA、VCC、GND）
   - 确认 GPIO 引脚配置与接线一致
   - 检查电源电压是否稳定（3.3V）
   - 确认 exs_adxl34x 扩展库已正常加载

2. **读取数据始终为零**：

   - 检查传感器供电是否正常
   - 检查 I2C 地址是否正确（SDO=GND 时地址 0x53，SDO=VCC 时地址 0x1D）
   - 确认接线无松动

3. **量程切换无效果**：

   - 确认 `set_range()` 参数为 "2g"、"4g"、"8g" 或 "16g"
   - 切换后需等待传感器稳定再读取数据

### 5.7 扩展功能建议

exs_adxl34x 更多接口的使用可以查看 [exs_adxl34x 扩展库说明](https://docs.openluat.com/osapi/ext/sensor/exs_adxl34x/)
