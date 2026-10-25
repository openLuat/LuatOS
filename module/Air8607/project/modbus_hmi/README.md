# Modbus 工业中控大屏（Air8607 + AirLCD_1090）

一套跑在 **Air8607（Air1603 最小系统板）** 上的 Modbus SCADA 中控大屏 HMI，
屏幕为 **AirLCD_1090**（9 寸 RGB、1024×600、驱动 IC `JD9165BA`、触摸 `GT911`）。

工程自带**完整的 Modbus 主站协议栈**与**内置虚拟从站**，无需外接任何传感器即可
在 PC 模拟器和实机上完整运行；接上 RS485 总线后切换到 `rtu` 即可与真实设备通讯。

---

## 一、目录结构

```
modbus_hmi/
├── README.md
└── code/
    ├── main.lua                 入口：板级上电 / 显示初始化 / 触摸 / 启动应用
    ├── conf.lua                 板级与通信参数（串口、TCP、轮询、阈值、报警）
    ├── theme.lua                工业暗色主题与基础控件封装
    ├── exd_jd9165ba_rgb.lua     AirLCD_1090（JD9165BA）显示 IC 初始化
    ├── modbus.lua               Modbus 协议核心：CRC16 / RTU / TCP / PDU / 数据类型
    ├── mbslave.lua              内置虚拟从站：5 个从站寄存器库 + 现场过程模拟
    ├── mbdev.lua                从站设备与点位（寄存器）模型、工程量换算、报警
    ├── mbmaster.lua             Modbus 主站：三传输层 + 轮询调度 + 统计 + 读写
    ├── chart.lua                曲线绘制：迷你趋势 / 单通道波形 / 多通道归一化
    ├── app.lua                  页面路由、刷新编排、全局 toast
    ├── ui_dashboard.lua         总览页
    ├── ui_device.lua            设备详情（点位表 + 写入操作）
    ├── ui_trend.lua             趋势页（多通道曲线）
    ├── ui_alarm.lua             报警记录页
    ├── ui_regtool.lua           寄存器调试工具（手发报文）
    └── ui_settings.lua          设置页
```

---

## 二、功能

### 1. Modbus 主站（三种传输方式，行为一致）

| 方式 | 说明 |
|------|------|
| `sim` 内置虚拟从站 | 默认。进程内完成真实组帧 → CRC → 超时 → 解析 → 异常码全过程，并按波特率折算响应延迟 |
| `rtu` RS485 RTU | 走 `uart`，支持 9600/19200/38400/115200、无/奇/偶校验、1/2 停止位、硬件 485 自动换向 GPIO |
| `tcp` Modbus TCP | `socket + libnet` 长连接，MBAP 事务号校验（Air8607 无网络，主要用于 PC 验证） |

支持功能码：`0x01 0x02 0x03 0x04 0x05 0x06 0x0F 0x10`，
支持数据类型：`UINT16 / INT16 / UINT32 / INT32 / FLOAT32`（含低字在前变体）、`BIT`。

### 2. 5 个从站、36 个点位

| 站号 | 设备 | 型号 | 点位 |
|------|------|------|------|
| #1 | 车间温湿度变送器 | TH-200 | 湿度 / 温度 / 露点 / 状态字（位域） |
| #2 | 三相电力仪表 | PM-300 | 三相电压、三相电流、有功功率、功率因数、频率、电能（UINT32） |
| #3 | 冷库温控器 | TC-100 | 目标温度(可写)、回差(可写)、延时(可写)、库内温度、蒸发器温度、压缩机(线圈)、除霜(线圈)、库门、高低压保护 |
| #4 | 液位流量计 | FM-400 | 液位、瞬时流量、累计流量、介质温度、管道压力 |
| #5 | 数字量 IO 模块 | IO-808 | 4 路继电器输出(可写) + 4 路开关量输入 |

### 3. 闭环联动（不是死数据）

