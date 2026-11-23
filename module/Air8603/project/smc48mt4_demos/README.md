# SMC-48MT-4 演示集

研宏 **SMC-48MT-4** 这台小型 PLC 的屏端演示程序集合。每个子目录是一个独立可运行的演示，
共用同一套屏（Air8603W1）、同一套通信参数，只是"PLC 采什么、屏上显示什么"不同。

仓库地址：<https://gitee.com/openLuat/LuatOS/tree/master/module/Air8603/project/smc48mt4_demos>

## 演示列表

| 目录 | 演示 | 做什么 | 已有实现 |
|---|---|---|---|
| `temp_dual` | 双路温度监控 | 两个 T100 探头 → PLC 的 AD0/AD1 → 屏上仪表 + 曲线 + 报警 + 语音播报 | airui |

后面继续加新目录，一个演示一个目录，名字用英文小写下划线。

**同一个演示可以有多版实现**：`temp_dual/airui/` 用 AirUI 画界面，`temp_dual/plcui/` 用 PLCUI。
业务逻辑（取数、报警、播报）两边一样，只有界面层不同。

## 这台 PLC 的公共约定

所有演示都基于下面这几条，写新演示时照抄即可：

| 项目 | 值 |
|---|---|
| 通信 | RS485，Modbus RTU 从站 |
| 波特率 / 格式 | 19200、8 位、无校验、1 停止位 |
| 站号 | 204（0xCC） |
| AD 采集结果 | 4x 地址 6700 起，每路占 2 个寄存器，**CDAB 浮点** |
| 换算 | 读到的已经是工程量（AD 最大值填 50 → 读到 0–50 ℃），系数 1.0 |

**帧格式**（读 4 个寄存器，一次拿两路）：

```
发  CC 03 1A 2C 00 04 92 C5
收  CC 03 08 <CH1 4字节> <CH2 4字节> <CRC>
```

## 目录结构

```
smc48mt4_demos/
├── README.md              本文件
└── temp_dual/             一个演示
    ├── README.md          这个演示是什么、接什么线、怎么验收
    ├── airui/             AirUI 版
    │   └── code/          Lua 脚本，整个 code 目录作为一个脚本区下载
    └── plcui/             PLCUI 版（待做）
        └── code/
```

层次是「演示 → 框架 → code」。演示是稳定的单位，加新演示只加一个顶层目录，
不用动框架那一层。

`code/` 里固定包含这几类文件，新演示直接从这里复制改：

| 文件 | 作用 | 新演示要不要改 |
|---|---|---|
| `main.lua` | 入口、开机顺序 | 不用 |
| `conf.lua` | 所有参数 | **要**：改地址、阈值、量程 |
| `board.lua` | 上电时序、屏、触摸、背光 | 不用 |
| `drv_lcd_rgb.lua` / `drv_tp_gt911.lua` | 屏和触摸驱动 | 不用 |
| `drv_modbus.lua` | Modbus 收发 | 不用 |
| `exaudio.lua` | 音频库（厂家提供） | 不用，别改 |
| `app_data.lua` | 定时取数、存历史 | **要**：改怎么解读寄存器 |
| `app_alarm.lua` | 报警判定、记录、消音 | 看情况 |
| `app_sound.lua` | 语音播报 | 看情况 |
| `app_store.lua` | 参数掉电保存 | 不用 |
| `ui.lua` | 画面 | **要**：整个重画 |

## 怎么跑

1. 固件刷 `LuatOS-SoC_V1030_Air1603`（屏上要有 TTS，否则语音演示没声音）；
2. 用 Luatools 把某个实现的 `code/` 目录**整个**作为脚本区下载（选 `code` 目录本身，别把 `code` 这层也打进去）；
3. 屏接 PLC 的 A/B 两根线，上电。

命令行刷写（luatos-cli）：

```bash
luatos-cli flash script \
  --soc LuatOS-SoC_V1030_Air1603_102.soc \
  --port COM12 \
  --script <演示>/<框架>/code
```

## 踩过的坑

- **AD 输入必须共地**：探头 24V 电源的负极要接到 PLC 的 `IN GND`，否则读数在 0–11 ℃ 之间锯齿乱跳
- **不要把 `code` 这层打进脚本区**，多套一层就是白屏
- `exaudio.lua` 有 147KB，是懒加载的，不要为了省空间把它删掉
