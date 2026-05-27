# LuatOS 音频子系统 — 完整功能与流程分析

## 一、概述

LuatOS 音频子系统采用**分层解耦 + 面向接口**的设计思想，驱动、编解码器、DSP 算法均可插件式注册。核心框架通过**一个统一的控制器**管理请求、驱动、通道，支持多优先级请求抢占、多模式（播放/录音/通话/TTS）、多数据源（文件/ROM数组/流式）。

上层通过 Lua 脚本 API（`audio_v2` 模块，详见第十四章）和扩展库 `exaudio.lua` 暴露给开发者，底层硬件驱动通过函数指针表实现硬件无关的框架设计。

---

## 二、目录结构

```
audio/
├── include/                     # 头文件
│   ├── luat_audio_define.h      # 通用枚举（驱动类型/状态/模式/编解码器类型/事件/常量）
│   ├── luat_audio_core.h        # 音频框架入口 API 声明
│   ├── luat_audio_driver.h      # 驱动抽象层定义（opts函数表、ctrl控制器、电源管理）
│   ├── luat_audio_data_codec.h  # 编解码器抽象层定义（opts函数表、common_param、注册/绑定/查找）
│   ├── luat_audio_channel.h     # 通道管理层定义（FIFO、音量、播放/录音状态）
│   ├── luat_audio_request.h     # 请求块定义 & 高级 API（play_files/play_tts/record/speech）
│   └── luat_audio_dsp.h        # DSP 处理抽象层定义（create/destroy/process 三接口）
├── src/                         # 核心源文件
│   ├── luat_audio_core.c        # 核心逻辑（任务调度/状态机/请求排队/优先级抢占/音源读写）
│   ├── luat_audio_data_codec.c  # 编解码器注册/绑定/查找/编解码循环（软件+硬件双数组管理）
│   ├── luat_audio_driver.c      # 驱动通用逻辑（PA/CODEC 电源管理时序/启动/停止/反激活/填充静音）
│   └── luat_audio_channel.c     # 通道数据写入（位宽转换/声道数转换/音量控制/符号转换）
├── codec_adapter/               # 编解码器适配层（每个文件对应一种编解码器）
│   ├── luat_audio_codec_port_wav.c   # WAV 编解码器（无压缩直通+WAV头解析/生成）
│   ├── luat_audio_codec_port_mp3.c   # MP3 编解码器（基于 minimp3，仅解码）
│   ├── luat_audio_codec_port_amr.c   # AMR-NB/AMR-WB 编解码器（基于 3GPP 参考实现）
│   ├── luat_audio_codec_port_opus.c  # OPUS 编解码器（基于 libopus，旧版注释代码）
│   └── luat_audio_codec_port_g711.c  # G711 A-Law/μ-Law 编解码器（旧版注释代码）
└── describe.md                 # 本文件
```

---

## 三、分层架构

```
┌──────────────────────────────────────────────────────────────────┐
│                    Lua 层                                         │
│  audio_v2.play() / audio_v2.stream() / audio_v2.tts() / audio_v2.on()               │
│  exaudio.lua (扩展封装: 优先级队列/多文件播放/回调管理)            │
├──────────────────────────────────────────────────────────────────┤
│                    C 上层 API（luat_audio_request_xxx）            │
│  play_files / play_tts / record / speech / prepare / cancel      │
├──────────────────────────────────────────────────────────────────┤
│                  核心调度层（luat_audio_core.c）                    │
│  common_task（优先级90） · tts_task（优先级20） · 请求链表管理       │
│  优先级排序 · 中断事件回调 · 文件/ROM数据源抽象 · 自动编解码器搜索   │
├───────────────┬──────────────┬───────────────────────────────────┤
│  通道层         │  编解码器层   │  驱动层                           │
│ (channel.c)   │ (codec.c)   │ (driver.c + BSP实现)              │
│  音量/位宽/     │  WAV/AMR/    │  I2S/DAC/ADC/USB 接口            │
│  声道数/符号    │  MP3/OPUS/   │  PA/CODEC 电源管理(防爆破音)       │
│  转换          │  G711/TTS    │  播放/录音/全双工循环启动/停止     │
├───────────────┴──────────────┴───────────────────────────────────┤
│                  硬件层（BSP 实现 — 芯片厂商提供）                  │
│          DMA 传输 · I2S 控制器 · DAC/ADC 外设 · GPIO              │
└──────────────────────────────────────────────────────────────────┘
```

---

## 四、核心数据结构

### 4.1 全局控制器 `luat_audio_ctrl_t`（`luat_audio_core.c` 内部 static）

```c
typedef struct {
    luat_llist_head request_block_list;       // 请求块链表（按优先级降序排列）
    luat_audio_driver_ctrl_t driver_ctrl[LUAT_AUDIO_DRIVER_MAX]; // 驱动控制器数组（最多4个）
    luat_audio_channel_t channel[LUAT_AUDIO_DRIVER_MAX]; // 通道数组（与驱动一一对应）
    luat_audio_request_block_t *current_request_block; // 当前正在处理的请求
    luat_rtos_task_handle common_task_handle;  // 通用任务句柄（优先级90, 栈13KB, 事件队列64）
    luat_rtos_task_handle tts_task_handle;    // TTS 独立任务句柄（优先级20, 栈13KB）
    void *request_lock;                       // 请求链表操作互斥锁
    void *tts_wait_sem;                       // TTS 等待信号量（初始锁定）
    uint32_t next_request_id;                 // 自增请求 ID
    uint8_t default_driver_index;             // 默认驱动索引
    uint8_t decode_is_running:1;              // 解码标志位
} luat_audio_ctrl_t;
```

### 4.2 `luat_audio_common_param_t`（`luat_audio_data_codec.h`）

```c
typedef struct {
    uint32_t frame_size;          // 帧大小（bytes）
    uint32_t sample_rate;         // 采样率（Hz）
    uint8_t channel_nums;         // 声道数（1=Mono, 2=Stereo）
    uint8_t data_align;           // 位宽对齐（1=8位, 2=16位, 3=24位, 4=32位）
    uint8_t is_signed;            // 有无符号（1=有符号, 0=无符号）
    uint8_t driver_work_mode;     // 工作模式（PLAY/RECORD/CALL/CALL_WITH_BUFFER）
} luat_audio_common_param_t;
```

此结构在编解码器和驱动控制器中**各有一份**，构成音频数据的完整描述。通道层处理时以此对比输入与驱动的参数差异。

### 4.3 `luat_audio_driver_ctrl_t`（`luat_audio_driver.h`）

| 字段 | 类型 | 说明 |
|------|------|------|
| `opts` | `const luat_audio_driver_opts_t*` | 驱动函数表指针 |
| `driver_data` | `void*` | 驱动私有数据 |
| `data_channel` | `luat_audio_channel_t*` | 关联通道指针 |
| `probe` | `luat_audio_driver_probe_t` | 驱动匹配条件（bus_type, bus_id）|
| `play_buff / record_buff` | `union {uint32_t*, uint8_t*}` | 播放/录音 DMA 缓冲 |
| `last_play_cnt / current_play_cnt` | `volatile uint32_t` | 播放计数（环形）|
| `one_play_block_len / one_record_block_len` | `uint32_t` | 单 block 大小 |
| `common_param` | `luat_audio_common_param_t` | 驱动当前公共参数 |
| `pa_power_* / codec_power_*` | 多位域 | 电源管理状态 |
| `state` | `volatile uint8_t` | 驱动状态机 |

### 4.4 `luat_audio_request_block_t`（`luat_audio_request.h`）

| 字段 | 说明 |
|------|------|
| `node` | 链表节点（用于请求队列管理）|
| `request_id` | 自增唯一请求 ID |
| `cb` | 请求事件回调函数 |
| `done_sem` | 同步模式信号量 |
| `temp_buff` | 临时缓冲区（文件信息/文本/其他）|
| `file_info / file_info_cnt / file_done_cnt` | 文件播放列表 |
| `tts_data / tts_data_size` | TTS 文本数据 |
| `play_buff / one_block_len / block_nums` | 流模式驱动缓冲参数 |
| `record_data_fifo` | 录音数据 FIFO |
| `org_input_data_fifo` | 原始编码数据 FIFO |
| `out_buffer` | 解码输出 PCM 缓冲区 |
| `dsp` | DSP 处理实例（预留）|
| `codec` | 编解码器实例 |
| `data_channel` | 关联音频通道 |
| `priority` | 优先级（0-255，数值越大优先级越高）|
| `driver_work_mode` | 驱动工作模式 |
| `is_stream / is_tts / is_stream_end` | 请求类型标志 |
| `is_user_stop / is_error_stop` | 停止标志 |
| `is_file_end / is_wait_play_end` | 文件播放状态 |

### 4.5 `luat_audio_channel_t`（`luat_audio_channel.h`）

| 字段 | 说明 |
|------|------|
| `play_fifo` | 播放 FIFO（中断上下文消费，仅1个消费者）|
| `play_fifo_low_level` | 低水位（默认 2^15 字节，触发数据请求）|
| `play_fifo_high_level` | 高水位（FIFO 满的阈值，停止解码）|
| `play_lock_mutex` | 写入保护互斥锁 |
| `driver_ctrl` | 关联驱动控制器 |
| `soft_vol` | 软件音量（0-1000，默认100=原始音量）|
| `user_play_stop / user_record_stop` | 用户停止标志 |

---

## 五、模块详解

### 5.1 枚举定义（`luat_audio_define.h`）

| 枚举族 | 值范围 | 说明 |
|--------|------|------|
| `LUAT_AUDIO_CHANNEL_*` | `MONO=0, LEFT, RIGHT, STEREO` | 声道配置 |
| `LUAT_AUDIO_DRIVER_TYPE_*` | `NONE=0, I2S=1, DAC=2, ADC=3, USB=4` | 硬件接口类型 |
| `LUAT_AUDIO_DRIVER_CONFIG_PARAM_*` | `I2S_MODE=0, I2S_FRAME_TYPE, DAC_BIT_WIDTH` | 驱动私有参数索引 |
| `LUAT_AUDIO_DRIVER_EVENT_*` | `TX_ONE_BLOCK_DONE=0, RX_ONE_BLOCK_DONE` | 中断回调事件 |
| `LUAT_AUDIO_DRIVER_STATE_*` | `IDLE=0, INITED, ACTIVE, RUNNING` | 驱动状态机 |
| `LUAT_AUDIO_DRIVER_MODE_*` | `NONE=0, PLAY, RECORD, CALL, CALL_WITH_BUFFER` | 驱动工作模式 |
| `LUAT_AUDIO_DATA_CODEC_TYPE_*` | `RAW=0, WAV=1, AMR_NB=2, AMR_WB=3, TTS=4, MP3=5, OPUS=6, G711=7, MAX=8` | 编解码器标识 |
| `LUAT_AUDIO_REQUEST_EVENT_*` | `START=0, NEED_NEW_DATA, GET_NEW_DATA, DECODE_DONE, END, ALL_PLAY_DATA_DONE` | 请求回调事件 |

