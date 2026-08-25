# PCA9685 16路 PWM功能演示

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责项目初始化、版本定义和任务调度
2. **pca9685_demo** - PCA9685 功能演示模块，包含 PWM 频率设置测试、呼吸灯测试、舵机角度测试、全通道控制测试功能的演示用例

### 1.2 扩展库模块

1. **exs_pca9685** - PCA9685 扩展库，提供 I2C 初始化、PWM 频率设置、通道占空比控制、ON/OFF 计数器控制、舵机角度控制、全通道同步控制、输出模式配置等 9 个 API

## 二、演示流程介绍

本 demo 按顺序演示 exs_pca9685 扩展库的 4 项功能：PWM 频率设置测试、呼吸灯测试、舵机角度测试、全通道控制测试

### 2.1 功能演示项说明

1. PWM 频率设置测试（[1/4]）- CH0 固定 50% 占空比，切换 24Hz/50Hz/200Hz 观察 LED 闪烁/常亮效果
2. 呼吸灯测试（[2/4]）- CH0 占空比 0→4095→0 渐变 3 个周期，模拟呼吸灯效果
3. 舵机角度测试（[3/4]）- CH1 角度 0°→180°→0° 扫描 2 个周期，驱动舵机转动
4. 全通道控制测试（[4/4]）- set_all_pwm 一次点亮/熄灭全部 16 路，并演示推挽/开漏输出模式切换

## 三、演示硬件环境

### 3.1 硬件清单

- Air780EHV 核心板

