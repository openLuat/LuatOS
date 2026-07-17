# QMC5883L 三轴地磁传感器演示

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责项目初始化、版本定义和任务调度
2. **qmc5883l_demo.lua** - QMC5883L 功能演示模块，包含数据读取、量程切换、输出速率切换等所有功能的演示用例

### 1.2 扩展库模块

1. **exs_qmc5883l** - QMC5883L 扩展库，提供初始化、三轴磁场数据读取、量程切换、输出速率切换、睡眠/唤醒、关闭等 API

### 1.3 I2C 模式说明

**推荐使用软件 I2C 模式**：QMC5883L 在异常 I2C 通信后可能锁死 SDA 总线。本库已内置 I2C 总线卡死自动检测与恢复功能。本 demo 使用软件 I2C 模式演示。

## 二、演示流程介绍

本 demo 按顺序演示 exs_qmc5883l 扩展库的 4 项功能：HELLO → [1/4] → [2/4] → [3/4] → [4/4] → End

### 2.1 功能演示项说明

1. **[1/4] 初始化与数据读取** - 初始化 QMC5883L 传感器并读取三轴磁场数据（X/Y/Z，单位 μT）
2. **[2/4] 量程切换演示** - 在 ±2G（高精度）和 ±8G（宽范围）量程之间切换，观察数据变化
3. **[3/4] 输出速率切换** - 依次切换 10Hz / 50Hz / 100Hz / 200Hz 输出速率
4. **[4/4] 休眠与唤醒演示** - 演示 sleep()/wakeup() 待机与唤醒

## 三、显示效果

![](https://docs.openluat.com/cdn/image/Air780EHM_qmc5883l.png)

## 四、演示硬件环境

### 3.1 硬件清单

- Air780EHM / Air780EHV / Air780EGH 核心板 × 1
- QMC5883L 三轴地磁传感器模块 × 1
  demo所演示的QMC5883L 三轴地磁传感器模块[购买链接](https://detail.tmall.com/item.htm?abbucket=12&id=41286452886&mi_id=0000mL_358u9JOlcX4nXEexqz-sHmWlRSDzJVprt2nO-dBw&ns=1&priceTId=215045e417839191910527013e1198&skuId=5886090880527&spm=a21n57.1.hoverItem.10&utparam=%7B%22aplus_abtest%22%3A%22dc3bc40800adf636989efd96ef16c269%22%7D&xxc=taobaoSearch)
- 母对母杜邦线 × 5
- TYPE-C 数据线 × 1

### 3.2 接线配置

#### 3.2.1 QMC5883L 模块接线

<table>
<tr>
<td>Air780EHM/Air780EHV/Air780EGH 核心板<br/></td><td>QMC5883L 模块<br/></td></tr>
<tr>
<td>32/GPIO31<br/></td><td>SCL<br/></td></tr>
<tr>
<td>31/GPIO30<br/></td><td>SDA<br/></td></tr>
<tr>
<td>VDD_EXT<br/></td><td>VCC<br/></td></tr>
<tr>
<td>GND<br/></td><td>GND<br/></td></tr>
</table>

> 说明：接线时注意杜邦线不宜过长，以免通信不稳定。

## 五、演示软件环境

### 5.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air780egh/luatos/common/download/) - 固件烧录和代码调试

### 5.2 内核固件

- [点击下载Air780EHM系列最新版本内核固件](https://docs.openluat.com/air780epm/luatos/firmware/780ehm_version/)，demo所使用的是 LuatOS-SoC_V2046_Air780EHM 1号固件

- [点击下载Air780EHV系列最新版本内核固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)，demo所使用的是 LuatOS-SoC_V2046_Air780EHV 1号固件

- [点击下载Air780EGH系列最新版本内核固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)，demo所使用的是 LuatOS-SoC_V2046_Air780EGH 1号固件

### 5.3 脚本文件

1. **main.lua** - 程序入口
2. **qmc5883l_demo.lua** - QMC5883L 功能演示模块
3. **exs_qmc5883l** - QMC5883L 扩展库

## 六、演示核心步骤

### 6.1 硬件准备

1. 按照接线表将 QMC5883L 模块连接到核心板
2. 确保电源连接正确，通过 TYPE-C USB 口供电
3. 检查所有接线无误，避免短路

### 6.2 软件配置

在 `main.lua` 中加载对应的演示模块：

```lua
-- 加载 qmc5883l_demo.lua 演示模块
require "qmc5883l_demo"

```

### 6.3 软件烧录

1. 使用 Luatools 选择最新内核固件
2. 下载本项目所有脚本文件
3. 将固件和脚本一起烧录到设备
4. 烧录成功后设备自动重启后开始运行

### 6.4 功能测试

#### 6.4.1 初始化与数据读取演示

1. 设备启动后打印 "HELLO"，随后自动进入 [1/4] 初始化与数据读取
2. 观察日志输出，确认初始化成功
3. 观察三轴磁场数据（X/Y/Z，单位 μT）的连续读取

#### 6.4.2 量程切换演示

1. 自动进入 [2/4] 量程切换演示
2. 观察 ±2G 高精度量程下的数据
3. 观察 ±8G 宽范围量程下的数据

#### 6.4.3 输出速率切换演示

1. 自动进入 [3/4] 输出速率切换演示
2. 依次观察 10Hz / 50Hz / 100Hz / 200Hz 下的数据读取
3. 最终恢复为 10Hz

#### 6.4.4 休眠与唤醒演示

1. 自动进入 [4/4] 休眠与唤醒演示
2. 观察 sleep() 进入待机模式
3. 观察 wakeup() 唤醒后数据恢复

### 6.5 预期效果

- **初始化与数据读取**：QMC5883L 初始化成功，三轴磁场数据正常输出
- **量程切换**：量程切换后数据范围随之变化，灵敏度不同
- **输出速率切换**：不同速率下均能正常读取数据
- **休眠与唤醒**：sleep 后进入低功耗，wakeup 后数据读取正常

### 6.6 故障排除

1. **传感器初始化失败**：

   - 检查 QMC5883L 接线是否正确（SCL、SDA、VCC、GND）
   - 确认 GPIO 引脚配置与接线一致
   - 检查电源电压是否稳定（3.3V）
   - 确认 exs_qmc5883l 扩展库已正常加载

2. **读取数据始终为零**：

   - 检查传感器供电是否正常
   - 检查 I2C 地址是否正确（QMC5883L 7 位地址为 0x0D，写操作地址 0x1A）
   - 确认接线无松动

3. **量程切换无效果**：

   - 确认 `set_range()` 参数为 "2G" 或 "8G"
   - 切换后需等待传感器稳定再读取数据

### 6.7 扩展功能建议

exs_qmc5883l 更多接口的使用可以查看 [exs_qmc5883l 扩展库说明](https://docs.openluat.com/osapi/ext/sensor/exs_qmc5883l/)
