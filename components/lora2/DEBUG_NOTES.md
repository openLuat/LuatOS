# LoRa2 (SX1262/LLCC68) 驱动调试记录

## 硬件背景

- **主板**：Air780EHV / Air780EGH（LuatOS）
- **LoRa 模块**：
  - 板 A：**安信可 Ra-01SH**（SX1262，**无源晶振** Y1 = CRYSTAL4/SM CY3225，32MHz 石英晶体）
  - 板 B：日浩 **ME-126XM**（SX1262，**TCXO 有源晶振**版本）
- **参考驱动**：`e:\work\custmoer\日浩lora\1.ME-126XM测试程序`（STM32 NucleoL152 + SX1262DVK1DAS）

## 涉及文件

| 文件 | 说明 |
|------|------|
| `components/lora2/luat_lib_lora.c` | Lua 侧 API 封装（lora2.init / send / recv 等） |
| `components/lora2/sx126x/sx126x.c` | SX126x 命令级驱动（Init/Standby/Calibrate/TCXO） |
| `components/lora2/sx126x/sx126x.h` | 常量定义（`USE_TCXO`, `RADIO_TCXO_SETUP_TIME` 等） |
| `components/lora2/sx126x/sx126x-board.c` | 板级 SPI/GPIO 适配层 |
| `components/lora2/sx126x/radio.c` | Radio 状态机（RadioInit 等） |
| `module/Air780EHM_Air780EHV_Air780EGH/demo/lora2/*.lua` | Lua 测试脚本（sender/receiver/main） |

## 调试历程

### 阶段 1：初步排查

**症状**：
- 日志能打印 `LORA*: 0C7F57B8`（userdata 创建成功）
- Lua 能收到 `DEVICE_READY` 消息
- 但收发不通

**分析**：
- `DEVICE_READY` 是 Lua 脚本自己 publish 的消息，跟芯片状态无关
- 只有这两条日志无法判断芯片是否真的工作
- 缺少 `lora2_main 接收超时` 打印说明 IRQ/RX 状态机根本没跑起来

### 阶段 2：判断是不是"有源晶振"

用户说：板子是有源晶振，TCXO = 1.8V。

**代码原本状态**：
- `#define USE_TCXO` 未启用
- `SX126xSetDio3AsTcxoCtrl(TCXO_CTRL_1_7V, ...)` 用 1.7V
- 改成 1.8V → 挂死
- 关闭 `USE_TCXO` → **正常工作**！


### 阶段 3：加入打印

在 `luat_lib_lora.c` 的 `Radio2.Init` 之后加：

```c
RadioError_t err = SX126xGetDeviceErrors2(lora_device);
RadioStatus_t st = SX126xGetStatus2(lora_device);
LLOGI("SX126x errors=0x%04X status=0x%02X (chipMode=%d cmdStatus=%d)",
      err.Value, st.Value, st.Fields.ChipMode, st.Fields.CmdStatus);
SX126xClearDeviceErrors2(lora_device);
```

**结果**：

| 板子 | 配置 | 现象 | 结论 |
|------|------|------|------|
| A（Ra-01SH 无源） | `USE_TCXO` 开 | **挂死**（无 errors 打印） | 无源晶振却启用 TCXO 控制 → Calibrate 卡在 BUSY |
| A（Ra-01SH 无源） | `USE_TCXO` 关 | `errors=0x0000` | **正常** ✓ |
| B（ME-126XM TCXO） | `USE_TCXO` 关 | `errors=0x2000` (XOSC_START_ERR) | 硬件是 TCXO 版本，芯片按无源模式启动失败 |
| B（ME-126XM TCXO） | `USE_TCXO` 开 1.8V | **挂死**（无 errors 打印） | Calibrate 阶段 TCXO 无输出，BUSY 一直高 |

### 阶段 4：定位挂死位置

在 `SX126xInit2` 每一步加打印：

```c
LLOGI("SX126xInit2 begin");
SX126xReset2(...);         LLOGI("after Reset");
SX126xWakeup2(...);        LLOGI("after Wakeup");
SX126xSetStandby2(...RC);  LLOGI("after SetStandby RC");
#ifdef USE_TCXO
    SX126xSetDio3AsTcxoCtrl2(...);  LLOGI("after SetDio3AsTcxoCtrl");
    SX126xCalibrate2(...);          LLOGI("after Calibrate");
#endif
```

**板 B 日志**：最后一条是 `after SetDio3AsTcxoCtrl`，没有 `after Calibrate`。

**结论**：`SX126xCalibrate` 里芯片启动 XOSC 尝试用 TCXO 时钟，但 TCXO 没起来，BUSY 一直高，`SX126xWaitOnBusy2` 死循环。

### 阶段 5：对比参考驱动

对比 `e:\work\custmoer\日浩lora\1.ME-126XM测试程序\src\radio\sx126x\sx126x.c` 的 `SX126xInit`：

