# LIS2DH12 三轴加速度传感器演示

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口
2. **lis2dh12_demo.lua** - LIS2DH12 功能演示模块

### 1.2 扩展库模块

1. **exs_lis2dh12** - LIS2DH12 扩展库，提供初始化、三轴加速度数据读取、量程切换、输出速率切换、功耗模式切换、温度读取、睡眠/唤醒、关闭等 API

### 1.3 I2C 模式说明

**推荐使用软件 I2C 模式**：LIS2DH12 在异常 I2C 通信后可能锁死 SDA 总线。本库已内置 I2C 总线卡死自动检测与恢复功能。本 demo 使用软件 I2C 模式演示。

## 二、演示流程介绍

本 demo 按顺序演示 exs_lis2dh12 扩展库的 5 项功能：HELLO → [1/5] → [2/5] → [3/5] → [4/5] → [5/5] → End

### 2.1 功能演示项说明

1. **[1/5] 初始化与数据读取**
2. **[2/5] 量程切换演示** - ±2g / ±4g
3. **[3/5] 输出速率切换** - 25 / 50 / 100 / 200Hz
4. **[4/5] 温度读取演示**
5. **[5/5] 休眠与唤醒演示** - 演示 sleep()/wakeup() 待机与唤醒

## 三、显示效果

![](https://docs.openluat.com/cdn/image/Air8000_exs_lis2dh12.png)

## 四、演示硬件环境

### 3.1 硬件清单

- Air8000 核心板 × 1
- CJMCU-LIS2DH12 三轴加速度传感器模块 × 1
  demo所演示的LIS2DH12 三轴加速度传感器模块[购买链接](https://item.taobao.com/item.htm?abbucket=12&id=558250923931&mi_id=0000CnnCsR0FV7f0P7irmdBj13iLAdQybnwMchjjsbtxS9Q&ns=1&priceTId=215045e417839190178541937e1198&skuId=4867682785456&spm=a21n57.1.hoverItem.2&utparam=%7B%22aplus_abtest%22%3A%2259cc019145c3f9fde211bc6c0f71f883%22%7D&xxc=taobaoSearch)
- 母对母杜邦线 × 6
- TYPE-C 数据线 × 1

### 3.2 接线配置

#### 3.2.1 I2C 模式接线

<table>
<tr>
<td>Air8000 核心板<br/></td><td>CJMCU-LIS2DH12 模块<br/></td></tr>
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

## 五、演示软件环境

### 5.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)

### 5.2 内核固件

- [点击下载Air8000固件](https://docs.openluat.com/air8000/luatos/firmware/)，demo使用 LuatOS-SoC_V2046_Air8000 1号固件

### 5.3 脚本文件

- **main.lua** - 程序入口
- **lis2dh12_demo.lua** - LIS2DH12 功能演示模块
- **exs_lis2dh12** - LIS2DH12 扩展库

## 六、演示核心步骤

### 6.1 软件配置

在 `main.lua` 中加载演示模块：

```lua
require "lis2dh12_demo"
```

### 6.2 软件烧录

1. 使用 Luatools 选择最新内核固件
2. 下载本项目所有脚本文件
3. 烧录到设备后自动重启运行

### 6.3 故障排除

1. **初始化失败**：检查接线和 I2C 地址（SA0=GND 时 0x18，SA0=VCC 时 0x19）
2. **数据始终为零**：检查供电和接线
3. **I2C 总线锁死**：本库已内置 I2C 总线卡死自动检测与恢复功能
