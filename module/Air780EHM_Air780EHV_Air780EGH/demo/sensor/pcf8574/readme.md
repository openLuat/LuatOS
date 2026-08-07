# PCF8574 GPIO 扩展 Demo

## 一、功能模块介绍

### 1.1 核心主程序模块

- [main.lua](file:///D:/project/luatos-git/LuatOS/module/Air780EHM_Air780EHV_Air780EGH/demo/sensor/pcf8574/main.lua)：Demo 入口文件，初始化日志、加载业务模块

### 1.2 扩展库模块

- [exs_pcf8574.lua](file:///D:/project/luatos-git/LuatOS/script/libs/sensor/exs_pcf8574.lua)：PCF8574 扩展库，提供 I2C 通信、GPIO 读写、中断处理等功能

### 1.3 I2C 模式说明

Demo 支持两种 I2C 通信模式，通过 `pcf8574_app.lua` 中的 `MODE` 变量切换：

| MODE | 模式 | 说明 |
|------|------|------|
| 1 | 软件 I2C | 默认引脚 SCL=67, SDA=66，可自定义 |
| 2 | 硬件 I2C | 使用 I2C1，引脚固定 |

## 二、演示流程介绍

本 Demo 按顺序演示 5 个功能：

1. **[1/5] GPIO 输出测试**：P0 输出高低电平切换，可观察 LED 亮灭
2. **[2/5] GPIO 输入测试**：P1 输出 → P2 读取（P1-P2 需短接）
3. **[3/5] GPIO 中断测试**：P3 输出 → P4 中断回调（P3-P4 需短接）
   - 需在 `setup()` 中配置 `int_gpio` 参数
   - 需启动中断监听任务，在协程上下文中调用 `exs_pcf8574.process_int()`
4. **[4/5] 批量读写测试**：write_all/read_all 接口演示
5. **[5/5] 数据读取与资源释放**：get_data() 读取最终状态，close() 释放资源

## 三、演示硬件环境

### 3.1 硬件清单

- Air780EHM/Air780EHV/Air780EGH 核心板 × 1

- PCF8574 GPIO 扩展模块 × 1，购买链接：[https://e.tb.cn/h.85OBnaVNzkO7BwQ?tk=EIFBgxHkMBR](https://e.tb.cn/h.85OBnaVNzkO7BwQ?tk=EIFBgxHkMBR)

- 母对母杜邦线 × 8

- TYPE-C 数据线 × 1

  ![](https://docs.openluat.com/osapi/ext/image/780ehv-pcf8574.png)

### 3.2 接线配置

| Air780EHM/Air780EHV/Air780EGH 核心板 | PCF8574 | 说明 |
|------|---------|------|
| 3.3V | VDD | 电源 |
| GND | GND | 地 |
| 66/I2C1_SDA | SDA | I2C 数据线 |
| 67/I2C1_SCL | SCL | I2C 时钟线 |
| 23/GPIO2 | INT | 中断引脚（可选） |
| GND | A0/A1/A2 | 地址配置（全接地=0x20） |

> **注意**：SDA 和 SCL 需要外接 4.7kΩ~10kΩ 上拉电阻到 3.3V

**短接说明**：
- 测试 2（输入）：P1 和 P2 需要短接
- 测试 3（中断）：P3 和 P4 需要短接

## 四、演示软件环境

### 4.1 开发工具

- [LuatOS Studio](https://docs.openluat.com/luatos/luatstudio/)：烧录固件和调试

### 4.2 内核固件

- Air780EHM：https://docs.openluat.com/air780ehm/luatos/firmware/version/
- Air780EHV：https://docs.openluat.com/air780ehv/luatos/firmware/version/
- Air780EGH：https://docs.openluat.com/air780egh/luatos/firmware/version/

### 4.3 脚本文件

| 文件 | 说明 |
|------|------|
| [main.lua](file:///D:/project/luatos-git/LuatOS/module/Air780EHM_Air780EHV_Air780EGH/demo/sensor/pcf8574/main.lua) | Demo 入口 |
| [pcf8574_app.lua](file:///D:/project/luatos-git/LuatOS/module/Air780EHM_Air780EHV_Air780EGH/demo/sensor/pcf8574/pcf8574_app.lua) | 业务模块 |
| [exs_pcf8574.lua](file:///D:/project/luatos-git/LuatOS/script/libs/sensor/exs_pcf8574.lua) | 扩展库（需放到 script/libs/sensor/ 目录） |

## 五、演示核心步骤

### 5.1 硬件准备

1. 按接线表连接主控和 PCF8574 模块
2. 将 P1-P2 短接（输入测试）
3. 将 P3-P4 短接（中断测试）
4. 可选：在 P0 与 GND 之间接 LED（低电平点亮）

### 5.2 软件配置

打开 `pcf8574_app.lua`，根据实际情况修改：

```lua
local MODE = 2  -- 1=软件 I2C, 2=硬件 I2C
```

如需使用软件 I2C，修改 `build_config_func()` 中的引脚号。

### 5.3 软件烧录

1. 将 `exs_pcf8574.lua` 复制到 `script/libs/sensor/` 目录
2. 使用 LuatOS Studio 打开 `demo/sensor/pcf8574/` 项目
3. 烧录对应型号的固件
4. 烧录脚本并运行

### 5.4 功能测试

上电后，Demo 自动执行 5 项测试：

1. `[1/5]` GPIO 输出测试：P0 输出高低电平，LED 应交替亮灭
2. `[2/5]` GPIO 输入测试：日志显示 P2 读取的电平应与 P1 输出一致
3. `[3/5]` GPIO 中断测试：P3 电平变化时，P4 回调触发日志
4. `[4/5]` 批量读写测试：日志显示批量写入和读取结果
5. `[5/5]` 数据读取与资源释放：get_data() 返回所有引脚状态

### 5.5 预期效果

```
I/user.main sensor_pcf8574 001.999.000
I/user.pcf8574 ====== PCF8574 Demo 开始 (MODE=2) ======
I/user.pcf8574 [1/5] ★ 开始 GPIO 输出测试
I/user.pcf8574 [1/5] ✓ GPIO 输出测试完成
I/user.pcf8574 [2/5] ★ 开始 GPIO 输入测试
I/user.pcf8574 P1=0, P2 读取: 0
I/user.pcf8574 P1=1, P2 读取: 1
...
I/user.pcf8574 [2/5] ✓ GPIO 输入测试完成
I/user.pcf8574 [3/5] ★ 开始 GPIO 中断测试
I/user.pcf8574 ★ 中断触发：引脚电平发生变化
...
I/user.pcf8574 [3/5] ✓ GPIO 中断测试完成
I/user.pcf8574 [4/5] ★ 开始批量读写测试
I/user.pcf8574 P0~P3 输出低，P4~P7 输出高: 写入=0xF0 读取=0xF0
...
I/user.pcf8574 [4/5] ✓ 批量读写测试完成
I/user.pcf8574 [5/5] ★ 读取最终状态并释放资源
I/user.pcf8574 [5/5] ✓ 资源已释放
I/user.pcf8574 ====== 全部测试完成 ======
```

### 5.6 故障排除

| 问题 | 排查方法 |
|------|---------|
| 初始化失败 | 检查 VCC/GND 接线、SDA/SCL 上拉电阻、A0/A1/A2 地址跳线 |
| 读取电平始终为 1 | 确认 P1-P2 已短接，PCF8574 内部上拉生效 |
| 中断无响应 | 确认 INT 引脚接线、上拉电阻、P3-P4 已短接 |
| LED 不亮 | PCF8574 拉电流极弱，建议低电平驱动（LED 正极接 VCC，负极接引脚） |
| I2C 通信失败 | 检查上拉电阻（建议 4.7kΩ），降低 I2C 速率 |

### 5.7 扩展功能建议

- **键盘矩阵扫描**：P0~P3 配置为输出，P4~P7 配置为输入，实现 4×4 键盘扫描
- **LED 状态指示**：多颗 LED 低电平驱动，实现状态指示扩展
- **LCD 驱动**：PCF8574 可作为 1602 LCD 的 I2C 转接板核心
- **级联扩展**：多片 PCF8574 级联，扩展更多 GPIO

## 六、API 参考

详细 API 说明请参考：[exs_opt3001.md](https://docs.openluat.com/osapi/ext/sensor/exs_pcf8574.html)