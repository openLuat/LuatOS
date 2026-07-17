# QMC5883L 三轴地磁传感器演示

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口
2. **qmc5883l_demo.lua** - QMC5883L 功能演示模块

### 1.2 扩展库模块

1. **exs_qmc5883l** - QMC5883L 扩展库，提供初始化、三轴磁场数据读取、量程切换、输出速率切换、睡眠/唤醒、关闭等 API

## 二、演示流程介绍

本 demo 按顺序演示 exs_qmc5883l 扩展库的 4 项功能：HELLO → [1/4] → [2/4] → [3/4] → [4/4] → End

### 2.1 功能演示项说明

1. **[1/4] 初始化与数据读取**
2. **[2/4] 量程切换演示** - ±2G / ±8G
3. **[3/4] 输出速率切换** - 10 / 50 / 100 / 200Hz
4. **[4/4] 休眠与唤醒演示** - 演示 sleep()/wakeup() 待机与唤醒

## 三、显示效果

![](https://docs.openluat.com/cdn/image/Air8000_qmc5883l.png)

## 四、演示硬件环境

### 3.1 硬件清单

- Air8000 核心板 × 1
- QMC5883L 传感器模块 × 1
  demo所演示的QMC5883L 三轴地磁传感器模块[购买链接](https://detail.tmall.com/item.htm?abbucket=12&id=41286452886&mi_id=0000mL_358u9JOlcX4nXEexqz-sHmWlRSDzJVprt2nO-dBw&ns=1&priceTId=215045e417839191910527013e1198&skuId=5886090880527&spm=a21n57.1.hoverItem.10&utparam=%7B%22aplus_abtest%22%3A%22dc3bc40800adf636989efd96ef16c269%22%7D&xxc=taobaoSearch)
- 母对母杜邦线 × 5
- TYPE-C 数据线 × 1

### 3.2 接线配置

#### 3.2.1 QMC5883L 模块接线

<table>
<tr>
<td>Air8000 核心板<br/></td><td>QMC5883L 模块<br/></td></tr>
<tr>
<td>GPIO1<br/></td><td>SCL<br/></td></tr>
<tr>
<td>GPIO2<br/></td><td>SDA<br/></td></tr>
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
- **qmc5883l_demo.lua** - 演示模块
- **exs_qmc5883l** - 扩展库

## 六、演示核心步骤

### 6.1 软件配置

在 `main.lua` 中加载演示模块：

```lua
require "qmc5883l_demo"
```

### 6.2 软件烧录

1. 使用 Luatools 选择最新内核固件
2. 下载本项目所有脚本文件
3. 烧录到设备后自动重启运行

### 6.3 故障排除

1. **初始化失败**：检查接线和 I2C 地址（0x0D）
2. **数据始终为零**：检查供电和接线
3. **I2C 总线锁死**：本库已内置 I2C 总线卡死自动检测与恢复功能
