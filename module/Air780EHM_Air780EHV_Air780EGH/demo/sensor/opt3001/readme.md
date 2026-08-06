# OPT3001 数字环境光传感器应用功能演示

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责项目初始化、版本定义和任务调度
2. **opt3001_app.lua** - OPT3001 功能演示模块，包含连续读取、单次测量、阈值中断、配置管理等演示用例

### 1.2 扩展库模块

1. **exs_opt3001** - OPT3001 扩展库，提供 I2C 初始化、照度读取、阈值设置、配置管理等 API

### 1.3 I2C 模式说明

本 demo 使用硬件 I2C（I2C1），Air780EHM/Air780EHV/Air780EGH 的 I2C1 默认引脚为：
- SCL：引脚 67
- SDA：引脚 66

OPT3001 的 I2C 速率最高支持 400kHz（i2c.FAST）。

## 二、演示流程介绍

本 demo 按顺序演示 exs_opt3001 扩展库的 4 项功能：

### 2.1 功能演示项说明

1. **[1/4] 连续读取照度** - 800ms 转换时间、自动量程、每 800ms 读取一次，共读取 10 次
2. **[2/4] 单次测量模式** - 切换为单次测量，100ms 与 800ms 转换时间对比测试
3. **[3/4] 阈值中断** - 设置 10 lux 低限 / 1000 lux 高限，通过 INT 引脚触发中断
4. **[4/4] 配置读取与软件复位** - 读取当前配置、执行软件复位、验证复位结果

> **注意**：同一时刻只允许运行一项测试任务，请根据需求注释掉不需要的测试项。

## 三、演示硬件环境

### 3.1 硬件清单

- Air780EHM/Air780EHV/Air780EGH 核心板 × 1

