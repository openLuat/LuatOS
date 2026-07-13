# SIP-VoLTE 音频桥接测试 Demo

4G模组作为 SIP ↔ VoLTE 音频网关，实现 SIP 客户端与手机之间的通话桥接。

## 配置

| 参数 | 值 |
|------|-----|
| 4G模组 SIP 用户名 | 1903CFC1 |
| 远程 SIP 客户端 | 1903CFC0 |
| 目标手机号 | 13781142418 |
| SIP 服务器 | 180.152.6.34:8910 |

## 文件说明

```
bsp/pc/test/143.sip_bridge_demo/scripts/
├── sip_bridge_agent.lua    -- 核心桥接逻辑模块
├── main.lua                -- 入口脚本
├── audio_drv.lua           -- 音频驱动（ES8311初始化）
├── cc_stub_pc.lua          -- PC模拟器CC库Stub（仅PC测试用）
└── test_controller.py      -- UDP控制脚本（PC测试用）
```

## 功能说明

### 呼出场景：SIP客户端 → 4G模组 → 手机

```
1903CFC0 (SIP软电话)  ──INVITE──►  1903CFC1 (4G模组)
                                      │
                                      ├── exsip.accept() → 建立SIP通话
                                      │
                                      └── cc.dial(13781142418) → 拨打手机
                                      │
手机接听 ◄──VoLTE── 4G模组 ──RTP──► 1903CFC0 (SIP软电话)
```

触发方式：
1. **SIP INVITE**：1903CFC0 拨打 SIP 1903CFC1，4G模组自动接听后自动拨打手机
2. **SIP MESSAGE**：1903CFC0 发送 MESSAGE `{"cmd":"dial","number":"138..."}`，4G模组解析后拨打手机
3. **手动触发**：通过 UDP 命令 `dial` 或 `dial_sip`

### 呼入场景：手机 → 4G模组 → SIP客户端

```
手机 ──VoLTE──► 4G模组 (1903CFC1)
                   │
                   ├── 收到 INCOMINGCALL
                   │
                   ├── exsip.dial(1903CFC0) → 发起SIP呼叫
                   │
                   └── 1903CFC0 接听SIP → cc.accept(0) → 接听手机
                   │
手机 ◄──VoLTE── 4G模组 ──RTP──► 1903CFC0 (SIP软电话)
```

触发方式：
1. **自动处理**：手机来电时，4G模组自动拨打 SIP 1903CFC0
2. **手动触发**：通过 UDP 命令 `incoming` 模拟手机来电

### 音频桥接

4G模组通过底层 **voip 桥接模式** 实现 SIP 和 VoLTE 之间的音频传输：

- `voip` 模块运行在 **AUDIO_MODE_BRIDGE** 模式，不直接控制 I2S 硬件
- `cc` 库独占 I2S，负责手机端的麦克风采集和扬声器播放
- 底层固件在 `cc` 的音频回调中自动完成 PCM 数据的双向交换：
  - 手机 mic → `cc` → `voip_bridge_pcm_in()` → RTP → SIP 服务器
  - SIP 服务器 → RTP → `voip` → `voip_bridge_pcm_out()` → `cc` → 手机扬声器

- 4G模组可以通过 `local_audio` 参数控制是否打开本地麦克风和喇叭：
  - `local_audio = true`：本地可以听到/说话（音频混音，cc 侧有声音）
  - `local_audio = false`：本地静音，仅桥接两端音频

```lua
-- 在脚本中设置
sip_bridge_agent.set_local_audio(true)   -- 打开本地音频
sip_bridge_agent.set_local_audio(false)  -- 关闭本地音频（仅桥接）
```

底层通过 `exaudio.vol()` 和 `exaudio.mic_vol()` 实现：
- `true` → `exaudio.vol(35) + exaudio.mic_vol(96)`
- `false` → `exaudio.vol(0) + exaudio.mic_vol(0)`

> **重要**：本 Demo 依赖底层 `components/voip` 的桥接模式修改和 `components/cc` 的 PCM 交换回调。`voip` 在 `exsip.start()` 之前通过 `voip.setAudioMode(voip.AUDIO_MODE_BRIDGE)` 设置为桥接模式。Lua 层面不直接处理 PCM ↔ RTP 的编解码转换，由 C 层自动完成。