#### 平台可配置常量

| 宏 | 默认值 | 说明 |
|----|--------|------|
| `LUAT_AUDIO_DRIVER_MAX` | 4 | 最大驱动数量 |
| `LUAT_AUDIO_CHANNEL_FIFO_DEFAULT_SIZE_POWER` | 17 | 播放 FIFO 大小 = 2^17 = 128KB |
| `LUAT_AUDIO_DATA_CODEC_INPUT_FIFO_DEFAULT_SIZE_POWER` | 14 | 编解码器输入 FIFO = 2^14 = 16KB |
| `LUAT_AUDIO_TASK_STACK` | 13*1024 | 音频任务栈大小 |

---

### 5.2 驱动抽象层（`luat_audio_driver.h` + `luat_audio_driver.c`）

#### 驱动匹配机制

```c
typedef struct luat_audio_driver_probe {
    uint8_t bus_type;   // 总线类型（I2S/DAC/ADC/USB...）
    uint8_t bus_id;     // 总线编号
} luat_audio_driver_probe_t;
```

驱动通过 `(bus_type, bus_id)` 元组匹配。`luat_audio_driver_probe(NULL)` 返回默认驱动。最多支持 4 个驱动并行注册。

#### 操作函数表（`luat_audio_driver_opts_t` — 13 个函数指针 + 能力描述字段）

| 函数 | 说明 |
|------|------|
| `init` | 初始化硬件（DMA/GPIO/时钟配置）|
| `config_private_param` | 配置 I2S 模式/帧格式/DAC 位宽等私有参数 |
| `activate` | 激活（退出低功耗、提供 I2S MCLK）|
| `modify_audio_common_param` | 配置采样率/位宽/声道 |
| `fill` | 填充空白音到 DMA 缓存（静音数据）|
| `start_tx_loop` | 启动播放 DMA 循环 |
| `start_rx_loop` | 启动录音 DMA 循环 |
| `start_full_loop` | 启动全双工 DMA 循环 |
| `rx_interrupt_switch` | 切换录音中断使能 |
| `start_full_loop_with_play_buff` | 全双工 + 外部播放缓冲（如 LTE 通话）|
| `stop` | 停止 DMA 循环 |
| `deactivate` | 反激活（进低功耗、关 MCLK）|
| `deinit` | 反初始化（释放硬件资源）|

**能力描述字段**：

| 字段 | 说明 |
|------|------|
| `tx_one_block_max_len` | 播放单 block 最大长度（8 字节对齐）|
| `rx_one_block_max_len` | 录音单 block 最大长度 |
| `support_tx_loop` | 是否支持播放循环 |
| `support_rx_loop` | 是否支持录音循环 |
| `support_full_loop` | 是否支持全双工循环 |
| `support_continue` | 是否支持继续播放 |
| `is_signed` | 驱动数据是否为有符号格式 |

#### 驱动状态机

```
IDLE (未初始化)
  │  opts->init()
  v
INITED (已初始化)
  │  opts->activate()
  v
ACTIVE (已激活)
  │  opts->start_tx_loop / start_rx_loop / start_full_loop
  v
RUNNING (运行中)
  │  opts->stop()
  v
ACTIVE
  │  opts->deactivate()
  v
INITED
```

#### PA/CODEC 电源管理时序

```
luat_audio_driver_start() 调用时：

  ① 检查当前状态
     [INITED] → opts->activate() → state=ACTIVE
     [ACTIVE] → 跳过
     [RUNNING且模式切换] → opts->stop() → state=ACTIVE

  ② opts->modify_audio_common_param()    // 设置采样率/位宽/声道

  ③ 根据 driver_work_mode 启动对应循环:
     PLAY              → support_full_loop ? start_full_loop : start_tx_loop
     RECORD            → support_full_loop ? start_full_loop : start_rx_loop
     CALL              → start_full_loop (必须支持全双工)
     CALL_WITH_BUFFER  → start_full_loop_with_play_buff

  ④ state = RUNNING

  ⑤ CODEC 上电:
     - gpio_set(codec_power_pin, on_level)
     - 启动 codec_ready_after_wakeup_timer
     - 定时器到期 → codec_ready_state=1

  ⑥ PA 上电:
     - 启动 pa_power_on_delay_timer
     - 定时器到期 → gpio_set(pa_power_pin, on_level), pa_power_state=1

  ⑦ 当 codec_ready_state && pa_power_state && codec_power_state 都就绪
     → audio_output_enable = 1（输出使能，DMA 数据开始送达 DAC/I2S）

luat_audio_driver_stop():
  ① opts->stop() → state=ACTIVE
  ② audio_output_enable = 0

PA/CODEC 下电（外部调用）:
  luat_audio_driver_pa_power_off()    → 先关 PA（防止爆破音）
  luat_audio_driver_codec_power_off() → 延时后关 CODEC
```

#### 填充空白音策略（`luat_audio_driver_fill_default`）

| 有符号 | 位宽 | 填充值 |
|--------|------|--------|
| 是 | 任意 | `0x00` （静音 = 零）|
| 否 | 8位 | `0x80` （无符号中点）|
| 否 | 16位 | `0x8000` |
| 否 | 24位 | `0x008000` |
| 否 | 32位 | `0x80000000` |

---

### 5.3 编解码器抽象层（`luat_audio_data_codec.h` + `luat_audio_data_codec.c`）

#### 核心设计

- 软件编解码器和硬件编解码器**分两个数组管理**（`_audio_data_codec_software_items[]` / `_audio_data_codec_hardware_items[]`）
- 硬件编解码器不可重入，绑定后标记 `is_busy`
- `luat_audio_data_codec_find(type)` 先找硬件、再找软件

#### 编解码器操作函数集（`luat_audio_data_codec_opts_t`）

| 函数 | 说明 |
|------|------|
| `init` | 初始化编解码器实例（分配解码器/编码器上下文）|
| `deinit` | 释放编解码器实例 |
| `get_play_info` | 解析文件头获取播放参数（支持多轮读取）|
| `pre_decode` | 预解码获取帧大小（AMR 变长帧需要）|
| `decode` | 解码一帧数据（编码 PCM → PCM）|
| `make_head` | 生成编码文件头（WAV/AMR）|
| `encode` | 编码一帧数据（PCM → 编码格式）|
| `tts_decode` | TTS 文本转语音 |
| `tts_set_param` | 设置 TTS 参数 |

**编解码器属性**：

| 字段 | 说明 |
|------|------|
| `type` | 编解码器类型枚举 |
| `is_reentrant` | 是否可重入（可同时多实例使用）|
| `is_hardware` | 是否硬件编解码器（不可重入，用 is_busy 保护）|
| `support_detect` | 是否支持文件头自动检测 |
| `decode_min_input_len` | 解码最小输入长度（0 表示变长帧，需 pre_decode）|
| `decode_max_output_len` | 解码最大输出长度 |
| `encode_min_input_len` | 编码最小输入长度 |
| `encode_max_output_len` | 编码最大输出长度 |

#### 编解码器生命周期

```
luat_audio_data_codec_register()   → 注册编解码器（BSP 启动时调用）

luat_audio_data_codec_bind()       → 分配 input_buffer，标记 is_busy
luat_audio_data_codec_deinit()     → 调用 opts->init()
                                         ↓
luat_audio_data_codec_decode_once() → 循环解码
luat_audio_data_codec_encode_once() → 循环编码
                                         ↓
luat_audio_data_codec_deinit()     → 调用 opts->deinit()，释放 input_buffer
luat_audio_data_codec_unbind()     → 清除 busy 标记
```

#### 解码循环逻辑（`luat_audio_data_codec_decode_once`）

```
while (output_buffer 有空间) {
    if (decode_min_input_len > 0) {
        // 定长帧：从 fifo 读取 decode_min_input_len 字节
        if (数据不足) {
            if (is_end) 读取剩余全部数据
            else return（等待更多数据）
        }
    } else {
        // 变长帧（AMR）：读数据 → pre_decode 获取帧大小
        if (帧大小 > 输入长度) return
    }
    调用 opts->decode()
    从 fifo 删除已消耗的 used_len
    累加 output_buffer->pos
}
```

#### 已实现的编解码器适配器

##### WAV 编解码器（`luat_audio_codec_port_wav.c`）

| 属性 | 值 |
|------|-----|
| type | `LUAT_AUDIO_DATA_CODEC_TYPE_WAV` |
| 可重入 | 是 |
| 硬件加速 | 否 |
| 支持自动检测 | 是 |
| `decode_max_output_len` | 4096 |
| `decode_min_input_len` | 4096 |

WAV 解码是**直通模式**（PCM 不压缩，输入直接复制到输出）。仅支持 16 位 PCM WAV。
`get_play_info` 解析 RIFF/WAVE 文件头，遍历 chunk 定位到 `data` 块。

##### MP3 编解码器（`luat_audio_codec_port_mp3.c`）

| 属性 | 值 |
|------|-----|
| type | `LUAT_AUDIO_DATA_CODEC_TYPE_MP3` |
| 可重入 | 是 |
| 硬件加速 | 否 |
| 支持自动检测 | 是 |
| `decode_max_output_len` | 4 × 1152 × 2（1792 样本）|
| `decode_min_input_len` | 1792 字节 |