- 主站改写 #3 的「目标温度」→ 温控器过程模型跟随该设定值制冷/回温；
- #5 的「进料泵 / 出料阀」→ 直接驱动 #4 的液位与瞬时流量变化；
- 写入的寄存器在下一次轮询即可读回，UI 立即刷新。

### 4. 页面

- **总览**：设备在线卡、4 个关键指标、实时趋势（可切通道）、通讯统计（成功/失败/超时/CRC/异常/耗时/轮次）、最新报警
- **设备详情**：点位表（Modbus 地址 / 类型 / 原始值 HEX / 工程量 / 状态）、可写点位直接下发、轮询报文一览、模拟掉线、注入异常、输出全复位
- **趋势**：8 个通道任选最多 3 条同屏，各通道按自身量程归一化，附当前值与可视量程图例
- **报警**：总/危险/偏离统计、级别过滤、20 条滚动记录、清空
- **寄存器工具**：手选从站号 / 功能码 / 地址 / 数量 / 写入值，发起读写，显示 **TX / RX 原始 HEX 报文** 与解析结果（HEX / UINT16 / INT16 / FLOAT32 / 位）
- **设置**：通讯方式切换、串口参数、TCP 与轮询参数、背光亮度、暂停轮询、重置统计

### 5. 告警链路

- 点位越限 → `warn`；越危险限 → `danger`；线圈类点位可配置为「ON 即报警」（如急停、高低压保护）
- 从站连续失败 N 轮 → 判定离线 → 产生通讯中断/恢复事件
- 自动故障注入：周期性地让某个从站掉线或返回错误 CRC，用来验证超时重传与报警链路

---

## 三、硬件连接（Air8607 + AirLCD_1090）

| 信号 | Air8607 |
|------|---------|
| LCD 供电使能 | GPIO17（低有效） |
| LCD_DISP / 复位 | GPIO15 |
| 背光 PWM | PWM3 |
| 触摸 I2C | I2C1（SCL=PIN42/GPIO39，SDA=PIN41/GPIO38） |
| TP_RST / TP_INT | GPIO14 / GPIO51（下降沿） |
| 功放关断 | GPIO73 |

RGB 时序（1024×600 生态实测组，与 `eng_8607_10i_v0.lua` 一致）：
`hbp=140 hspw=20 hfp=160 vbp=20 vspw=3 vfp=12 @ 50MHz`

RS485：默认用 UART1，收发换向脚可在设置页指定（交给 uart 硬件自动切换）；
未接总线时保持 `sim` 方式即可。

---

## 四、运行

### PC 模拟器（Windows）

```powershell
# 1、编译带 GUI 的模拟器（AirUI/LVGL 走 SDL）
cd bsp\pc
cmd /c build_windows_32bit_msvc_gui.bat
# 或 64 位
cmd /c build_windows_64bit_msvc_gui.bat

# 2、运行本工程
cd build\out
.\luatos-lua.exe ..\..\..\..\module\Air8607\project\modbus_hmi\code\
```

### 实机（Air8607）

用 LuatTools 把 `code/` 目录整体作为脚本工程下载即可；
`conf.lua` 中把 `comm.transport` 改成 `"rtu"` 并配好串口参数即可接真实 RS485 总线。

---

## 五、常用配置（`code/conf.lua`）

```lua
comm = {
    transport = "sim",            -- sim / rtu / tcp
    rtu  = { uart_id = 1, baud = 9600, databits = 8, parity = "none",
             stopbits = 1, rs485_de_pin = 0, rs485_de_level = 1 },
    tcp  = { ip = "192.168.1.100", port = 502 },
    timeout_ms = 800, retry = 2, poll_interval_ms = 1000,
    offline_after = 3, inter_frame_ms = 30,
},
sim = { history_n = 80, baud_for_delay = 9600,
        inject_fault = true, fault_every = 45, fault_rounds = 4 },
```

点位阈值（`lo/hi` 预警、`dlo/dhi` 报警）与模拟初值都在 `mbdev.lua` 的点位表里，按需修改。