## 运行方法

### PC 模拟器（测试状态机）

```bash
cd bsp/pc
build\out\luatos-lua.exe test\143.sip_bridge_demo\scripts\ ..\..\script\libs\
```

> 注意：PC 模拟器无法测试实际 VoLTE 通话和音频桥接，仅验证 SIP 注册、状态机流转、事件处理逻辑。

启动后，在另一个终端窗口发送控制命令：

```bash
cd bsp/pc/test/143.sip_bridge_demo/scripts/

# 查看状态
python test_controller.py status

# 手动拨打手机（呼出测试）
python test_controller.py dial
python test_controller.py dial 13800138000

# 手动拨打 SIP（呼入测试）
python test_controller.py dial_sip

# 模拟手机来电
python test_controller.py incoming 13900139000

# 接听 SIP 来电
python test_controller.py answer

# 接听手机来电
python test_controller.py answer_mobile

# 挂断所有通话
python test_controller.py hangup

# 打开/关闭本地音频
python test_controller.py audio on
python test_controller.py audio off

# 显示帮助
python test_controller.py help
```

### 真机（Air8000）

1. 将脚本文件烧录到 4G模组
2. 确认 SIM 卡已插入，支持 VoLTE
3. 确认 SIP 服务器账号密码正确（在 `sip_bridge_agent.lua` 的 `CONFIG` 中修改）
4. 上电启动，等待 SIP 注册成功

## 状态机说明

### SIP 状态

```
idle ──► incoming（收到来电） ──► connected（接听/接通）
  │
  └──► dialing（主动拨打） ──► connected
       │
       └──► idle（失败/挂断）
```

### CC 状态

```
idle ──► ringing（手机来电） ──► connected（接听）
  │
  └──► dialing（主动拨打） ──► connected（接通）
       │
       └──► idle（失败/挂断）
```

### 通话状态判断

```lua
in_call = (sip_state == "sip_connected" and cc_state == "cc_connected")
```

只有当 SIP 和 CC 都 connected 时，才认为通话建立成功。

## 核心 API

```lua
local bridge = require("sip_bridge_agent")

-- 启动
bridge.start({
    sip_username = "1903CFC1",
    sip_password = "Air.903CFC1",
    target_phone_number = "13781142418",
    auto_answer_sip = true,        -- 自动接听 SIP 来电
    auto_handle_mobile_incoming = true,  -- 自动处理手机来电
})

-- 手动拨打手机
bridge.dial_phone("13781142418")

-- 手动拨打 SIP
bridge.dial_sip("sip:1903CFC0@180.152.6.34")

-- 手动接听 SIP
bridge.answer_sip()

-- 手动接听手机
bridge.answer_mobile()

-- 挂断所有通话
bridge.hangup_all()

-- 音频控制
bridge.set_local_audio(true)   -- 打开本地音频
bridge.set_local_audio(false)  -- 关闭本地音频（仅桥接）

-- 获取状态
local state = bridge.get_state()
-- state.sip_state      -- "sip_idle" | "sip_incoming" | "sip_dialing" | "sip_connected"
-- state.cc_state       -- "cc_idle" | "cc_ringing" | "cc_dialing" | "cc_connected"
-- state.in_call        -- true/false
-- state.call_direction -- "outgoing" | "incoming" | nil
-- state.local_audio    -- true/false
```

## 注意事项

1. **密码配置**：运行前请确认 `sip_bridge_agent.lua` 中 `CONFIG.sip_password` 与 SIP 服务器账号匹配
2. **PC 模拟器限制**：
   - 无法测试实际 VoLTE 通话
   - 无法测试实际音频桥接
   - 使用 `cc_stub_pc.lua` 模拟 CC 事件
3. **真机音频**：
   - 确认 ES8311 初始化成功（查看日志中的 `audio_drv` 输出）
   - 如果 TTS 无声，先排查硬件问题