- PCA9685 16路 PWM驱动模块 × 1，购买链接：[https://e.tb.cn/h.8lsh0VZw5CcHzrB?tk=C7mqTWRfMLW](https://e.tb.cn/h.8lsh0VZw5CcHzrB?tk=C7mqTWRfMLW)

- LED × 1（呼吸灯演示使用，接 CH0）

- 舵机 × 1（舵机角度演示使用，接 CH1，推荐 SG90/MG996R 等标准舵机）

- 5V/6V 外部电源（舵机供电，SG90 用 5V，MG996R 用 6V）

- 母对母杜邦线 × 若干

- TYPE-C 数据线 × 1

![](https://docs.openluat.com/osapi/ext/image/780ehv-pca9685.png)

### 3.2 接线配置

#### 3.2.1 PCA9685 模块接线（硬件 I2C）

<table>
<tr>
<td>Air780EHV 核心板</td><td>PCA9685 模块</td>
</tr>
<tr>
<td>67 / I2C1_SCL</td><td>SCL</td>
</tr>
<tr>
<td>66 / I2C1_SDA</td><td>SDA</td>
</tr>
<tr>
<td>3V3</td><td>VCC（逻辑电源）</td>
</tr>
<tr>
<td>GND</td><td>GND（共地）</td>
</tr>
<tr>
<td>GND</td><td>OE（输出使能，低电平有效，接地常使能）</td>
</tr>
<tr>
<td>GND</td><td>A0~A5（地址选择，全部接地为地址 0x40）</td>
</tr>
<tr>
<td>5V/6V 外部电源正极</td><td>V+（舵机/负载电源）</td>
</tr>
<tr>
<td>5V/6V 外部电源负极</td><td>GND（与 Air780EHV 共地）</td>
</tr>
</table>

> 说明：VCC 为逻辑电源（2.3V~5.5V，本 demo 接 3V3）；V+ 为舵机/负载电源（按舵机要求接 5V 或 6V），两者相互独立。V+ 必须与 Air780EHV 共地。具体引脚以模块实际丝印为准。

#### 3.2.2 演示负载接线

<table>
<tr>
<td>PCA9685 模块</td><td>负载</td>
</tr>
<tr>
<td>CH0（通道 0 输出）</td><td>LED 正极（经限流电阻）</td>
</tr>
<tr>
<td>GND</td><td>LED 负极</td>
</tr>
<tr>
<td>CH1（通道 1 输出）</td><td>舵机信号线（橙色）</td>
</tr>
<tr>
<td>V+</td><td>舵机电源线（红色）</td>
</tr>
<tr>
<td>GND</td><td>舵机地线（棕色）</td>
</tr>
</table>


## 四、演示软件环境

### 4.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air780ehv/luatos/common/download/)

### 4.2 内核固件

- [点击下载Air780EHV系列最新版本内核固件](https://docs.openluat.com/air780ehv/luatos/firmware/version/)，demo 使用 LuatOS-SoC Air780EHV 1号固件

### 4.3 脚本文件

1. **main.lua** - 程序入口

2. **pca9685_demo.lua** - 演示模块

3. **exs_pca9685.lua** - 扩展库

## 五、演示核心步骤

### 5.1 硬件准备

1. 按照接线表将 PCA9685 模块连接到核心板
2. 将 LED 接入通道 0，将舵机接入通道 1
3. 确保 V+ 外部电源连接正确，通过 TYPE-C USB 口给核心板供电
4. 检查所有接线无误，避免短路

### 5.2 软件配置

在 `main.lua` 中加载对应的演示模块：

```lua
-- 加载 pca9685_demo.lua 演示模块（内部已 require exs_pca9685 扩展库）
require "pca9685_demo"
```

### 5.3 演示运行

使用 Luatools 烧录脚本后，模组自动运行，日志输出如下：

```
I/main.        PCA9685_Demo 001.999.000
I/pca9685_demo PCA9685 Demo 启动
I/exs_pca9685.init 从设备地址识别成功: 64
I/exs_pca9685.set_pwm_freq 频率设置成功: 50 Hz, prescale=0x79
I/exs_pca9685.init 初始化完成, i2c= 1 addr=0x40 freq= 50
I/pca9685_demo PCA9685 初始化成功, 版本: 202608252000
I/pca9685_demo [1/4] PWM 频率设置演示开始（CH0 固定 50% 占空比）
I/exs_pca9685.set_pwm_freq 频率设置成功: 24 Hz, prescale=0xFF
I/exs_pca9685.set_pwm_freq 频率设置成功: 50 Hz, prescale=0x79
I/exs_pca9685.set_pwm_freq 频率设置成功: 200 Hz, prescale=0x1E
I/exs_pca9685.set_pwm_freq 频率设置成功: 50 Hz, prescale=0x79
I/pca9685_demo [1/4] PWM 频率设置演示结束
I/pca9685_demo [2/4] 呼吸灯演示开始（CH0，需外接 LED）
I/pca9685_demo [2/4] 呼吸灯演示结束
I/pca9685_demo [3/4] 舵机角度演示开始（CH1，需外接舵机，频率 50Hz）
I/pca9685_demo [3/4] 舵机角度演示结束
I/pca9685_demo [4/4] 全通道控制演示开始（需外接 LED）
I/exs_pca9685.set_all_pwm 所有通道占空比设置成功: 2048
I/exs_pca9685.set_all_pwm 所有通道占空比设置成功: 0
I/exs_pca9685.set_output_mode 输出模式配置成功, mode2=0x04
I/pca9685_demo [4/4] 全通道控制演示结束
I/pca9685_demo PCA9685 Demo 全部演示结束
```

### 5.4 演示效果观察

1. **[1/4] 频率演示**：CH0 的 LED 在 24Hz 时肉眼可见明显闪烁，50Hz/200Hz 时视为常亮（可用示波器观察频率变化）
2. **[2/4] 呼吸灯演示**：CH0 的 LED 亮度平滑渐变（渐亮→渐灭），模拟呼吸灯效果
3. **[3/4] 舵机演示**：CH1 的舵机在 0°~180° 之间来回摆动（每 10° 一步，共 2 个周期）
4. **[4/4] 全通道演示**：全部 16 路输出同时点亮 2 秒后熄灭，随后切换推挽/开漏输出模式

## 六、常见问题

### 6.1 初始化失败，日志提示"未识别到 PCA9685 从设备"

1. 检查 SCL/SDA 接线是否正确（67=I2C1_SCL、66=I2C1_SDA）
2. 检查 VCC 是否供电（3.3V~5V），GND 是否共地
3. 检查模块地址是否与代码一致（A0~A5 全部接地为 0x40，可在 init 中指定其他地址）

### 6.2 舵机不动作或抖动

1. 确认 PWM 频率为 50Hz（init 默认 50Hz，舵机标准频率）
2. 检查舵机电源 V+ 是否足够（SG90 用 5V，MG996R 用 6V，电流需达 1A 以上）
3. 确认舵机信号线接在正确的通道（本 demo 使用 CH1）
4. 若舵机反向，可在接线中调换舵机方向或调整 min_pulse/max_pulse 参数

### 6.3 LED 亮度异常或发热

1. 检查 LED 是否串接限流电阻（建议 100Ω~1kΩ，视 LED 规格而定）
2. 确认输出模式与负载匹配（普通 LED 用推挽模式即可，大电流负载建议开漏+外部驱动）