基于 [minimp3](https://github.com/lieff/minimp3) 实现，**仅支持解码**，不支持编码。
`get_play_info` 支持跳过 ID3v2 标签头。

##### AMR-NB / AMR-WB 编解码器（`luat_audio_codec_port_amr.c`）

| 属性 | AMR-NB | AMR-WB |
|------|--------|--------|
| type | `AMR_NB` | `AMR_WB` |
| 采样率 | 8000 Hz | 16000 Hz |
| 帧大小 | 320 字节 PCM | 640 字节 PCM |
| `decode_min_input_len` | 0（变长帧）| 0（变长帧）|
| `decode_max_output_len` | 320 | 640 |
| 文件头 | `#!AMR\n` | `#!AMR-WB\n` |

基于 3GPP 参考实现（`interf_dec.h` / `interf_enc.h`）。支持编解码。
变长帧通过 `pre_decode` 从帧头提取 mode 查找 `amr_nb_byte_len[]` / `amr_wb_byte_len[]` 表。
`get_play_info` 通过魔术字 `#!AMR\n` / `#!AMR-WB\n` 识别。

##### OPUS 编解码器（`luat_audio_codec_port_opus.c`）

当前为**注释代码**（`#if 0`）。基于 libopus，支持编解码。自定义帧格式：2 字节大端长度前缀 + Opus 数据包。

##### G711 编解码器（`luat_audio_codec_port_g711.c`）

当前为**注释代码**（`#if 0`）。基于 `g711_codec/g711_codec.h`。固定 8kHz 采样率，单声道，8 位深度。

---

### 5.4 通道层（`luat_audio_channel.h` + `luat_audio_channel.c`）

#### `luat_audio_channel_write_data()` — 核心函数

输入 PCM 数据写入播放 FIFO 前，经过**三阶段处理**：

```
阶段1：软件音量调节
  - 仅当 channel->soft_vol != 0 && != 100 时执行
  - 16位数据：_audio_channel_play_vol_16bit（限幅 ±32767）
  - 24/32位数据：_audio_channel_play_vol_32bit（限幅 ±2147483647）
  - 公式：temp = data[i] * vol / 100

阶段2：有无符号转换（仅当输入与驱动要求不一致时）
  ╔══════════════════╦═══════════════════╦═══════════════════╗
  ║ 输入\转换方向     ║ 无符号→有符号      ║ 有符号→无符号      ║
  ╠══════════════════╬═══════════════════╬═══════════════════╣
  ║ 8位              ║ ^0x80             ║ - 0x80            ║
  ║ 16位             ║ ^0x8000           ║ - 0x8000          ║
  ║ 24位             ║ ^0x800000         ║ (-0x800000)&0xFFFFFF║
  ║ 32位             ║ ^0x80000000       ║ - 0x80000000      ║
  ╚══════════════════╩═══════════════════╩═══════════════════╝

阶段3：格式适配（输入与驱动参数不匹配时转换）

  情况A: 位宽+声道数完全匹配 → 直接写入 FIFO ✅（零拷贝路径）
  
  情况B: 位宽匹配 + 声道数不匹配 → 声道数转换
    - 输入声道数 > 驱动声道数：丢弃多余声道（取前 N 个）
    - 输入声道数 < 驱动声道数：复制填充
      - 单声道→双声道：左右声道填同一数据
      - 单声道→多声道：所有声道填同一数据
  
  情况C: 声道数匹配 + 位宽不匹配 → 位宽转换
    ┌──────────────┬──────────────────────────────────────────────────┐
    │ 输入\输出     │ 8位(1)        │ 16位(2)    │ 24位(3)    │ 32位(4)   │
    ├──────────────┼───────────────┼────────────┼────────────┼──────────┤
    │ 8位(1)       │ -             │ << 8       │ << 16      │ << 24    │
    │ 16位(2)      │ >> 8          │ -          │ << 8       │ << 16    │
    │ 24位(3)      │ >> 16         │ >> 8       │ << 8       │          │
    │ 32位(4)      │ >> 24         │ >> 16      │ >>8&0xFFFFFF│ -        │
    └──────────────┴───────────────┴────────────┴────────────┴──────────┘

  情况D: 位宽+声道数都不匹配 → 返回错误 -LUAT_ERROR_PARAM_INVALID
```

#### FIFO 水位机制

- **低水位**（`play_fifo_low_level`）：默认 FIFO 大小的 25%（2^15 = 32KB）。当 FIFO 空闲空间 ≥ 低水位时，触发 `LUAT_AUDIO_EV_TX_NEED_DATA` 事件，驱动从文件/流读取更多数据解码。
- **高水位**（`play_fifo_high_level`）：默认 FIFO 大小 - 2^14（128KB - 16KB = 112KB）。解码循环持续到 FIFO 数据量 ≥ 高水位为止。

---

### 5.5 DSP 处理层（`luat_audio_dsp.h`）

简化的 DSP 抽象，支持三个接口：

| 接口 | 说明 |
|------|------|
| `create` | 创建 DSP 实例上下文 |
| `destroy` | 销毁 DSP 实例上下文 |
| `process` | 执行 DSP 处理（支持 input + ref_input 双通道，用于回声消除）|

当前 DSP 层已定义接口但**尚未集成到主播放/录音流程**中。

---

### 5.6 请求层（`luat_audio_request.h` + `luat_audio_core.c`）

#### 高级 API

| API | 功能 | 实现状态 |
|-----|------|---------|
| `luat_audio_request_play_files` | 播放文件列表（支持文件路径/ROM 数组）| ✅ 已实现 |
| `luat_audio_request_play_tts` | TTS 文本转语音播放 | ✅ 已实现 |
| `luat_audio_request_play_stream` | 流模式音频播放（指定 codec + common_param）| ✅ 已实现 |
| `luat_audio_request_record` | 录音（声明未实现）| ⚠️ 声明仅为框架预留 |
| `luat_audio_request_speech` | 通话（声明未实现）| ⚠️ 声明仅为框架预留 |
| `luat_audio_request_prepare` | 低级 API：请求准备 | ✅ 已实现 |
| `luat_audio_request_cancel` | 取消请求 | ✅ 已实现 |
| `luat_audio_request_start` | 提交请求（同步/异步）| ✅ 已实现 |

#### 请求块核心字段详解

| 字段组 | 字段 | 说明 |
|--------|------|------|
| 文件播放 | `file_info[]` | 每个文件可指定 path/fd/rom_data/rom_data_len/fail_continue |
| TTS | `tts_data / tts_data_size` | 待合成文本 |
| 流播放 | `union { play_buff / one_block_len / block_nums }` | 低级流式数据缓冲区参数；高级流 API 使用 `org_input_data_fifo` + `REQUEST_NEED_NEW_DATA` 回调驱动 |
| 录音 | `record_data_fifo` | 录音数据 FIFO |
| 解码 | `codec` | 编解码器实例（含 common_param）|
| | `org_input_data_fifo` | 原始编码数据输入 FIFO |
| | `out_buffer` | 解码输出 PCM 缓冲区 |
| 同步 | `done_sem` | 同步模式：用互斥锁阻塞等待 |

#### 数据源抽象

音频框架支持两种数据源，通过 `luat_audio_play_file_info_t` 统一抽象：

```c
typedef struct {
    union {
        const char *path;         // 文件路径（文件模式）
        FILE *fd;                 // 文件描述符（运行时由 luat_fs_fopen 获得）
        const uint8_t *rom_data;  // ROM 数组地址（内存模式）
    };
    uint32_t rom_data_len;        // ROM 数组长度（0 表示文件模式）
    uint32_t rom_data_offset;     // ROM 数组当前读取偏移
    uint32_t fail_continue;       // 解码失败是否跳过继续
} luat_audio_play_file_info_t;
```

`_audio_data_read_to_fifo()` 和 `_audio_data_read_to_buffer()` 内部判断 `rom_data_len`：
- `== 0`：通过 `luat_fs_fread` 从文件读取
- `!= 0`：从内存数组直接 `memcpy`

`_audio_data_seek()` 同样支持文件和内存两种模式的 `SEEK_SET` / `SEEK_CUR` / `SEEK_END`。

---

## 六、核心流程

### 6.1 系统初始化流程

```
BSP 启动时（luavm 初始化前）:
  luat_audio_base_init()
    ├─ 创建 common_task（优先级 90，栈 13KB，事件队列 64）
    ├─ 创建 tts_task（优先级 20，栈 13KB）
    ├─ 创建 request_lock 互斥锁
    ├─ 创建 tts_wait_sem 并立即加锁
    └─ 初始化请求链表

  luat_audio_data_codec_register(&wav_opts)      // 注册 WAV 编解码器
  luat_audio_data_codec_register(&mp3_opts)      // 注册 MP3 编解码器
  luat_audio_data_codec_register(&amr_nb_opts)   // 注册 AMR-NB
  luat_audio_data_codec_register(&amr_wb_opts)   // 注册 AMR-WB

  luat_audio_driver_register(opts, probe, data)  // 注册硬件驱动
    ├─ opts->init() → state=INITED
    ├─ 创建 play_fifo（默认 128KB）
    ├─ 设置低水位（32KB）、高水位（112KB）
    ├─ 设置软件音量（100 = 原始音量）
    └─ 关联 channel[i].driver_ctrl = &driver_ctrl[i]

  luat_audio_driver_config_pa_power_ctrl()       // 配置 PA 电源管理
  luat_audio_driver_config_codec_power_ctrl()    // 配置 CODEC 电源管理
```

### 6.2 请求生命周期（文件播放）

```
Lua 层 audio_v2.play("/music.mp3")
  └─ C 层 luat_audio_request_play_files()
      ├─ luat_audio_request_prepare()
      │   ├─ luat_audio_request_init()     // 生成 request_id
      │   └─ luat_audio_driver_probe()     // 匹配驱动（或取默认驱动）
      ├─ 打开文件（luat_fs_fopen）
      ├─ 复制 file_info 到 temp_buff
      └─ luat_audio_request_start(is_sync)
          ├─ 请求插入链表（按优先级降序）
          └─ 发送 LUAT_AUDIO_EV_REQUEST 事件

common_task 收到 EV_REQUEST:
  ├─ 无 current_request → _audio_find_next_request_block() ← 取链表头
  ├─ 有 current_request → 检查新请求优先级是否更高
  │   └─ 更高 → 当前请求压回链表 → 新请求上场
  └─ _audio_start_request()
      ├─ 回调 EVENT_START
      ├─ _audio_decode_file_start()
      │   ├─ 创建 org_input_data_fifo（16KB）
      │   ├─ _audio_decode_current_request_play_info()
      │   │   ├─ 已指定 codec → 直接 get_play_info
      │   │   └─ 未指定 codec → 遍历所有 support_detect 的编解码器
      │   │                        逐个尝试 get_play_info 自动识别
      │   ├─ 创建 out_buffer（decode_max_output_len * 4）
      │   └─ is_stream_end = 0
      ├─ modify_audio_common_param（设置采样率/位宽/声道）
      ├─ _audio_decode_file_to_fifo()
      │   └─ while (FIFO 数据 < 高水位):
      │       ├─ _audio_data_read_to_fifo()       // 文件 → org_input_fifo
      │       ├─ 读到文件尾 → 切换下一个文件
      │       └─ luat_audio_data_codec_decode_once()
      │           └─ org_input_fifo → 解码 → out_buffer
      │           └─ luat_audio_channel_write_data()
      │               └─ play_fifo
      └─ luat_audio_driver_start()               // 启动 DMA 循环

播放中（中断上下文）:
  DMA TX 完成 → LUAT_AUDIO_DRIVER_EVENT_TX_ONE_BLOCK_DONE
    └─ _audio_play_next_block()
        ├─ 从 play_fifo 读数据到 DMA 缓冲
        ├─ 不足则 fill 空白音
        └─ 若 FIFO 空闲 ≥ 低水位
            → 发送 EV_TX_NEED_DATA → common_task 解码更多

请求完成:
  common_task 检测 is_file_end && FIFO 空
    → is_wait_play_end = 1
    → 连续 3 次请求空白数据 → is_stream_end = 1
    → _audio_request_finish()
        ├─ luat_audio_request_deinit()    // 关闭文件、释放 FIFO/buffer
        ├─ 回调 EVENT_END
        └─ 发送 EV_REQUEST → 处理下一个排队请求
```

### 6.3 驱动启动流程

```
luat_audio_driver_start(ctrl, common_param, play_buff, one_block_len, block_nums)
  ├─ [INITED] opts->activate() → state=ACTIVE
  ├─ [RUNNING 且模式切换] opts->stop() → state=ACTIVE
  ├─ opts->modify_audio_common_param()
  ├─ 根据 mode 选择启动函数:
  │   ├─ PLAY       → support_full_loop ? start_full_loop : start_tx_loop
  │   ├─ RECORD     → support_full_loop ? start_full_loop : start_rx_loop
  │   ├─ CALL       → start_full_loop
  │   └─ CALL_WITH_BUFFER → start_full_loop_with_play_buff
  ├─ state = RUNNING
  ├─ CODEC 上电 → codec_ready_after_wakeup_timer → codec_ready_state=1
  ├─ PA 上电 → pa_power_on_delay_timer → pa_power_state=1
  └─ codec_power_state && codec_ready_state && pa_power_state
      → audio_output_enable = 1
```

### 6.4 TTS 独立任务流程

```
luat_audio_request_play_tts()
  ├─ prepare → bind(TTS codec) → codec.init → 复制文本到 temp_buff
  └─ start() → 发送 EV_REQUEST

common_task 收到 EV_REQUEST:
  └─ is_tts → 发送 EV_TTS_RUN → tts_task 处理

tts_task:
  └─ opts->tts_decode() 循环
      └─ 回调 _audio_tts_output_callback(data, len):
          ├─ [data==NULL] → 首次回调，启动驱动
          └─ [data!=NULL] → luat_audio_channel_write_data()
                            → 写入 play_fifo
                            → FIFO 满则等待 tts_wait_sem
                           ← 等待 common_task 消费后释放信号量

common_task 收到 EV_TX_NEED_DATA:
  └─ is_tts → luat_mutex_unlock(tts_wait_sem)  // 唤醒 TTS 任务
```

### 6.5 流模式请求流程

```
luat_audio_request_play_stream() [上层由 audio_v2.stream() 调用]:
  ├─ prepare → is_stream = 1
  ├─ 用户必须指定 codec（流模式不支持自动搜索）
  ├─ 绑定 codec + 设置 common_param（sample_rate / channel_nums / data_align / is_signed）
  ├─ luat_audio_driver_start()
  └─ 回调 EVENT_START

播放中 common_task 收到 EV_TX_NEED_DATA:
  ├─ _audio_decode_stream_to_fifo()
  │   ├─ 从 org_input_data_fifo 读取编码数据
  │   ├─ 调用 codec->decode() 解码
  │   └─ 写入 channel->play_fifo
  └─ 回调 EVENT_NEED_NEW_DATA → 用户写入新数据到 org_input_fifo

用户通过 `audio_v2.stream()` 启动流播放，并在 `audio_v2.on()` 回调的 `REQUEST_NEED_NEW_DATA` 事件中写入数据到 `org_input_fifo`
```

---

### 6.6 优先级抢占流程

```
请求块链表按优先级降序排列（同优先级尾插插入）:

  luat_audio_request_start()
    └─ _audio_add_request()
        ├─ 遍历链表 → 找到第一个 priority < 新请求的位置
        └─ 插到前面（优先级高的在前面）

common_task 收到 EV_REQUEST:
  ├─ 无 current_request → 取链表头
  ├─ 有 current_request → 检查链表头优先级是否更高
  │   └─ 更高 → 当前请求压回链表 → 新请求上场
  └─ _audio_start_request()
      └─ 重启驱动（不同模式时先 stop）
```

### 6.7 同步/异步模式

```c
// 异步模式（默认）
luat_audio_request_start(request_block, 0);  // 立即返回
// 完成后通过 EVENT_END 回调通知

// 同步模式
luat_audio_request_start(request_block, 1);
// 内部：创建 done_sem → lock → 提交请求 → lock（等待完成）
// 完成后 EVENT_END 回调中 unlock → 函数返回
```

同步模式通过 `done_sem`（互斥锁）实现：
1. 创建新的互斥锁 `done_sem` 并存入 `request_block->done_sem`
2. 锁定 `done_sem`
3. 提交请求
4. 再次锁定 `done_sem`（阻塞等待）
5. `_audio_request_finish()` 中 `luat_mutex_unlock(done_sem)` → 唤醒

---

## 七、请求事件回调一览

| 事件 | 触发时机 | data/len |
|------|---------|---------|
| `EVENT_START` | 请求开始处理 | NULL |
| `EVENT_NEED_NEW_DATA` | 流模式需要更多数据 | NULL |
| `EVENT_GET_NEW_DATA` | 录音数据可用（FIFO 数据 ≥ 水位）| rx_data / len |
| `EVENT_DECODE_DONE` | 文件解码完成（预留）| NULL |
| `EVENT_END` | 请求结束（正常/出错/用户停止）| NULL |
| `ALL_PLAY_DATA_DONE` | 所有播放数据已写入 FIFO | NULL |

---

## 八、数据流图

### 播放数据流（文件播放）

```
文件（Filesystem）
  ↓ _audio_data_read_to_fifo()
org_input_data_fifo（16KB 编码数据 FIFO）
  ↓ luat_audio_data_codec_decode_once()
out_buffer（解码输出 PCM 缓冲区）
  ↓ luat_audio_channel_write_data()
  ├─ 软件音量调节
  ├─ 有无符号转换
  ├─ 声道数适配
  └─ 位宽适配
  ↓
channel->play_fifo（128KB PCM 数据 FIFO）
  ↓ [中断上下文 — _audio_play_next_block()]
driver->play_buff[]（DMA 双/多缓冲）
  ↓ [DMA 传输]
DAC / I2S 硬件输出
```

### 录音数据流

```
ADC / I2S 硬件输入
  ↓ [DMA 传输]
driver->record_buff[]（DMA 双/多缓冲）
  ↓ [中断回调 — luat_audio_driver_event_callback]
channel->record_request_block->record_data_fifo
  ↓ [common_task — EVENT_RX_ENOUGH_DATA]
回调 EVENT_GET_NEW_DATA → 用户取走录音数据
```

### 播放数据流（流模式）

```
用户（Lua/C 应用层）
  ↓ audio_v2.stream() / luat_audio_channel_write_data()
  ↓ EVENT_NEED_NEW_DATA 回调 → 用户推数据到 org_input_fifo
org_input_data_fifo（编码数据 FIFO）
  ↓ luat_audio_data_codec_decode_once()
out_buffer
  ↓ luat_audio_channel_write_data()
channel->play_fifo
  ↓ [中断上下文]
DMA → 硬件输出
```

### 播放数据流（TTS）

```
TTS 文本
  ↓ tts_task — opts->tts_decode()
PCM 数据块
  ↓ _audio_tts_output_callback()
  ↓ luat_audio_channel_write_data()
channel->play_fifo
  ↓ [中断上下文]
DMA → 硬件输出
```

### 数据流（ROM 数组）

```
ROM 中的音频数据（如开机音效在 Flash 中的数组）
  ↓ _audio_data_read_to_fifo() — 直接 memcpy
org_input_data_fifo
  ↓ 解码
...（同文件播放流）
```

---

## 九、关键设计要点

| 特性 | 实现方式 |
|------|---------|
| **低延迟播放** | 双/多缓冲 + DMA 中断驱动 + FIFO 生产者-消费者模型 |
| **优先级抢占** | 请求链表按优先级降序排列，新请求以更高优先级可抢占当前播放 |
| **同步/异步** | 同步模式用 `done_sem` 互斥锁阻塞等待 |
| **电源管理** | PA/CODEC 独立定时器控制，先启 CODEC 再启 PA（上电），先关 PA 再关 CODEC（下电），防爆破音 |
| **位宽自适应** | 8/16/24/32 位任意互转（移位/掩码），支持 24-bit packed-in-32 格式 |
| **声道自适应** | Mono↔Stereo 自动扩展/缩减（复制或丢弃声道数据）|
| **符号自适应** | 有符号/无符号自动转换（XOR/加减操作）|
| **驱动热插拔** | 最多 4 个驱动并行注册，通过 `probe(bus_type, bus_id)` 匹配 |
| **零拷贝传输** | 同声道同位宽时直接 `luat_fifo_write` 直达硬件 FIFO |
| **TTS 隔离** | 独立低优先级任务处理，不阻塞主播放流程 |
| **自动编解码器识别** | 遍历所有 `support_detect` 编解码器，逐一代用 `get_play_info` 尝试 |
| **双数据源** | 统一抽象文件（`luat_fs_f*`）和内存数组（`memcpy`）两种数据源 |
| **文件列表播放** | `file_info[]` 数组支持连续播放多个文件，`fail_continue` 控制失败是否跳过 |
| **FIFO 水位控制** | 低水位触发数据请求、高水位停止解码，兼顾实时性和 DMA 缓冲深度 |
| **驱动状态机** | IDLE → INITED → ACTIVE → RUNNING 四级状态，确保各阶段资源正确管理 |
| **播放结束检测** | 文件尾+FIFO 空后连续 3 次请求空白数据才判定结束（防止缓冲数据未播完）|

---

## 十、文件 API 汇总

### 头文件 API 导出

| 文件 | 导出函数数 | 主要函数 |
|------|-----------|---------|
| `luat_audio_core.h` | 4 | `base_init`, `debug_switch`, `driver_register`, `driver_probe`, `driver_set_default`, `get_play_info_from_file`, `driver_event_callback` |
| `luat_audio_driver.h` | 11 | `config_pa_power`, `config_codec_power`, `config_private_param`, `config_audio_common_param`, `change_sample_rate`, `start`, `pa_power_off`, `codec_power_off`, `stop`, `deactivate`, `fill_default` |
| `luat_audio_data_codec.h` | 8 | `register`, `bind`, `init`, `deinit`, `unbind`, `decode_once`, `encode_once`, `find` |
| `luat_audio_channel.h` | 5 | `create_fifo`, `destroy_fifo`, `play`, `record`, `write_data` |
| `luat_audio_request.h` | 10 | `play_files`, `play_tts`, `play_stream`, `record`(⚠未实现), `speech`(⚠未实现), `prepare`, `cancel`, `init`, `deinit`, `start` |

总 API 数量：约 **41** 个公开函数（其中 2 个声明但未实现）。

### 内部函数（`luat_audio_core.c` static）

| 函数 | 功能 |
|------|------|
| `_audio_play_next_block` | 中断上下文：从 FIFO 读下一 block 到 DMA 缓冲 |
| `_audio_find_next_request_block` | 从请求链表取最高优先级块 |
| `_audio_add_request` | 按优先级降序插入请求到链表 |
| `_audio_tts_output_callback` | TTS 解码输出回调，写入通道 FIFO |
| `_audio_data_read_to_fifo` | 文件/ROM → 编码数据 FIFO（循环读取）|
| `_audio_data_read_to_buffer` | 文件/ROM → 固定缓冲区 |
| `_audio_data_seek` | 文件/ROM 定位（SEEK_SET/CUR/END）|
| `_audio_decode_current_request_play_info` | 自动搜索并初始化匹配编解码器 |
| `_audio_decode_file_start` | 文件解码初始化（创建 FIFO/buffer）|
| `_audio_decode_file_to_fifo` | 文件解码主循环：读取+解码+写入 FIFO |
| `_audio_decode_stream_to_fifo` | 流解码：从 FIFO 解码到播放 FIFO |
| `_audio_start_request` | 启动请求（驱动启动/回调通知/TTS 事件发送）|
| `_audio_request_finish` | 请求完成处理（释放资源+回调+排队处理）|

---

## 十一、编解码器适配层参数一览

| 编解码器 | 类型 | 输入最小长度 | 输出最大长度 | 自动检测 | 编码 |
|---------|------|------------|------------|---------|------|
| RAW | 0 | 4096 | 4096 | ❌ | ✅ |
| WAV | 1 | 4096 | 4096 | ✅ | ✅ |
| AMR-NB | 2 | 0（变长）| 320 | ✅ | ✅ |
| AMR-WB | 3 | 0（变长）| 640 | ✅ | ✅ |
| TTS | 4 | - | - | - | - |
| MP3 | 5 | 1792 | 4608 | ✅ | ❌ |
| OPUS | 6 | - | - | - | - |
| G711 | 7 | - | - | - | - |

注：OPUS 和 G711 的适配代码当前被 `#if 0` 注释，未处于激活状态。

---

## 十二、`exaudio.lua` 扩展库

`exaudio.lua` 是基于 `audio_v2` C API 的纯 Lua 扩展层，提供更高级的功能封装：

| 函数 | 功能 |
|------|------|
| `exaudio.setup(param)` | 初始化音频硬件（支持 es8311/tm8211/dac 三种模型）|
| `exaudio.play_start(configs, priority, cbfnc)` | 多优先级队列播放（文件/TTS/流）|
| `exaudio.play_stop()` | 停止播放 |
| `exaudio.play_stream_write(data)` | 流式写入数据（写入队列，由 audio.MORE_DATA 事件驱动）|
| `exaudio.record_start(format, time, path_or_cb, cbfnc)` | 录音启动 |
| `exaudio.record_stop()` | 停止录音 |
| `exaudio.vol(vol)` | 设置音量 |
| `exaudio.pm(mode)` | 设置电源管理模式 |

**核心特性**：
- **优先级队列**：`play_start` 支持优先级参数，高优先级请求可打断低优先级
- **多文件一致性检查**：连续播放多个文件时，自动检查采样率/声道数/位深一致性
- **流式数据队列**：`play_stream_write` 写入队列，由 `audio.MORE_DATA` 事件逐一消费
- **自动电源管理**：play_start / record_start 自动 RESUME，播放/录音完成自动 SHUTDOWN

---

## 十三、调试与诊断

- 全局调试标志 `luat_audio_debug_flag`（默认为 1），通过 `luat_audio_debug_switch()` 控制
- 各模块使用 `LLOGC(luat_audio_debug_flag, ...)` 条件编译日志
- 关键日志标签：
  | 标签 | 模块 |
  |------|------|
  | `audio_core` | 核心调度层 |
  | `audio_drv` | 驱动层 |
  | `audio_ch` | 通道层 |
  | `audio_codec` | 编解码器层 |
  | `luat_wav` | WAV 编解码器 |
  | `luat_mp3` | MP3 编解码器 |
  | `luat_amr` | AMR 编解码器 |
  | `codec_opus` | OPUS 编解码器 |

---

## 十四、audio_v2 Lua API 文档（`luat_lib_audio.c`）

`audio_v2` 是 LuatOS 新一代音频框架的 Lua C 绑定层，提供了完整的音频播放、流式音频、TTS、事件回调、驱动管理等功能的 Lua 接口。使用前需确保固件启用了 `LUAT_USE_AUDIO_V2`。

### 14.1 请求类 API

#### `audio_v2.play(path, err_stop, priority, driver_probe_id, codec_id)`

播放一个或多个音频文件。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | string/table | 文件名或文件路径数组。如果是 table，表示连续播放多个文件 |
| `err_stop` | boolean | 可选。是否在文件解码失败后停止解码，仅在连续播放多文件时有效。默认 `true`，遇到解码错误自动停止 |
| `priority` | int | 可选。优先级（0~255），值越大优先级越高。默认 0 |
| `driver_probe_id` | int | 可选。驱动 ID，不使用默认驱动时填写。需通过 `audio_v2.make_probe_id` 合成。绝大部分情况不需要填写 |
| `codec_id` | int | 可选。解码器 ID，需要指定解码器时填写。见 `DATA_CODEC_TYPE_*` 常量，绝大部分情况不需要填写（自动识别）。`stream` 模式此参数为必填 |

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| 成功标志 | boolean | 成功返回 `true`，否则返回 `false` |
| request_index | int | 请求索引，用于停止、暂停等后续操作，也可在回调中区分请求 |

**示例**：

```lua
-- 播放单个文件
local ok, req_id = audio_v2.play("/music.mp3")

-- 连续播放多个文件，解码错误时跳过继续播放下一个
local ok, req_id = audio_v2.play({"/music1.mp3", "/music2.amr", "/music3.wav"}, false)

-- 播放单个文件，高优先级
local ok, req_id = audio_v2.play("/alarm.wav", true, 200)

-- 指定解码器（跳过自动识别，直接使用 MP3 解码器）
local ok, req_id = audio_v2.play("/music.mp3", true, 0, nil, audio_v2.DATA_CODEC_TYPE_MP3)
```

---

#### `audio_v2.tts(text, priority, driver_probe_id)`

播放 TTS 文本转语音。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `text` | string/zbuff | 需要播放的文本内容 |
| `priority` | int | 可选。优先级（0~255），值越大优先级越高。默认 0 |
| `driver_probe_id` | int | 可选。驱动 ID，不使用默认驱动时填写。需通过 `audio_v2.make_probe_id` 合成 |

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| 成功标志 | boolean | 成功返回 `true`，否则返回 `false` |
| request_index | int | 请求索引，用于停止、暂停等后续操作 |

**示例**：

```lua
-- 播放 TTS
local ok, req_id = audio_v2.tts("当前温度25摄氏度")

-- 高优先级 TTS 可打断低优先级播放
local ok, req_id = audio_v2.tts("告警！温度过高！", 200)

-- 使用 zbuff 作为 TTS 输入
local buff = zbuff.create(1024)
buff:write("Hello World")
local ok, req_id = audio_v2.tts(buff)
```

---

#### `audio_v2.stream(codec_id, sample_rate, data_bits, channel_nums, is_signed, priority, driver_probe_id)`

流模式播放。与 `play` 不同，它不读取文件，而是由应用层通过回调事件主动推送音频数据到解码器内部 FIFO。适用于实时音频流（如网络音频、实时 PCM 采集播放、音频编辑等）。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `codec_id` | int | 解码器 ID，**必填**。指定使用的解码器类型，见 `DATA_CODEC_TYPE_*` 常量。常用 `audio_v2.DATA_CODEC_TYPE_RAW` 直接播放裸 PCM 数据 |
| `sample_rate` | int | **必填**。采样率（Hz），例如 8000, 16000, 44100, 48000 |
| `data_bits` | int | **必填**。数据位数，支持 8, 16, 24, 32 |
| `channel_nums` | int | **必填**。声道数，1=Mono，2=Stereo |
| `is_signed` | boolean | 可选。数据是否有符号，默认 `true`（有符号 PCM）。8bit 数据通常为 `false`（无符号） |
| `priority` | int | 可选。优先级（0~255），值越大优先级越高。默认 0 |
| `driver_probe_id` | int | 可选。驱动 ID，不使用默认驱动时填写。需通过 `audio_v2.make_probe_id` 合成 |

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| 成功标志 | boolean | 成功返回 `true`，否则返回 `false` |
| request_index | int | 请求索引，用于停止、暂停等后续操作，也可在回调中区分请求 |

**数据推送方式**：

流模式启动后，框架通过 `audio_v2.REQUEST_NEED_NEW_DATA` 事件通知应用层需要更多数据。应用层需在回调中将数据写入请求块对应的 `org_input_data_fifo`（通过 `zbuff` 或其他方式）。当解码器处理完数据后，会再次触发 `REQUEST_NEED_NEW_DATA` 事件，循环直到用户主动停 止或调用 `audio_v2.stop()`。

**示例**：

```lua
-- 启动 16000Hz, 16bit, 2ch 的有符号 PCM 流播放
local ok, req_id = audio_v2.stream(audio_v2.DATA_CODEC_TYPE_RAW, 16000, 16, 2, true)

-- 在回调中推数据
audio_v2.on(function(request_index, event, param)
    if request_index == req_id and event == audio_v2.REQUEST_NEED_NEW_DATA then
        -- 应用层自行将 PCM 数据写入 zbuff，再写入 org_input_data_fifo
        -- 实际应用中，可在 zbuff 准备好后调用底层写入接口
    elseif event == audio_v2.REQUEST_END then
        log.info("stream playback finished")
    end
end)
```

**注意**：
- `stream` 模式**必须**指定 `codec_id`，不会自动识别解码器
- 流模式不会自动结束，需要应用层在数据发送完毕后调用 `audio_v2.stop()` 停止播放
- RAW 编解码器（`DATA_CODEC_TYPE_RAW`）不做任何解码，数据直通到音频通道，适合预先处理好的 PCM 数据

---

#### `audio_v2.input(request_index, data, is_end)`

向流模式请求的输入 FIFO 推送音频数据。与 `stream` 搭配使用，在 `REQUEST_NEED_NEW_DATA` 回调中调用此函数将数据喂给解码器。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `request_index` | int | 请求索引，由 `audio_v2.stream` 返回 |
| `data` | string/zbuff | 要推送的音频数据。支持 Lua string 或 zbuff 对象 |
| `is_end` | boolean | 可选。是否为最后一帧数据。`true` 表示数据发送完毕，解码器处理完剩余数据后将结束播放。默认 `false` |

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| 成功标志 | boolean | 成功返回 `true`，否则返回 `false`（请求不存在或未处于 busy 状态）|
| write_len | int | 实际写入的字节数。FIFO 空间不足时可能小于传入数据长度 |
| free_len | int | 输入 FIFO 剩余可用空间（字节）|

**示例**：

```lua
-- 启动流播放
local ok, req_id = audio_v2.stream(audio_v2.DATA_CODEC_TYPE_RAW, 16000, 16, 2, true)

-- 在回调中写入数据
audio_v2.on(function(request_index, event, param)
    if request_index == req_id and event == audio_v2.REQUEST_NEED_NEW_DATA then
        -- 从网络或其他来源获取音频数据写入 zbuff
        local ok, written, free = audio_v2.input(req_id, zbuff_data)
        log.info("input result", ok, written, free)
    elseif event == audio_v2.REQUEST_END then
        log.info("stream end")
    end
end)

-- 发送最后一帧数据，通知解码结束
audio_v2.input(req_id, last_data, true)
```

**注意**：
- 必须在 `stream` 返回的 `request_index` 有效且请求处于 busy 状态时调用
- 写入的数据量受 `org_input_data_fifo` 剩余空间限制（默认 16KB），超出部分将被截断
- 使用 zbuff 传入时，写入成功后 zbuff 的 `used` 指针会自动前移（消耗已写数据）
- 设置 `is_end = true` 后，解码器消费完 FIFO 中所有数据后会结束播放并触发 `REQUEST_END`

---

#### `audio_v2.stop(request_index)`

停止正在播放的请求。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `request_index` | int | 请求索引，由 `audio_v2.play`、`audio_v2.stream` 或 `audio_v2.tts` 返回 |

**返回值**：无

**示例**：

```lua
local ok, req_id = audio_v2.play("/music.mp3")
-- 稍后停止
audio_v2.stop(req_id)
```

---

#### `audio_v2.pause(request_index, pause)`

暂停或恢复音频通道播放。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `request_index` | int | 请求索引，由 `audio_v2.play`、`audio_v2.stream` 或 `audio_v2.tts` 返回 |
| `pause` | boolean | 可选。`true` 暂停，`false`/nil 恢复。默认 `false` |

**返回值**：无

**示例**：

```lua
-- 暂停
audio_v2.pause(req_id, true)

-- 恢复播放
audio_v2.pause(req_id, false)
```

---

#### `audio_v2.is_all_done()`

判断所有音频请求是否处理完成。常用于轮询等待所有播放任务结束。

**参数**：无

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| all_done | boolean | `true` 表示所有请求已处理完成，`false` 表示仍有请求正在处理 |

**示例**：

```lua
-- 启动多个文件播放后等待全部完成
audio_v2.play({"/intro.mp3", "/content.amr", "/outro.wav"})

while not audio_v2.is_all_done() do
    sys.wait(100)
end
log.info("所有音频播放完成")
```

**注意**：
- 此函数仅检查请求链表是否为空，判断依据是 `request_busy_list` 是否为空
- 适用于简单场景，复杂场景建议在 `audio_v2.on` 回调中通过 `REQUEST_END` 事件精确判断
- 存在竞态可能：两次调用之间可能有新请求加入，建议结合回调使用

---

#### `audio_v2.get_play_info(data, codec_id, pos)`

从原始编码数据中解析音频播放信息（采样率、位宽、声道数等）。可用于在播放前预检音频文件属性，或手动解析编码数据的音频参数。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `data` | string/zbuff | 输入编码数据，至少包含文件头部数据 |
| `codec_id` | int | 解码器 ID，**必填**。指定使用的解码器类型，见 `DATA_CODEC_TYPE_*` 常量 |
| `pos` | int | 当前输入数据在整个文件中的偏移位置（字节），通常为 0 |

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| no_error | boolean | `true` 表示无错误。还需检查后续 sample_rate 是否非 0，非 0 才表示成功获取信息 |
| jump_offset | int | 需要跳转到的音频数据起始位置（字节）。解析到有效信息后应 seek 到此位置 |
| need_len | int | 需要获取的数据长度。若本次未解析到有效信息但未返回错误，说明数据不足，需读取更多数据后重试 |
| sample_rate | int | 采样率（Hz）。为 0 表示未获取到有效信息 |
| data_bits | int | 数据位数（8/16/24/32）|
| channel_nums | int | 声道数（1=Mono，2=Stereo）|
| is_signed | boolean | 数据是否有符号 |

**示例**：

```lua
-- 从文件头解析 WAV 音频信息
local fp = io.open("/music.wav", "rb")
if fp then
    local head = fp:read(1024)  -- 读取头部数据
    local ok, jump, need, rate, bits, ch, sig = audio_v2.get_play_info(head, audio_v2.DATA_CODEC_TYPE_WAV, 0)
    if ok and rate > 0 then
        log.info("WAV info", rate, bits, ch, sig)
    end
    fp:close()
end

-- 从 zbuff 解析 MP3 信息
local buff = zbuff.create(4096)
-- ... 填充 zbuff 数据 ...
local ok, jump, need, rate, bits, ch, sig = audio_v2.get_play_info(buff, audio_v2.DATA_CODEC_TYPE_MP3, 0)
```

**注意**：
- 此函数仅为信息查询，不启动播放
- `sample_rate` 为 0 表示数据长度不足以完成解析，需读取更多数据后重试
- 并非所有编解码器都支持 `get_play_info`（如 RAW 编解码器不支持）

---

#### `audio_v2.record()` — ⚠️ 待实现

录音功能。当前版本暂未实现，声明为框架预留接口。

#### `audio_v2.speech()` — ⚠️ 待实现

通话（对讲）功能。当前版本暂未实现，声明为框架预留接口。

---

### 14.2 事件回调 API

#### `audio_v2.on(func)`

注册音频事件回调函数。最多同时支持 10 个请求（`LUAT_AUDIO_REQUEST_MAX`）。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `func` | function | 回调函数，接收三个参数 |

**回调函数签名**：

```lua
function(request_index, event, param)
```

| 回调参数 | 类型 | 说明 |
|---------|------|------|
| `request_index` | int | 请求索引，标识是哪个请求触发的回调 |
| `event` | int | 事件类型，见 `REQUEST_*` 常量 |
| `param` | int | 附加参数，依赖具体事件类型 |

**事件-参数对应表**：

| 事件常量 | 值 | 触发时机 | param |
|---------|-----|---------|-------|
| `audio_v2.REQUEST_START` | 0 | 开始处理请求 | 无意义 |
| `audio_v2.REQUEST_NEED_NEW_DATA` | 1 | 播放需要更多数据（流模式） | 无意义 |
| `audio_v2.REQUEST_GET_NEW_DATA` | 2 | 获取到新录音数据 | zbuff 序号（录音专用）|
| `audio_v2.REQUEST_DECODE_DONE` | 3 | 请求解码完成（预留） | 无意义 |
| `audio_v2.REQUEST_END` | 4 | 请求块处理完成（正常/出错/停止） | 无意义 |

**示例**：

```lua
audio_v2.on(function(request_index, event, param)
    if event == audio_v2.REQUEST_START then
        log.info("audio", "请求", request_index, "开始播放")
    elseif event == audio_v2.REQUEST_END then
        log.info("audio", "请求", request_index, "播放结束")
    elseif event == audio_v2.REQUEST_NEED_NEW_DATA then
        log.info("audio", "请求", request_index, "需要更多数据")
    elseif event == audio_v2.REQUEST_GET_NEW_DATA then
        log.info("audio", "请求", request_index, "获取到新录音数据, zbuff序号:", param)
    end
end)
```

**注意**：
- 多次调用 `audio_v2.on()` 会覆盖之前的回调
- 传入 `nil` 可清除回调

---

#### `audio_v2.debug(on_off)`

开启或关闭音频调试信息输出。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `on_off` | boolean | `true` 开启调试信息，`false` 关闭 |

**示例**：

```lua
audio_v2.debug(true)   -- 开启调试
audio_v2.debug(false)  -- 关闭调试
```

---

### 14.3 驱动管理 API

#### `audio_v2.make_probe_id(tx_bus_type, tx_bus_id, rx_bus_type, rx_bus_id)`

合成音频驱动 ID。驱动 ID 用于在多驱动场景下指定使用哪个硬件接口。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `tx_bus_type` | int | 发送（播放）总线类型，见 `DRIVER_TYPE_*` 常量。默认 `DRIVER_TYPE_NONE` |
| `tx_bus_id` | int | 发送总线 ID（编号）。默认 0 |
| `rx_bus_type` | int | 接收（录音）总线类型，见 `DRIVER_TYPE_*` 常量。默认 `DRIVER_TYPE_NONE` |
| `rx_bus_id` | int | 接收总线 ID（编号）。默认 0 |

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| probe_id | int | 驱动 ID，可用于其他 API 的 `driver_probe_id` 参数 |

**示例**：

```lua
-- I2S0 全双工（同时播放和录音）
local pid = audio_v2.make_probe_id(audio_v2.DRIVER_TYPE_I2S, 0,
                                   audio_v2.DRIVER_TYPE_I2S, 0)

-- DAC0 单工（仅播放）
local pid = audio_v2.make_probe_id(audio_v2.DRIVER_TYPE_DAC, 0,
                                   audio_v2.DRIVER_TYPE_NONE, 0)

-- USB 音频播放
local pid = audio_v2.make_probe_id(audio_v2.DRIVER_TYPE_USB, 0,
                                   audio_v2.DRIVER_TYPE_NONE, 0)
```

---

#### `audio_v2.set_default_driver(driver_probe_id)`

设置默认音频驱动。后续不指定 `driver_probe_id` 的请求将使用此驱动。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `driver_probe_id` | int | 驱动 ID，需通过 `audio_v2.make_probe_id` 合成 |

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| 成功标志 | boolean | 成功返回 `true`，否则返回 `false` |

**示例**：

```lua
-- 设置 I2S0 为默认驱动
local pid = audio_v2.make_probe_id(audio_v2.DRIVER_TYPE_I2S, 0,
                                   audio_v2.DRIVER_TYPE_I2S, 0)
audio_v2.set_default_driver(pid)

-- 设置 DAC0 为默认驱动（仅播放）
local pid = audio_v2.make_probe_id(audio_v2.DRIVER_TYPE_DAC, 0,
                                   audio_v2.DRIVER_TYPE_NONE, 0)
audio_v2.set_default_driver(pid)
```

---

#### `audio_v2.get_driver_info()`

获取系统中已注册的音频驱动数量和默认驱动索引。

**参数**：无

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| all_nums | int | 所有已注册的音频驱动数量 |
| default_driver_index | int | 默认音频驱动索引（从 0 开始）|

**示例**：

```lua
local all_nums, default_index = audio_v2.get_driver_info()
log.info("驱动总数:", all_nums, "默认驱动索引:", default_index)
```

---

#### `audio_v2.get_driver_id(index)`

根据驱动索引获取驱动 ID。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `index` | int | 驱动索引（从 0 开始）。默认 0 |

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| probe_id | int | 驱动 ID，可通过 `audio_v2.print_probe_id` 分解查看详情 |

**示例**：

```lua
-- 获取默认驱动的 ID
local all_nums, default_index = audio_v2.get_driver_info()
local driver_id = audio_v2.get_driver_id(default_index)
log.info("默认驱动ID:", driver_id)
```

---

#### `audio_v2.print_probe_id(driver_probe_id, is_string)`

分解驱动 ID 并返回总线类型和 ID 的详细信息。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `driver_probe_id` | int | 驱动 ID，需通过 `audio_v2.make_probe_id` 合成 |
| `is_string` | boolean | `true` 返回字符串形式名称，`false`/nil 返回数值常量。默认 `false` |

**返回值**（`is_string = true`）：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| tx_bus_type | string | 发送总线类型名称，如 `"I2S"`, `"DAC"`, `"ADC"`, `"USB"`, `"NONE"` |
| tx_bus_id | int | 发送总线 ID |
| rx_bus_type | string | 接收总线类型名称 |
| rx_bus_id | int | 接收总线 ID |

**返回值**（`is_string = false`）：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| tx_bus_type | int | 发送总线类型常量值 |
| tx_bus_id | int | 发送总线 ID |
| rx_bus_type | int | 接收总线类型常量值 |
| rx_bus_id | int | 接收总线 ID |

**示例**：

```lua
-- 字符串形式
local pid = audio_v2.make_probe_id(audio_v2.DRIVER_TYPE_I2S, 0,
                                   audio_v2.DRIVER_TYPE_I2S, 0)
local tx_type, tx_id, rx_type, rx_id = audio_v2.print_probe_id(pid, true)
log.info(tx_type, tx_id, rx_type, rx_id)  -- 输出: I2S  0  I2S  0

-- 数值形式
local tx_type, tx_id, rx_type, rx_id = audio_v2.print_probe_id(pid, false)
```

---

#### `audio_v2.config(config_param, config_value1, config_value2, driver_probe_id)`

配置音频驱动的私有参数。用于设置 I2S 模式、帧位宽、声道数等硬件接口参数。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `config_param` | int | 驱动私有参数索引，见 `CFG_PARAM_*` 常量 |
| `config_value1` | int | 参数值 1，见 `CFG_VALUE_*` 常量或直接填写数值 |
| `config_value2` | int | 可选。参数值 2，通常情况下只需 1 个参数，无需填写 |
| `driver_probe_id` | int | 可选。驱动 ID，不使用默认驱动时填写，详见 `make_probe_id` |

**可配置参数一览**：

| 参数常量 | 值 | 说明 | value1 取值 |
|---------|-----|------|-------------|
| `CFG_PARAM_I2S_MODE` | 0 | I2S 通信模式 | `CFG_VALUE_I2S_MODE_I2S`(0) / `LSB`(1) / `MSB`(2) / `PCMS`(3) / `PCML`(4) |
| `CFG_PARAM_I2S_FRAME_BITS` | 1 | I2S 帧位宽，需与外部 CODEC 匹配 | 16 / 24 / 32 等 |
| `CFG_PARAM_I2S_CHANNEL_NUMS` | 2 | I2S 通道数，需与外部 CODEC 匹配 | 1=Mono, 2=Stereo |
| `CFG_PARAM_DAC_BIT_WIDTH` | 3 | DAC 位宽 | 8 / 16 / 24 / 32 |

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| 成功标志 | boolean | 成功返回 `true`，否则返回 `false`（驱动未找到或驱动不支持该参数）|

**示例**：

```lua
-- 配置 I2S0：标准 I2S 模式，16bit 帧位宽，单声道
audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE, audio_v2.CFG_VALUE_I2S_MODE_I2S)
audio_v2.config(audio_v2.CFG_PARAM_I2S_FRAME_BITS, 16)
audio_v2.config(audio_v2.CFG_PARAM_I2S_CHANNEL_NUMS, 1)

-- 配置 DAC0：16bit 位宽
audio_v2.config(audio_v2.CFG_PARAM_DAC_BIT_WIDTH, 16)

-- 对指定驱动配置
local pid = audio_v2.make_probe_id(audio_v2.DRIVER_TYPE_I2S, 0,
                                   audio_v2.DRIVER_TYPE_I2S, 0)
audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE, audio_v2.CFG_VALUE_I2S_MODE_MSB, nil, pid)
```

**注意**：
- 采样率和数据位宽是通用参数，在 `audio_v2.stream()` 中通过 `sample_rate / data_bits` 参数设置，不能通过此 API 配置
- 不同驱动支持的可配置参数不同，具体取决于驱动实现
- 应在 `play` / `stream` / `tts` 之前完成配置，播放过程中修改可能无效

---

#### `audio_v2.soft_volume(volume, driver_probe_id)`

设置软件音量增益。通过软件算法调整音频输出音量，适用于需要额外音量放大或减小的场景。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `volume` | int | 软件音量增益值（0~1000），值越大音量越高。默认 100（原始音量），1000 表示 10 倍增益 |
| `driver_probe_id` | int | 可选。驱动 ID，不使用默认驱动时填写，详见 `make_probe_id` |

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| 成功标志 | boolean | 成功返回 `true`，否则返回 `false`（驱动未找到时也返回 `false`）|

**示例**：

```lua
-- 设置为原始音量的 75%
audio_v2.soft_volume(75)

-- 设置为 2 倍增益
audio_v2.soft_volume(200)

-- 对指定驱动设置增益
audio_v2.soft_volume(150, driver_probe_id)
```

**注意**：
- 软件增益通过通道层的 `luat_audio_channel_set_soft_volume` 实现，在 PCM 数据写入 FIFO 前进行幅度缩放
- 过高的增益可能导致音频削波失真，建议根据实际音频动态范围酌情设置
- 值 100 表示原始音量（1.0x），50 表示 -6dB（0.5x），200 表示 +6dB（2.0x）

---

### 14.4 电源管理 API

#### `audio_v2.config_pa_power_ctrl(pa_power_ctrl_enable, pa_power_pin, pa_power_on_level, pa_power_on_delay_time_ms, driver_probe_id)`

配置音频驱动的 PA（功放）电源控制参数。用于防爆破音管理。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `pa_power_ctrl_enable` | boolean | 是否使能 PA 电源控制 |
| `pa_power_pin` | int | PA 电源控制 GPIO 引脚编号 |
| `pa_power_on_level` | int | PA 电源使能电平，1=高电平使能，0=低电平使能 |
| `pa_power_on_delay_time_ms` | int | 可选。PA 电源开启延时时间（毫秒），默认 100ms |
| `driver_probe_id` | int | 可选。驱动 ID，不使用默认驱动时填写，详见 `make_probe_id` |

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| 成功标志 | boolean | 成功返回 `true`，否则返回 `false` |

**示例**：

```lua
-- 配置 PA 控制：GPIO12，高电平使能，延时 100ms
audio_v2.config_pa_power_ctrl(true, 12, 1, 100)
```

---

#### `audio_v2.config_codec_power_ctrl(codec_power_ctrl_enable, codec_power_pin, codec_power_on_level, codec_ready_after_wakeup_time_ms, codec_power_off_delay_time_ms, driver_probe_id)`

配置音频驱动的 CODEC 电源控制参数。用于防爆破音和电源管理。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `codec_power_ctrl_enable` | boolean | 是否使能 CODEC 电源控制 |
| `codec_power_pin` | int | CODEC 电源控制 GPIO 引脚编号 |
| `codec_power_on_level` | int | CODEC 电源使能电平，1=高电平使能，0=低电平使能 |
| `codec_ready_after_wakeup_time_ms` | int | 可选。CODEC 上电后等待稳定的时间（毫秒），默认 200ms |
| `codec_power_off_delay_time_ms` | int | 可选。CODEC 下电延时时间（毫秒），默认 10ms |
| `driver_probe_id` | int | 可选。驱动 ID，不使用默认驱动时填写，详见 `make_probe_id` |

**返回值**：

| 返回值 | 类型 | 说明 |
|--------|------|------|
| 成功标志 | boolean | 成功返回 `true`，否则返回 `false` |

**示例**：

```lua
-- 配置 CODEC 控制：GPIO11，高电平使能，上电等待 200ms，下电延时 10ms
audio_v2.config_codec_power_ctrl(true, 11, 1, 200, 10)
```

---

#### `audio_v2.shutdown(driver_power_off, codec_power_off, pa_power_off, driver_probe_id)`

关闭音频驱动及相关外设电源。用于系统休眠或音频模块卸载前做完整的下电清理。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `driver_power_off` | boolean | 是否关闭驱动。`true` 会调用 `stop` + `deactivate` 停止驱动并释放资源 |
| `codec_power_off` | boolean | 是否关闭外部 CODEC 电源（需事先通过 `config_codec_power_ctrl` 配置引脚）|
| `pa_power_off` | boolean | 是否关闭 PA 功放电源（需事先通过 `config_pa_power_ctrl` 配置引脚）|
| `driver_probe_id` | int | 可选。驱动 ID，不使用默认驱动时填写，详见 `make_probe_id` |

**返回值**：无

**执行顺序**（按参数依次执行）：

1. `pa_power_off` — 先关闭 PA 功放电源（防爆破音）
2. `codec_power_off` — 再关闭 CODEC 电源
3. `driver_power_off` — 最后停止驱动（DMA/DMA 中断）并反激活

**示例**：

```lua
-- 完整下电：关闭 PA → 关闭 CODEC → 停止驱动
audio_v2.shutdown(true, true, true)

-- 仅关闭 PA，保持驱动和 CODEC 运行
audio_v2.shutdown(false, false, true)

-- 对指定驱动执行下电
local pid = audio_v2.make_probe_id(audio_v2.DRIVER_TYPE_I2S, 0,
                                   audio_v2.DRIVER_TYPE_I2S, 0)
audio_v2.shutdown(true, true, true, pid)
```

**注意**：
- 关闭驱动后（`driver_power_off = true`），需要调用 `audio_v2.play`、`audio_v2.stream` 或 `audio_v2.tts` 重新启动驱动
- 建议在系统进入低功耗模式前调用此函数
- 电源关闭时序与 `config_pa_power_ctrl` / `config_codec_power_ctrl` 中配置的电源引脚和电平相关

---

### 14.5 常量定义

#### 请求事件常量（用于 `audio_v2.on` 回调）

| 常量名 | 值 | 说明 |
|--------|-----|------|
| `audio_v2.REQUEST_START` | 0 | 开始处理请求 |
| `audio_v2.REQUEST_NEED_NEW_DATA` | 1 | 需要新的播放数据（流模式）|
| `audio_v2.REQUEST_GET_NEW_DATA` | 2 | 获取到新录音数据 |
| `audio_v2.REQUEST_DECODE_DONE` | 3 | 解码完成（预留）|
| `audio_v2.REQUEST_END` | 4 | 请求处理完成 |

#### 驱动总线类型常量（用于 `make_probe_id` / `print_probe_id`）

| 常量名 | 值 | 说明 |
|--------|-----|------|
| `audio_v2.DRIVER_TYPE_NONE` | 0 | 无（单工时接收或发送设为 NONE）|
| `audio_v2.DRIVER_TYPE_I2S` | 1 | I2S 数字音频接口 |
| `audio_v2.DRIVER_TYPE_DAC` | 2 | DAC 模拟输出 |
| `audio_v2.DRIVER_TYPE_ADC` | 3 | ADC 模拟输入 |
| `audio_v2.DRIVER_TYPE_USB` | 4 | USB 音频声卡 |

#### 编解码器类型常量（用于 `play` 的 `codec_id`，以及 `stream` 的 `codec_id`）

| 常量名 | 值 | 说明 |
|--------|-----|------|
| `audio_v2.DATA_CODEC_TYPE_RAW` | 0 | RAW 编解码器（PCM 直通，不解码）|
| `audio_v2.DATA_CODEC_TYPE_WAV` | 1 | WAV 编解码器（PCM 直通）|
| `audio_v2.DATA_CODEC_TYPE_AMR_NB` | 2 | AMR-NB 编解码器（8kHz）|
| `audio_v2.DATA_CODEC_TYPE_AMR_WB` | 3 | AMR-WB 编解码器（16kHz）|
| `audio_v2.DATA_CODEC_TYPE_TTS` | 4 | TTS 文本转语音 |
| `audio_v2.DATA_CODEC_TYPE_MP3` | 5 | MP3 编解码器 |
| `audio_v2.DATA_CODEC_TYPE_OPUS` | 6 | OPUS 编解码器 |
| `audio_v2.DATA_CODEC_TYPE_G711` | 7 | G711 编解码器 |

#### 驱动私有参数常量（用于 `audio_v2.config` 的 `config_param`）

| 常量名 | 值 | 说明 |
|--------|-----|------|
| `audio_v2.CFG_PARAM_I2S_MODE` | 0 | I2S 通信模式 |
| `audio_v2.CFG_PARAM_I2S_FRAME_BITS` | 1 | I2S 帧位宽 |
| `audio_v2.CFG_PARAM_I2S_CHANNEL_NUMS` | 2 | I2S 通道数 |
| `audio_v2.CFG_PARAM_DAC_BIT_WIDTH` | 3 | DAC 位宽 |

#### I2S 模式取值常量（用于 `audio_v2.config` 的 `config_value1`，配合 `CFG_PARAM_I2S_MODE`）

| 常量名 | 值 | 说明 |
|--------|-----|------|
| `audio_v2.CFG_VALUE_I2S_MODE_I2S` | 0 | I2S 标准模式（飞利浦格式）|
| `audio_v2.CFG_VALUE_I2S_MODE_LSB` | 1 | LSB 格式（左对齐）|
| `audio_v2.CFG_VALUE_I2S_MODE_MSB` | 2 | MSB 格式（右对齐）|
| `audio_v2.CFG_VALUE_I2S_MODE_PCMS` | 3 | PCM 短帧格式 |
| `audio_v2.CFG_VALUE_I2S_MODE_PCML` | 4 | PCM 长帧格式 |

---

### 14.6 完整使用示例

#### 基础播放

```lua
-- 注册事件回调
audio_v2.on(function(req_id, event, param)
    if event == audio_v2.REQUEST_START then
        log.info("播放开始", req_id)
    elseif event == audio_v2.REQUEST_END then
        log.info("播放结束", req_id)
    end
end)

-- 播放单个文件
local ok, req_id = audio_v2.play("/music.mp3")
```

#### 多优先级播放

```lua
-- 低优先级背景音乐
audio_v2.play("/bgm.mp3", true, 10)

-- 高优先级告警（打断背景音乐）
audio_v2.tts("告警！", 200)

-- 当高优先级播放结束后，低优先级自动恢复
```

#### I2S 驱动初始化 + 全功能播放

```lua
-- 1. 配置 I2S 驱动私有参数（在 play 之前完成）
local pid = audio_v2.make_probe_id(audio_v2.DRIVER_TYPE_I2S, 0,
                                   audio_v2.DRIVER_TYPE_I2S, 0)
audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE, audio_v2.CFG_VALUE_I2S_MODE_I2S, nil, pid)
audio_v2.config(audio_v2.CFG_PARAM_I2S_FRAME_BITS, 16, nil, pid)
audio_v2.config(audio_v2.CFG_PARAM_I2S_CHANNEL_NUMS, 2, nil, pid)

-- 2. 配置电源管理
audio_v2.config_pa_power_ctrl(true, 12, 1, 100)
audio_v2.config_codec_power_ctrl(true, 11, 1, 200, 10)

-- 3. 设置软件音量（原始音量的 80%）
audio_v2.soft_volume(80)

-- 4. 注册回调
audio_v2.on(function(req_id, event, param)
    log.info("audio event", req_id, event, param)
end)

-- 5. 连续播放列表
local files = {"/intro.mp3", "/content.amr", "/outro.wav"}
local ok, req_id = audio_v2.play(files, false, 50)

-- 6. 等待播放完成（简单轮询方式）
while not audio_v2.is_all_done() do
    sys.wait(200)
end
log.info("所有文件播放完成")

-- 7. 关闭音频驱动（进入低功耗前）
audio_v2.shutdown(true, true, true)
```

#### 流模式播放

```lua
-- 注册事件回调
audio_v2.on(function(req_id, event, param)
    if event == audio_v2.REQUEST_START then
        log.info("stream start", req_id)
    elseif event == audio_v2.REQUEST_NEED_NEW_DATA then
        -- 在回调中通过 audio_v2.input() 推送 PCM 数据
        -- 例如从网络接收或实时生成的音频数据
        local ok, written, free = audio_v2.input(req_id, pcm_zbuff)
        if not ok then
            log.warn("input failed")
        end
    elseif event == audio_v2.REQUEST_END then
        log.info("stream end", req_id)
    end
end)

-- 启动 16bit 16kHz 单声道 PCM 流
local ok, req_id = audio_v2.stream(audio_v2.DATA_CODEC_TYPE_RAW, 16000, 16, 1, true, 0)

-- 数据发送完毕后，标记结束
audio_v2.input(req_id, last_data, true)
```

#### 驱动查询

```lua
-- 查询系统中注册了哪些音频驱动
local all_nums, default_index = audio_v2.get_driver_info()
log.info("音频驱动数量:", all_nums)

for i = 0, all_nums - 1 do
    local pid = audio_v2.get_driver_id(i)
    local tx_type, tx_id, rx_type, rx_id = audio_v2.print_probe_id(pid, true)
    log.info("驱动", i, ":", tx_type, tx_id, "↔", rx_type, rx_id)
end

-- 设置默认驱动为 DAC0
local dac_pid = audio_v2.make_probe_id(audio_v2.DRIVER_TYPE_DAC, 0,
                                       audio_v2.DRIVER_TYPE_NONE, 0)
audio_v2.set_default_driver(dac_pid)
```
