# Air8204 出厂固件（8204_factory）

## 一、项目简介

1. **产测 + 出货合一**：单固件按 `fskv` 中的 `test_done` 标记分流 —— 未产测进产测模式，产测完成自动进出货模式，产线与售后共用同一固件。
2. **单入口分层**：`main.lua` 只保留固件常量 + 启动，启动逻辑下沉 `boot.lua`，两种模式各自独立装配，互不干扰。
3. **产测模式**：USB 虚拟串口（VUART_0）响应 20 条产测指令，覆盖写号、录音、TF 卡、加速度、GNSS、RF 校准查询等。
4. **出货模式**：录音定位工牌完整业务 —— 录音采集/存卡/上传、GNSS + 基站双模定位、震动检测、双路 LED、电量上报、云端 TLV 交互。
5. **FOTA 统一**：统一走 `libfota3`（整机成品 FOTA），由 `update.lua` 管理，消除双升级通道。

## 二、固件形态（两个模式）

| 模式 | 入口 | 触发条件 | 交互方式 | 用途 |
|---|---|---|---|---|
| **产测模式** | `factory.lua` | `test_done` 未完成 | USB 虚拟串口 VUART_0（指令以 `#` 结尾） | 产线写号与功能测试 |
| **出货模式** | `card_main.lua` | `test_done == true` | 4G + 云端（excloud） | 整机出货运行 |

> **模式切换**：产线执行 `TEST_DONE#` → 写 `fskv` 标记 → 3 秒后自动重启 → 进入出货模式。
>
> **调试开关**：`boot.lua` 中 `BOOT_MODE` 可强制指定模式（`auto` 按标记分流 / `normal` 强制出货 / `factory` 强制产测）。

## 三、目录结构

```
8204出厂固件/
├── README.md                  # 本文件
│   ├── user/                  # LuaTools 脚本目录
│   │   ├── main.lua           # 入口：PROJECT / VERSION / PRODUCT_KEY + require "boot"
│   │   ├── boot.lua           # ⭐ 启动分流：VREF / 软狗 / FOTA / test_done 判定
│   │   ├── factory.lua        # ⭐ 产测模式（USB VUART_0 响应产测指令）
│   │   ├── card_main.lua      # ⭐ 出货模式装配（录音定位工牌应用）
│   │   ├── prodmeta.lua       # OTP 写号（PROD 型号 / PCB 硬件版本）
│   │   ├── update.lua         # FOTA 管理（libfota3，开机 + 定时循环）
│   │   ├── config.lua         # 全局配置与状态枚举
│   │   ├── app.lua            # 业务调度（上报周期、录音上传）
│   │   ├── es7243e.lua        # ES7243E 录音 ADC 驱动
│   │   ├── sd_test.lua        # TF 卡挂载与录音数据库
│   │   ├── http_app.lua       # 录音文件云端上传
│   │   ├── normal.lua         # GNSS 卫星定位
│   │   ├── lbs_util.lua       # 基站/WiFi 混合定位（airlbs）
│   │   ├── da221.lua          # DA221 加速度传感器与运动判定
│   │   ├── exvib.lua          # 震动检测扩展（8204 适配版，i2cId=0）
│   │   ├── led_util.lua       # 双路 WS2812 状态指示
│   │   ├── gpio_util.lua      # 电量检测与录音开关
│   │   ├── excloud_app.lua    # excloud 云端接入
│   │   ├── mem_monitor.lua    # 内存监控
│   │   ├── network_watchdog.lua # 网络业务看门狗
│   │   ├── libfota3.lua       # 整机成品 FOTA 库
│   │   └── pins_Air780EGH.json # 引脚定义
│   ├── lib/                   # 扩展库
```

## 四、启动流程

```
main.lua           仅定义 PROJECT / VERSION / PRODUCT_KEY，require "boot"，sys.run()
   │
   └─ boot.lua
        fskv.init()                     -- 初始化 KV 存储
        gpio.setup(23, 1)               -- VREF 拉高（开机高电平源）
        wdt.init(9000) + 3 秒喂狗        -- 软狗（产测 / 出货统一启用）
        update.init()                   -- FOTA 初始化（libfota3）
        │
        ├─ test_done 未完成 → factory.lua      产测模式（USB VUART_0）
        └─ test_done == true → card_main.lua   出货模式（录音定位工牌应用）
```

## 五、产测模式

通过 **USB 虚拟串口（VUART_0，115200）** 收发指令，指令以 `#` 结尾，回复同样以 `#` 结尾。

### 5.1 产测指令表