```c
SX126xReset();
SX126xIoIrqInit(dioIrq);           // ← LuatOS 没这行（用软定时器轮询代替）
SX126xWakeup();
SX126xSetStandby(STDBY_XOSC);      // ← 参考用 XOSC，LuatOS 用 RC
#ifdef USE_TCXO
    SX126xSetDio3AsTcxoCtrl(TCXO_CTRL_1_8V, SX126xGetBoardTcxoWakeupTime() << 6);
    calibParam.Value = 0x7F;
    SX126xCalibrate(calibParam);
#endif
SX126xSetDio2AsRfSwitchCtrl(true);
```

**关键差异**：
1. 参考用 `STDBY_XOSC`，LuatOS 用 `STDBY_RC`
2. 参考驱动的 `radio.c` 里 `RadioInit` 之后也是 `STDBY_XOSC`

**尝试改为 XOSC**：
- 试过 `STDBY_XOSC` → 依然挂死（因为 TCXO 都没配前就切 XOSC，芯片没时钟，BUSY 一直高）

**正确顺序**（SX1262 官方推荐）：
```
Wakeup → STDBY_RC → SetDio3AsTcxoCtrl → Calibrate → [可选] STDBY_XOSC
```

### 阶段 6：软延时 + 延长 TCXO 启动时间（未解决）

**尝试配置**：
1. `USE_TCXO` 启用
2. 电压 `TCXO_CTRL_1_8V`
3. `RADIO_TCXO_SETUP_TIME` 从 5ms 改为 **10ms**
4. `SetDio3AsTcxoCtrl` 后追加 `SX126xDelayMs2(20)` 软延时

**实测结果**：**仍然挂死**，最后一条打印为 `after Delay20ms`，`Calibrate` 依然卡死。

**分析**：
- `SetDio3AsTcxoCtrl` 只是**写寄存器配置**，并不立即让 DIO3 输出电压
- 芯片只有在需要 XOSC（即 `Calibrate`）时才拉高 DIO3、等 `RADIO_TCXO_SETUP_TIME`
- 因此这 20ms 软延时期间 DIO3 还是 0V，TCXO 根本没供电
- 真正等 TCXO 稳定的时间由 `RADIO_TCXO_SETUP_TIME` 决定
- 单纯延长 setup 时间到 10ms 也没能解决问题

### 阶段 7：尝试其他 TCXO 电压（未解决）

**尝试**：`TCXO_CTRL_3_3V`（曾在早期尝试过，结果依旧挂死）

**结论**：仅靠软件调 TCXO 电压/时间已无法解决。

### 阶段 8：怀疑硬件问题（当前状态）

**推理链**：
1. 板 B 关掉 `USE_TCXO` → `errors=0x2000`（XOSC_START_ERR）→ 芯片以为要用无源 XTAL，但硬件没接 XTAL → 起不来
2. 板 B 开启 `USE_TCXO`（任意电压/时间）→ Calibrate 挂死 → DIO3 输出后 TCXO 没有产生 32MHz 时钟 → BUSY 永远高

两种现象都指向同一根因：**XOSC 起不来**。可能原因：
- TCXO 硬件损坏（元件失效）
- TCXO 焊接不良（虚焊 / 冷焊）
- DIO3 到 TCXO VCC 的走线断裂
- 元件缺件（BOM 有但未贴片）
- 芯片本身损坏（罕见）

**待做验证**：
- 万用表测 SX1262 的 DIO3 引脚电压（Calibrate 阶段应输出 1.8V）
- 示波器/频率计测 XTA 引脚（应有 32MHz 时钟信号）
- 与已知能工作的板子对换 LoRa 模块验证

## 当前代码状态

### `sx126x.c`

```c
#define USE_TCXO  // 有源晶振 (TCXO) 版本

void SX126xInit2(lora_device_t* lora_device, DioIrqHandler dioIrq)
{
    LLOGI("SX126xInit2 begin");
    SX126xReset2(lora_device);           LLOGI("after Reset");
    SX126xWakeup2(lora_device);          LLOGI("after Wakeup");
    SX126xSetStandby2(lora_device, STDBY_RC);
    LLOGI("after SetStandby RC");
#ifdef USE_TCXO
    CalibrationParams_t calibParam;
    SX126xSetDio3AsTcxoCtrl2(lora_device, TCXO_CTRL_1_8V, RADIO_TCXO_SETUP_TIME << 6);
    LLOGI("after SetDio3AsTcxoCtrl");
    SX126xDelayMs2(20);                  // 额外延时确保 TCXO 稳定
    LLOGI("after Delay20ms");
    calibParam.Value = 0x7F;
    SX126xCalibrate2(lora_device, calibParam);
    LLOGI("after Calibrate");
#endif
    SX126xSetDio2AsRfSwitchCtrl2(lora_device, true);
    LLOGI("after SetDio2AsRfSwitchCtrl");
    lora_device->OperatingMode = MODE_STDBY_RC;
    LLOGI("SX126xInit2 end");
}
```

### `sx126x.h`