4. **音频桥接依赖底层修改**：本 Demo 需要底层 `components/voip` 的桥接模式（`VOIP_AUDIO_MODE_BRIDGE`）和 `components/cc` 的 PCM 交换回调配合。如果 SIP 通话和 VoLTE 通话同时存在但无声音，请检查：
   - `sip_bridge_agent.lua` 中 `voip.setAudioMode(voip.AUDIO_MODE_BRIDGE)` 是否设置成功
   - `components/voip/src/luat_voip_core.c` 和 `components/cc/luat_lib_cc_v2.c` 是否已编译进固件
   - `luat_audio_core.c` 的 `SPEECH_WITH_BUFFER` 模式修复是否已生效

## 音频桥接问题排查记录

### 1. CC 音频通道重复启动

**现象**：`CC_EVENT_VOICE_START request speech success` 日志出现两次，`upload enable` 先为 0 再为 1，导致音频通道重复初始化，产生并行数据流和 FIFO 混乱。

**根因**：CP 侧的 `soc_mobile_speech_start()` 和 `_cc_data_input()` 都可能触发 `luat_cc_start_audio()`，两者调用时机不同但都会尝试启动音频通道。

**修复**：
- `luatos-soc-2024/interface/src/luat_audio_ec7xx.c`：
  - `soc_mobile_speech_start()` 增加 `_cc_upload_enable && _cc_input_buffer` 检查，已启动则直接返回
  - `_cc_data_input()` 增加 `_cc_download_enable` 检查，已启用则只更新 buffer 指针
- `components/cc/luat_lib_cc_v2.c`：
  - `luat_cc_start_audio()` 开头检查 `_l_cc.is_audio_start`，已为 1 则只更新状态并返回，不再调用 `luat_audio_request_speech()`

### 2. 桥接模式下 VoIP AEC/降噪干扰

**现象**：通话有声音但音质差，有大量刺啦刺啦的噪声，类似信号被错误处理。

**根因**：VoIP 引擎在 `VOIP_AUDIO_MODE_BRIDGE` 模式下仍启用了 Speex AEC（回声消除）和降噪。纯数字桥接不存在声学回声，AEC 和降噪错误处理 PCM 数据导致失真。

**修复**：
- `components/voip/src/luat_voip_core.c`：
  - `voip_session_start()` 中，在 `voip_aec_init()` 之前，若 `audio_mode == VOIP_AUDIO_MODE_BRIDGE`，强制设置 `config.aec_enable = 0` 和 `config.aec_denoise = 0`
  - 日志应输出 `Bridge mode: AEC disabled`

### 3. 采样率不匹配（16kHz CC vs 8kHz VoIP）

**现象**：通话有声音但音调严重失真，像 Mickey Mouse 声音（音调变高2倍），或完全听不懂的变音/电音。

**根因**：CP 的 VoLTE 使用 WB 模式（16kHz AMR-WB），但 SIP 服务器只协商了 8kHz PCMU。桥接接口没有做采样率转换：
- 下行（手机→SIP）：16kHz PCM 被直接送给 8kHz VoIP 编码 → 音调变高2倍
- 上行（SIP→手机）：8kHz PCM 被直接送给 16kHz CP 编码 → 音调变低2倍

**修复**：
- `components/cc/luat_lib_cc_v2.c`：
  - **上行重采样**（`luat_cc_bridge_get_uplink_pcm`）：当 CC=16kHz、VoIP=8kHz 时，从 VoIP 请求 `samples/2` 个 8kHz 样本，每个样本复制一次（简单插值）成 16kHz 320 样本
  - **下行重采样**（`_l_cc_audio_voice_request_callback` 的 `GET_NEW_DATA` 处理）：当 CC=16kHz、VoIP=8kHz 时，从 `play_save_fifo` 读取的 16kHz 数据，每2个样本取1个（`downsample_16k_to_8k`）下采样成 8kHz 160 样本，再传给 VoIP
  - 增加 `_downsample_16k_to_8k()` helper 函数，原地紧凑下采样

### 验证要点

刷写修复后的固件后，测试通话时应检查日志：
1. `CC_EVENT_VOICE_START request speech success` 只出现 **一次**
2. VoIP 启动日志输出 `Bridge mode: AEC disabled`
3. `voip_do_tx: energy=` 的值随说话有明显波动（非持续为 0）
4. 双向语音音调正常，无电音、变音
