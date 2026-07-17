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


## 三、演示硬件环境

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
![](https://docs.openluat.com/cdn/image/Air8000_exs_lis2dh12.png)

## 四、演示软件环境

### 4.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/)

### 4.2 内核固件

- [点击下载Air8000固件](https://docs.openluat.com/air8000/luatos/firmware/)，demo使用 LuatOS-SoC_V2046_Air8000 1号固件

### 4.3 脚本文件

- **main.lua** - 程序入口
- **lis2dh12_demo.lua** - LIS2DH12 功能演示模块
- **exs_lis2dh12** - LIS2DH12 扩展库

## 五、演示核心步骤

### 5.1 硬件准备

1. 按照接线表将 CJMCU-LIS2DH12 模块连接到核心板
2. 确保电源连接正确，通过 TYPE-C USB 口供电
3. 检查所有接线无误，避免短路

### 5.2 软件配置

在 `main.lua` 中加载对应的演示模块：

```lua
-- 加载 lis2dh12_demo.lua 演示模块
require "lis2dh12_demo"
```

### 5.3 软件烧录

1. 使用 Luatools 选择最新内核固件
2. 下载本项目所有脚本文件
3. 将固件和脚本一起烧录到设备
4. 烧录成功后设备自动重启后开始运行

### 5.4 功能测试

#### 5.4.1 初始化与数据读取演示

1. 设备启动后打印 "HELLO"，随后自动进入 [1/5] 初始化与数据读取
2. 观察日志输出，确认初始化成功
3. 观察三轴加速度数据（X/Y/Z，单位 g）的连续读取

#### 5.4.2 量程切换演示

1. 自动进入 [2/5] 量程切换演示
2. 观察 ±4g 宽范围量程下的数据
3. 观察 ±2g 高精度量程下的数据

#### 5.4.3 输出速率切换演示

1. 自动进入 [3/5] 输出速率切换演示
2. 依次观察 25Hz / 50Hz / 100Hz / 200Hz 下的数据读取
3. 最终恢复为 100Hz

#### 5.4.4 温度读取演示

1. 自动进入 [4/5] 温度读取演示
2. 使能温度传感器并等待稳定
3. 读取并显示芯片温度（单位 °C）

#### 5.4.5 休眠与唤醒演示

1. 自动进入 [5/5] 休眠与唤醒演示
2. 观察 sleep() 进入待机模式
3. 观察 wakeup() 唤醒后数据恢复

### 5.5 预期效果

- **初始化与数据读取**：LIS2DH12 初始化成功，三轴加速度数据正常输出
- **量程切换**：量程切换后数据范围随之变化，灵敏度不同
- **输出速率切换**：不同速率下均能正常读取数据
- **温度读取**：正常读取芯片温度（约 20-40°C）
- **休眠与唤醒**：sleep 后进入低功耗，wakeup 后数据读取正常

### 5.6 故障排除

1. **传感器初始化失败**：

   - 检查 LIS2DH12 接线是否正确（SCL、SDA、VCC、GND）
   - 确认 GPIO 引脚配置与接线一致
   - 检查电源电压是否稳定（3.3V）
   - 确认 exs_lis2dh12 扩展库已正常加载

2. **读取数据始终为零**：

   - 检查传感器供电是否正常
   - 检查 I2C 地址是否正确（SA0=GND 时地址 0x18，SA0=VCC 时地址 0x19）
   - 确认接线无松动

3. **量程切换无效果**：

   - 确认 `set_range()` 参数为 "2g"、"4g"、"8g" 或 "16g"
   - 切换后需等待传感器稳定再读取数据

4. **温度读取失败**：

   - 确认已在 setup 时设置 `enable_temp = true` 或调用 `enable_temp(true)`
   - 使能后需等待约 200ms 让 ADC 稳定

### 5.7 扩展功能建议

exs_lis2dh12 更多接口的使用可以查看 [exs_lis2dh12 扩展库说明](https://docs.openluat.com/osapi/ext/sensor/exs_lis2dh12/)