| 指令 | 形式 | 功能 | 说明 |
|---|---|---|---|
| `VERSION` | `VERSION#` | 读固件版本 | 返回 `Air8204_Factory_001.000.001` |
| `MODEL` | `MODEL,型号#` | 写工业型号 | 写入 OTP（`PROD`），如 `MODEL,8204#` |
| `MODEL?` | `MODEL?#` | 读工业型号 | 读回 OTP 中的 `PROD` |
| `HVERSION` | `HVERSION,版本#` | 写硬件版本 | 写入 OTP（`PCB`），如 `HVERSION,1103#` |
| `HVERSION` | `HVERSION#` | 读硬件版本 | 读回 OTP 中的 `PCB` |
| `IMEI` | `IMEI#` | 读 IMEI | 模块信息 |
| `IMSI` | `IMSI#` | 读 IMSI | 卡信息 |
| `ICCID` | `ICCID#` | 读 ICCID | 卡信息 |
| `CSQ` | `CSQ#` | 读信号强度 | 模块信息 |
| `MUID` | `MUID#` | 读模块唯一 ID | 模块信息 |
| `VBAT` | `VBAT#` | 读电池电压 | `adc.CH_VBAT`，返回 mV |
| `LED` | `LED,1#` / `LED,0#` | 灯测试 | WS2812×2 + RGB 灯 R 路 点亮 / 熄灭 |
| `RECORD` | `RECORD#` | 录音链路测试 | ES7243E 供电 + I2C1 配置 + I2S 采集，返回 `OK` / `ERROR` |
| `SD_TEST` | `SD_TEST#` | TF 卡测试 | SPI0 挂载 + 写读比对，返回 `OK` / `ERROR` |
| `GS_STATE` | `GS_STATE#` | 加速度传感器测试 | I2C0 读 DA221 芯片 ID（期望 `0x13`） |
| `GPSTEST` | `GPSTEST,1#` / `GPSTEST,0#` | GNSS 测试 | 开 / 关 GNSS，原始 NMEA 透传至 VUART_0 |
| `ECNPICFG` | `ECNPICFG#` | 读 RF 校准标志 | 只读，返回 `passed` / `rfCaliDone` 等标志位 |
| `FLYMODE` | `FLYMODE,1#` / `FLYMODE,0#` | 飞行模式开关 | 主 LTE（adapter 0） |
| `RST` | `RST#` | 重启设备 | **不写** `test_done`，重启后仍进产测模式 |
| `TEST_DONE` | `TEST_DONE#` | 产测完成 | 写 `test_done`，3 秒后重启进**出货模式** |
| `PCBA_TEST_DONE` | `PCBA_TEST_DONE#` | 板级测试完成 | **不写** `test_done`，3 秒后**关机**（下板用） |

> 除 `VERSION` 外，未知指令统一回复 `ERROR#`。

### 5.2 产测外设与管脚

| 外设 | 接口 | 管脚 / 地址 |
|---|---|---|
| LED1 / LED2 | WS2812 ×2 | GPIO27 / GPIO28 |
| RGB 灯 R 路 | GPIO | GPIO25（高电平亮，G/B 由充电芯片控制，不测） |
| ES7243E 录音 ADC | 供电 GPIO32；I2C1 地址 `0x10`；I2S0 数据 | — |
| TF 卡 | SPI0，CS = GPIO8（软件 CS），使能 GPIO1 | — |
| DA221 加速度 | I2C0 地址 `0x27`，使能 GPIO20，芯片 ID `0x13` | — |
| GNSS | 内置，UART2 | — |
| 录音模式开关 | GPIO22 输入（低电平 = 录音） | — |
| VREF | GPIO23（开机拉高） | — |
| 电池电压 | `adc.CH_VBAT` | — |

### 5.3 产测流程

```
新板开机 → 自动进产测模式 → 逐条执行指令测试 → TEST_DONE# → 自动重启 → 出货模式
```

## 六、出货模式（录音定位工牌应用）

`card_main.lua` 装配 air_card 全量功能模块：

| 功能 | 模块 | 说明 |
|---|---|---|
| 音频录音 | `es7243e.lua` | ES7243E ADC + I2S 采集，`codec` 编码 AMR，定时分片存卡 |
| TF 卡存储 | `sd_test.lua` | SPI0 挂载 `/sd`，录音数据库 `recording_db.json`，上传状态机 |
| 录音上传 | `http_app.lua` | `excloud.upload_audio()` 上传，成功后删除，失败重试（最多 5 次） |
| GNSS 定位 | `normal.lua` | `exgnss` 卫星定位，输出经纬度 |
| 基站/WiFi 定位 | `lbs_util.lua` | `airlbs` 混合定位，70 秒周期，GPS 无解时回退使用 |
| 震动检测 | `da221.lua` / `exvib.lua` | DA221 三轴加速度，运动/静止判定，联动定位省电 |
| 状态指示 | `led_util.lua` | 双路 WS2812：设备状态 + 录音状态 |
| 电量检测 | `gpio_util.lua` | ADC0 采样换算电量 |
| 云端接入 | `excloud_app.lua` | `excloud` 平台：TLV 上报、命令收发、心跳、运维日志 |
| 业务调度 | `app.lua` | 待上传录音轮询；60 秒上报基础数据；30 秒上报定位 |
| 内存监控 | `mem_monitor.lua` | 内存使用量与增长监控 |
| 网络看门狗 | `network_watchdog.lua` | 网络业务超时（330 秒）自动重启 |
| 全局配置 | `config.lua` | 上传配置、设备/录音状态枚举 |

**上报周期**：基础数据 60 秒；定位数据 30 秒；基站定位请求 70 秒。
**定位优先级**：GNSS 卫星定位优先，定不到时使用基站/WiFi 定位结果。
**定位来源识别**：日志中以 `[GNSS定位]` / `[LBS基站定位]` / `[定位上报]` 前缀区分，上报字段本身不带来源标识。

## 七、数据中心上报格式（AirCloud TLV）

| tag | 含义 | 类型 | 来源 |
|---|---|---|---|
| 771 | 电量 | INTEGER | ADC0 采样换算 |
| 793 | TF 卡总容量 | ASCII | `fatfs.getfree()` |
| 794 | TF 卡可用容量 | ASCII | `fatfs.getfree()` |
| 795 | 内存总量 | ASCII | `rtos.meminfo("sys")` |
| 796 | 内存可用 | ASCII | `rtos.meminfo("sys")` |
| 512 | 经度 | FLOAT | GNSS（无解时回退 LBS） |
| 513 | 纬度 | FLOAT | GNSS（无解时回退 LBS） |
| 1280 | 时间戳 | INTEGER | `os.time()` |

> 下行控制：云端可下发 `record_ctrl` 远程控制录音开 / 关；本地录音开关为 GPIO22 硬件检测，两者状态变化均同步上报。