```c
#ifdef USE_TCXO
    #define RADIO_TCXO_SETUP_TIME    10 // [ms]  （从 5ms 提升）
#else
    #define RADIO_TCXO_SETUP_TIME    0
#endif
```

### `radio.c`

```c
static void RadioInit(lora_device_t* lora_device, RadioEvents_t *events)
{
    memcpy(&lora_device->RadioEvents, events, sizeof(RadioEvents_t));
    lora_device->MaxPayloadLength = 0xFF;
    SX126xInit2(lora_device, RadioOnDioIrq);
    SX126xSetStandby2(lora_device, STDBY_RC);        // 保持 RC 简化状态
    SX126xSetRegulatorMode2(lora_device, USE_DCDC);
    SX126xSetBufferBaseAddress2(lora_device, 0x00, 0x00);
    SX126xSetTx2Params2(lora_device, 0, RADIO_RAMP_200_US);
    SX126xSetDioIrqParams2(lora_device, IRQ_RADIO_ALL, IRQ_RADIO_ALL, IRQ_RADIO_NONE, IRQ_RADIO_NONE);
}
```

### `luat_lib_lora.c`

```c
RadioEventsInit2(lora_device, &RadioEvents);
if (lora_device->lora_init) Radio2.Init(lora_device, &RadioEvents);

// 诊断打印
RadioError_t err = SX126xGetDeviceErrors2(lora_device);
RadioStatus_t st = SX126xGetStatus2(lora_device);
LLOGI("SX126x errors=0x%04X status=0x%02X (chipMode=%d cmdStatus=%d)",
      err.Value, st.Value, st.Fields.ChipMode, st.Fields.CmdStatus);
SX126xClearDeviceErrors2(lora_device);
```

## 结论与经验教训

### 已验证结论

1. **板 A（安信可 Ra-01SH，无源晶振）**：
   - 关闭 `USE_TCXO` 即可正常工作
   - 芯片直接使用 XTA/XTB 上的 32MHz 无源晶振
   - `errors=0x0000`，RX/TX 状态机正常

2. **板 B（日浩 ME-126XM，TCXO 版本）**：
   - 关闭 `USE_TCXO` → `errors=0x2000`（XOSC_START_ERR）
   - 启用 `USE_TCXO`（1.7V / 1.8V / 3.3V, 5ms / 10ms, ±20ms 软延时）→ **Calibrate 阶段全部挂死**
  
### 关键经验

1. **不要盲信硬件描述**，必须用芯片自诊断（`GetDeviceErrors` / `GetStatus`）验证
2. **DEVICE_READY 类 Lua 消息不能代表芯片工作正常**，只能说 `luat_lora_init` 没崩溃
3. **芯片挂死** 和 **芯片报错** 是两种不同现象：
   - 挂死 = BUSY 一直高，代码卡在 `WaitOnBusy` 死循环
   - 报错 = 命令能返回，但 `DeviceErrors` 寄存器有位置位
4. **STDBY_XOSC 不能在 TCXO 配置前调用**，否则芯片没时钟源 → BUSY 永远高
5. **软件模拟 IRQ (10ms 定时器轮询)** vs **硬件 IRQ (DIO1 中断)**：LuatOS 版是前者，超时事件也是靠芯片 IRQ 位判断的，芯片不工作 → 什么事件都收不到

### 参考驱动 vs LuatOS 版差异

| 项 | 参考 (STM32) | LuatOS |
|----|-------------|--------|
| IRQ 检测 | DIO1 硬件中断（`GpioSetInterrupt`） | 10ms 软定时器轮询 DIO1 电平 |
| 初始 Standby | `STDBY_XOSC` | `STDBY_RC`（当前保留） |
| TCXO 电压 | `TCXO_CTRL_1_8V` | `TCXO_CTRL_1_8V`（对齐后） |
| TCXO 启动时间 | `BOARD_TCXO_WAKEUP_TIME = 5ms` | `RADIO_TCXO_SETUP_TIME = 10ms`（延长） |
| CS 控制 | 每次命令手动拉 NSS | 通过 `luat_spi_device_transfer` 自动 |
| BUSY 等待 | `while(GpioRead(BUSY)==1)` | 相同，但加 1ms 延时 |

## 后续待办

- [x] 板 B 尝试 TCXO 1.8V + 10ms + 20ms 软延时 → **挂死**
- [x] 板 B 尝试 TCXO 3.3V → **挂死**


- [ ] **硬件排查（当前优先级最高）**：
    - 万用表量 SX1262 DIO3 引脚电压，看 Calibrate 阶段是否输出 1.8V
    - 示波器/频率计测 XTA 引脚，看 32MHz 时钟是否存在
    - 与板 A 交换 LoRa 模块位置，验证是否是模块故障 vs 主板故障
- [ ] 若硬件问题确认，联系模块供应商更换 / 返修
- [ ] 最终稳定后，清理所有 `LLOGI("after XXX")` 诊断打印
- [ ] 考虑将 TCXO 配置改为 Lua 运行时参数（避免两块板需要两份固件）