- OPT3001 环境光传感器模块 × 1，参考购买链接：[https://e.tb.cn/h.8UbW2HuxLd4poB1?tk=QCTngyteLSQ](https://e.tb.cn/h.8UbW2HuxLd4poB1?tk=QCTngyteLSQ)

- 母对母杜邦线 × 5

- TYPE-C 数据线 × 1

![](https://docs.openluat.com/osapi/ext/image/780ehv-opt3001.png)

### 3.2 接线配置

#### 3.2.1 OPT3001 模块接线（硬件 I2C）

<table>
<tr>
<td>Air780EHM/Air780EHV/Air780EGH 核心板</td><td>OPT3001</td></tr>
<tr>
<td>67 / I2C1_SCL</td><td>SCL</td></tr>
<tr>
<td>66 / I2C1_SDA</td><td>SDA</td></tr>
<tr>
<td>23 / GPIO2</td><td>INT（中断引脚，可选）</td></tr>
<tr>
<td>VBAT</td><td>VDD（3.3V）</td></tr>
<tr>
<td>GND</td><td>GND</td></tr>
<tr>
<td>GND</td><td>ADDR（接地→地址 0x44）</td></tr>
</table>

> **SDA/SCL 上拉电阻**：OPT3001 的 SDA 和 SCL 需要外接 4.7kΩ~10kΩ 上拉电阻到 VDD。大多数 OPT3001 模块已集成上拉电阻。

> **INT 引脚说明**：OPT3001 的 INT 为开漏输出，需要外接上拉电阻。当照度超出阈值范围时，INT 引脚变为低电平（默认极性 POL=0，低有效）。



#### 3.2.2 ADDR 引脚地址选择

| ADDR 连接 | I2C 地址 |
|-----------|----------|
| GND | 0x44（默认） |
| VDD | 0x45 |

## 四、演示软件环境

### 4.1 开发工具

- [Luatools 下载调试工具](https://docs.openluat.com/air780egh/luatos/common/download/)

### 4.2 内核固件

- [点击下载 Air780EHM 系列最新版本内核固件](https://docs.openluat.com/air780ehm/luatos/firmware/version/)，建议使用 V2048 及以后版本
- [点击下载 Air780EHV 系列最新版本内核固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)，建议使用 V2048 及以后版本
- [点击下载 Air780EGH 系列最新版本内核固件](https://docs.openluat.com/air780egh/luatos/firmware/version/)，建议使用 V2048 及以后版本

### 4.3 脚本文件

1. **main.lua** - 程序入口
2. **opt3001_app.lua** - 演示业务模块
3. **exs_opt3001.lua** - 扩展库脚本

## 五、演示核心步骤

### 5.1 硬件准备

1. 按照接线表将 OPT3001 模块连接到 Air780EHM/Air780EHV/Air780EGH 核心板
2. 确保电源连接正确，通过 TYPE-C USB 口供电
3. 检查 SDA/SCL 上拉电阻是否存在
4. 检查所有接线无误，避免短路

### 5.2 软件配置

在 `main.lua` 中加载演示模块：

```lua
-- 加载 opt3001_app.lua 演示模块
require "opt3001_app"
```

### 5.3 软件烧录

1. 使用 Luatools 选择 Air780EHM/Air780EHV/Air780EGH 对应内核固件
2. 下载本项目所有脚本文件
3. 将固件和脚本一起烧录到设备
4. 烧录成功后设备自动重启开始运行

### 5.4 功能测试

#### 5.4.1 [1/4] 连续读取照度测试

- 传感器配置为连续测量模式、800ms 转换时间、自动量程
- 每 800ms 读取一次环境光照度，共读取 10 次
- 观察日志中照度值是否随环境光变化

#### 5.4.2 [2/4] 单次测量模式测试

- 先测试 100ms 转换时间（快速测量，精度较低）
- 再测试 800ms 转换时间（慢速测量，精度较高）
- 对比两种模式下的读数差异和响应速度

#### 5.4.3 [3/4] 阈值中断测试

- 设置低限为 10 lux、高限为 1000 lux
- 遮挡传感器使照度低于 10 lux，观察是否触发下限中断
- 用强光照射使照度超过 1000 lux，观察是否触发上限中断
- 中断触发后日志中会打印中断事件

#### 5.4.4 [4/4] 配置读取与软件复位测试

- 读取当前配置寄存器值并解析显示
- 读取当前阈值设置
- 执行软件复位（恢复默认配置）
- 验证复位后配置是否正确恢复

### 5.5 预期效果

**[1/4] 连续读取日志示例：**

```
I/user.opt3001 [1/4] ★ 开始连续读取照度（自动量程，800ms 转换时间）
I/user.opt3001 照度: 158.44 lux (溢出=否)
I/user.opt3001 照度: 160.08 lux (溢出=否)
I/user.opt3001 [1/4] ✓ 连续读取完成
```

**[2/4] 单次测量日志示例：**

```
I/user.opt3001 [2/4] ★ 开始单次测量模式测试
I/user.opt3001 --- 100ms 快速模式 ---
I/user.exs_opt3001 配置已更新: mode=single ct=100ms
I/user.opt3001 [100ms] 照度: 177.28 lux
I/user.opt3001 [100ms] 照度: 168.08 lux
I/user.opt3001 --- 800ms 精确模式 ---
I/user.exs_opt3001 配置已更新: mode=single ct=800ms
I/user.opt3001 [800ms] 照度: 178.00 lux
I/user.opt3001 [800ms] 照度: 176.32 lux
I/user.exs_opt3001 配置已更新: mode=continuous ct=800ms
I/user.opt3001 [2/4] ✓ 单次测量测试完成
```

**[3/4] 阈值中断日志示例（遮挡传感器触发下限）：**

```
I/user.opt3001 [3/4] ★ 启动中断监听任务
I/user.exs_opt3001 阈值已设置: low=10.00 high=1000.00
I/user.opt3001 阈值已设置: 低限=10 lux, 高限=1000 lux
I/user.opt3001 当前阈值: 低限=10.00, 高限=1000.00
I/user.opt3001 等待中断触发（可遮挡/照射传感器改变照度）...
I/user.opt3001 [3/4] ★ 中断触发：照度低于下限阈值！
I/user.opt3001 [3/4] ✓ 阈值中断测试完成
```

**[4/4] 配置与复位日志示例：**

```
I/user.opt3001 [4/4] ★ 开始配置管理与软件复位测试
I/user.opt3001 当前配置: mode=continuous ct=800ms range=auto
I/user.opt3001 标志: CRF=Y F_H=N F_L=N OVF=N
I/user.opt3001 版本号: 202608052000
I/user.exs_opt3001 执行软件复位...
I/user.exs_opt3001 软件复位完成
I/user.opt3001 软件复位成功
I/user.opt3001 复位后照度: 195.04 lux
I/user.opt3001 [4/4] ✓ 配置管理与软件复位测试完成
I/user.exs_opt3001 资源已释放
```

### 5.6 故障排除

| 问题 | 可能原因 | 解决方法 |
|------|----------|----------|
| 初始化失败，设备 ID 校验不通过 | 接线错误或传感器损坏 | 检查 SDA/SCL 接线，确认供电正常 |
| 读数始终为 0 | SDA/SCL 无数据传输 | 检查上拉电阻，确认 I2C 地址正确 |
| 读数溢出（overflow=true） | 超出量程范围 | 增大量程或使用自动量程 |
| 无中断触发 | INT 引脚未接或上拉缺失 | 确认 INT 接线，检查上拉电阻 |
| 读数跳变较大 | 环境光变化或接触不良 | 稳定光源，检查接线可靠性 |

### 5.7 扩展功能建议

- **日志记录**：可将照度数据存储到文件系统，用于长期监测
- **联动控制**：根据照度值自动控制 LED 灯亮度（如暗时自动补光）
- **多传感器融合**：与其他传感器（如温湿度）配合使用
- **OTA 升级**：结合 FOTA 实现远程固件升级

## 六、API 参考

详细 API 说明请参考：[exs_opt3001.md](https://docs.openluat.com/osapi/ext/sensor/exs_opt3001.html)