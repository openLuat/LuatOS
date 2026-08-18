# 应用工厂（Audio_v2）功能方案

> 日期：2026-08-06 ｜ 范围：`app_engine/factory`
> 目标型号：`Engine_Air1602_AirLCD_1100_10421_V000`（先验证，后扩展）
> 音频框架：**audio_v2（新框架，直接调用，不经 exaudio）**

---

## 一、结论摘要

| 决策点 | 结论 |
|--------|------|
| 应用定位 | **应用工厂**（最终名），录音/播放是**第一个功能**，主页为功能列表，便于后续扩展 |
| 音频框架 | **audio_v2 直接调用**（用户指定），不经过 exaudio |
| 常开 vs 进APP开关 | **进APP开关**：进入录音功能页才初始化驱动，退出时 `shutdown` 下电 |
| config 驱动 | `features.app_factory` + `hw.audio` 子表 + `ui.show_app_factory` |
| 录音存储 | `/ram/record.amr`（内存文件系统），AMR_NB，~1.2KB/s |
| 文件名约束 | 所有代码文件 ≤24 字节（见第六节命名清单） |
| 图标命名 | `app_factory.png`（15 字节） |

---

## 二、应用定位：应用工厂

应用工厂是一个**功能容器应用**，录音/播放只是其中的第一个功能。

```
应用工厂（factory_win 主页）
├── 录音播放   ← 当前第一个功能（factory_rec_win）
├── ...        ← 未来扩展功能（语音对讲/音箱/提示音管理等）
```

- 桌面入口：`应用工厂` → `OPEN_APP_FACTORY_WIN` → 打开主页（功能列表）
- 主页点击"录音播放" → `OPEN_FACTORY_REC_WIN` → 打开录音播放页
- 业务层同样分层：`factory_app.lua`（工厂主逻辑）+ `factory_rec.lua`（录音播放业务）

> 这样设计的好处：未来加新功能时，只需在主页列表加一项 + 新增一个 `xxx.lua` + `xxx_win.lua`，不动整体框架。

---

## 三、audio_v2 方案（核心）

### 3.1 audio_v2 关键 API（已确认）

| 用途 | API | 说明 |
|------|-----|------|
| 合成驱动ID | `audio_v2.make_probe_id(tx_type, tx_id, rx_type, rx_id)` | I2S2 双工 → `(I2S,2,I2S,2)` |
| 设置默认驱动 | `audio_v2.set_default_driver(pid)` | Air1602 默认 DAC，需切到 I2S2 |
| 配置PA电源 | `audio_v2.config_pa_power_ctrl(true, 45, 1, delay_ms, pid)` | PA_EN=GPIO45 高电平使能 |
| 配置Codec电源 | `audio_v2.config_codec_power_ctrl(true, 49, 1, ready_ms, off_ms, pid)` | 8311_EN=GPIO49 |
| I2S格式 | `audio_v2.config(CFG_PARAM_xxx, value, nil, pid)` | MODE/FRAME_BITS/CHANNEL |
| 播放文件 | `audio_v2.play(path, err_stop, priority, pid, codec_id)` | 返回 req_id |
| 录音文件 | `audio_v2.record(save_path, seconds, codec_id, priority, ...)` | 返回 req_id |
| 停止 | `audio_v2.stop(req_id)` | 按请求索引停止 |
| 事件回调 | `audio_v2.on(function(req_id, event, param))` | `REQUEST_END` = 播放/录音结束 |
| 下电 | `audio_v2.shutdown(true, true, true, pid)` | 先关PA→再关Codec→再停驱动 |

### 3.2 初始化序列（进入录音功能页时）

```lua
local function audio_init(ac)
    -- ac = project_config.hw.audio
    -- 1. 合成 I2S2 双工驱动 ID（播放+录音都走 I2S2）
    local pid = audio_v2.make_probe_id(audio_v2.DRIVER_TYPE_I2S, ac.i2s_id,
                                       audio_v2.DRIVER_TYPE_I2S, ac.i2s_id)
    if not pid then return nil end

    -- 2. Air1602 默认驱动是 DAC，必须切到 I2S2
    audio_v2.set_default_driver(pid)

    -- 3. I2S 格式配置（ES8311 用 LSB 左对齐）
    audio_v2.config(audio_v2.CFG_PARAM_I2S_MODE, audio_v2.CFG_VALUE_I2S_MODE_LSB, nil, pid)
    audio_v2.config(audio_v2.CFG_PARAM_I2S_FRAME_BITS, ac.bits_per_sample, nil, pid)
    audio_v2.config(audio_v2.CFG_PARAM_I2S_CHANNEL_TYPE, audio_v2.CFG_VALUE_I2S_CHANNEL_TYPE_MONO, nil, pid)

    -- 4. 电源管理：PA 先延时再开，CODEC 上电等待稳定 —— 防 pop 音
    audio_v2.config_pa_power_ctrl(true, ac.pa_ctrl, ac.pa_on_level, 100, pid)
    audio_v2.config_codec_power_ctrl(true, ac.dac_ctrl, ac.dac_on_level, 200, 10, pid)

    -- 5. 注册事件回调（播放/录音完成检测）
    audio_v2.on(rec_on_event)   -- rec_on_event 全局命名，禁止匿名闭包

    return pid
end
```

> ⚠️ **验证点**：目标型号固件的默认驱动是否已是 I2S2？用 `audio_v2.get_driver_info()` / `get_driver_id()` 检查。若不是再 `set_default_driver`。若默认已是 I2S2 则省略第 2 步。

### 3.3 录音（AMR_NB → /ram）

```lua
-- 录音到文件，AMR_NB，指定时长秒数，codec_id 决定采样率(8k)
local ok, req_id = audio_v2.record("/ram/record.amr", ac.max_record_time,
                                   audio_v2.DATA_CODEC_TYPE_AMR_NB,
                                   0, nil, nil, nil, pid)
-- 完成检测：audio_v2.on 回调中 event == audio_v2.REQUEST_END 且 request_index == req_id
```

### 3.4 播放（/ram 的 AMR）

```lua
local ok, req_id = audio_v2.play("/ram/record.amr", true, 1, pid,
                                 audio_v2.DATA_CODEC_TYPE_AMR_NB)
-- 完成检测：REQUEST_END
```

### 3.5 退出清理（关闭录音功能页时）

```lua
local function audio_deinit()
    if rec_req_id then audio_v2.stop(rec_req_id); rec_req_id = nil end
    if play_req_id then audio_v2.stop(play_req_id); play_req_id = nil end
    audio_v2.shutdown(true, true, true, pid)   -- 先关PA → 再关CODEC → 停驱动
    if io.exists("/ram/record.amr") then os.remove("/ram/record.amr") end
end
```

---

## 四、config 配置设计

### 4.1 目标型号 `config/eng_1602_10i_v10421.lua` 新增

```lua
-- 功能开关
features = {
    -- ... 现有项 ...
    app_factory = true,    -- 启用"应用工厂"
    speaker = true,        -- 喇叭（音频输出）
    mic = true,            -- 麦克风（音频输入）
},

-- 硬件配置
hw = {
    -- ... 现有 lcd/tp/battery ...
    audio = {
        model = "es8311",          -- 音频编解码芯片
        i2c_id = 1,                -- I2C1 控制总线
        i2s_id = 2,                -- I2S2 数据总线
        pa_ctrl = 45,              -- PA_EN  功放使能 GPIO
        dac_ctrl = 49,             -- 8311_EN 编解码使能 GPIO
        pa_on_level = 1,           -- PA 高电平使能
        dac_on_level = 1,          -- CODEC 高电平使能
        i2s_sample = 8000,         -- I2S 采样率（AMR_NB=8k；AMR_WB=16k）
        bits_per_sample = 16,      -- 采样位深
        play_vol = 70,             -- 默认播放音量(0~100)
        mic_vol = 70,              -- 默认录音音量(0~100)
        record_format = "AMR_NB",  -- 录音格式
        max_record_time = 60,      -- 最大录音时长(秒)
    },
},

-- UI 显示
ui = {
    -- ... 现有项 ...
    show_app_factory = true,   -- 桌面显示"应用工厂"入口
},
```

### 4.2 引脚映射（已从《Air1601/Air1602管脚复用表260805.xlsx》确认）

**I2S2（PIN69~72，四线）**：

| PIN | GPIO | I2S2 信号 | 说明 |
|-----|------|-----------|------|
| 69 | GPIO40 | I2S2_SD | 数据线（播放/录音共用） |
| 70 | GPIO41 | I2S2_LRCK | 帧时钟 |
| 71 | GPIO48 | I2S2_BCLK | 位时钟 |
| 72 | GPIO44 | I2S2_MCLK | 主时钟 |

**I2C1（PIN32/33）**：

| PIN | 复用功能 | 说明 |
|-----|---------|------|
| 32 | I2C1_SDA | 数据线（注意：默认是 UART5_TXD） |
| 33 | I2C1_CLK | 时钟线（复用表写作 CLK，不是 SCL） |

**控制脚（8311_EN / PA_EN）**：
- 8311_EN = GPIO49（对应 PIN63，UART6_TXD/I2C2_SDA 复用脚）
- PA_EN = GPIO45（对应 PIN75，默认 GPIO45）

**关键结论**：
1. **I2C1 已经用于触摸屏**（config 里 `tp.params.port = 1`），I2C1 引脚复用已由固件默认配置，音频直接用 `i2c_id = 1` 即可，通常**无需重复配置**
2. **I2S2 引脚由 audio_v2 驱动管理**：Air1602 固件默认驱动是 "DAC+I2S2"，切 I2S2 驱动后固件自动配置 PIN69-72，通常**无需在 config pins 里手动配置**
3. 若验证发现固件未自动配置，再在 config `pins` 中补：

```lua
pins = {
    -- 仅在固件未自动配置时才需要（一般可省略）
    { pin = 69, func = "I2S2_SD"   },
    { pin = 70, func = "I2S2_LRCK" },
    { pin = 71, func = "I2S2_BCLK" },
    { pin = 72, func = "I2S2_MCLK" },
}
```

> ⚠️ **冲突提醒**：PIN32/33 默认是 UART5_TXD/RXD，配置为 I2C1 后 UART5 不可用；PIN69-72 默认是 GPIO40/41/48/44，配置为 I2S2 后这些 GPIO 不可用。

---

## 五、代码结构（UI/业务解耦 + 文件名 ≤24 字节）

### 5.1 文件清单（字节数已核）

| 文件路径 | 字节 | 职责 |
|---------|------|------|
| `app/factory/factory_app.lua` | 14 | 应用工厂业务层：主页功能列表、事件分发 |
| `app/factory/factory_rec.lua` | 14 | 录音播放业务层：audio_v2 初始化/录音/播放/清理 |
| `ui/factory_win.lua` | 15 | 应用工厂主页窗口（功能列表） |
| `ui/factory_rec_win.lua` | 18 | 录音播放窗口 |
| `res/app_factory.png` | 15 | 应用工厂桌面图标 |

> 全部 ≤24 字节。注意：**不能用中文文件名**（如 `应用工厂.lua` 为 12+4=16 字节，虽 ≤24 但 LuatOS 脚本区建议 ASCII，且 git/工具链兼容性差）。

### 5.2 消息协议

```
OPEN_APP_FACTORY_WIN    → 打开应用工厂主页
OPEN_FACTORY_REC_WIN    → 打开录音播放页

FACTORY_REC_START       → 开始录音
FACTORY_REC_STOP        → 停止录音
FACTORY_REC_PLAY        → 播放录音
FACTORY_REC_STOP_PLAY   → 停止播放
FACTORY_REC_RESET       → 退出清理（停+下电+删文件）

FACTORY_REC_STATE({state}) → 状态同步给 UI（idle/recording/playing）
FACTORY_REC_STATUS(msg)    → 提示文本
FACTORY_REC_DURATION(sec)  → 录音计时
```

### 5.3 业务层 `app/factory/factory_rec.lua`（核心）

```lua
-- 状态机：idle / recording / playing，互斥
local state = "idle"
local pid = nil
local rec_req = nil
local play_req = nil
local rec_path = "/ram/record.amr"

local function rec_on_event(req_id, event, param) ... end  -- 命名，不用匿名

local function rec_start()
    if state ~= "idle" then return end
    if io.exists(rec_path) then os.remove(rec_path) end
    local ok, req = audio_v2.record(rec_path, ac.max_record_time,
                                    audio_v2.DATA_CODEC_TYPE_AMR_NB,
                                    0, nil, nil, nil, pid)
    if ok then state = "recording"; rec_req = req; publish(FACTORY_REC_STATE, {state="recording"}) end
end

local function rec_stop()
    if state == "recording" and rec_req then audio_v2.stop(rec_req) end
end

local function rec_play()
    if state ~= "idle" then return end
    if io.exists(rec_path) and io.fileSize(rec_path) > 0 then
        local ok, req = audio_v2.play(rec_path, true, 1, pid, audio_v2.DATA_CODEC_TYPE_AMR_NB)
        if ok then state = "playing"; play_req = req end
    end
end

local function rec_reset()
    if state == "recording" and rec_req then audio_v2.stop(rec_req) end
    if state == "playing" and play_req then audio_v2.stop(play_req) end
    if pid then audio_v2.shutdown(true, true, true, pid); pid = nil end
    if io.exists(rec_path) then os.remove(rec_path) end
    state = "idle"
end

sys.subscribe("FACTORY_REC_START", function() rec_start() end)
-- ... 其余订阅
```

### 5.4 界面层

- `ui/factory_win.lua`：主页功能列表（卡片式，参照 settings_win 的 create_card 模式），点击"录音播放" → `OPEN_FACTORY_REC_WIN`
- `ui/factory_rec_win.lua`：录音/播放/停止按钮 + 计时显示，on_create 时 `audio_init()`，on_destroy 时 `rec_reset()`

### 5.5 桌面入口挂载（idle_win.lua）

```lua
local has_factory = (_G.project_config and _G.project_config.features
                     and _G.project_config.features.app_factory
                     and _G.project_config.ui and _G.project_config.ui.show_app_factory)

local builtin_apps = {
    { name = "设置",     win = "SETTINGS",     icon = "/luadb/settings.png" },
    { name = "应用市场", win = "APP_STORE",    icon = "/luadb/app_store_icon.png" },
    { name = "文件管理", win = "FILE_MANAGER", icon = "/luadb/file_manager.png" },
    { name = "网络测速", win = "SPEEDTEST",    icon = "/luadb/internet_speed.png" },
}
if has_factory then
    table.insert(builtin_apps, { name = "应用工厂", win = "APP_FACTORY", icon = "/luadb/app_factory.png" })
end
```

### 5.6 模块注册

- `app_main.lua`：`if features.app_factory then require "factory_app" end`
- `ui_main.lua`：`require "factory_win"`（窗口内部自行判断，无配置则 open 时提示）
- `platform_loader.lua` 编译清单：加 `require ("factory_app")` / `require ("factory_rec")` / `require ("factory_win")` / `require ("factory_rec_win")`

---

## 六、落地步骤

| 步骤 | 内容 | 文件 |
|------|------|------|
| 1 | 核对 I2C1/I2S2 引脚复用号 | config |
| 2 | config 新增 `features.app_factory/speaker/mic` + `hw.audio` + `ui.show_app_factory` + `pins` | `eng_1602_10i_v10421.lua` |
| 3 | 最小验证：audio_v2 驱动 I2S2 录音/播放跑通，确认默认驱动与电源时序 | 临时脚本 |
| 4 | 业务层 `factory_app.lua` + `factory_rec.lua` | 新文件 |
| 5 | 界面层 `factory_win.lua` + `factory_rec_win.lua` | 新文件 |
| 6 | 桌面入口 + 模块注册 + 编译清单 | idle_win/app_main/ui_main/platform_loader |
| 7 | 图标 `app_factory.png` 放 `res/` | 新文件 |
| 8 | 真机联调：录音→播放→退出→重启，验证 pop 音/内存/文件残留 | 硬件 |
| 9 | 扩展型号：只改各 config 的 `hw.audio` + 引脚 | 各 config |

---

## 七、风险与注意事项

1. **默认驱动**：Air1602 默认 DAC，需确认目标固件默认驱动是否为 I2S2。用 `get_driver_info()` 检查，必要时 `set_default_driver(pid)`。
2. **电源时序**：`config_pa_power_ctrl` / `config_codec_power_ctrl` 的顺序与延时是防 pop 音关键。CODEC 上电等待默认 200ms，PA 延时默认 100ms，先 PA 后 Codec 关闭。
3. **事件回调**：`audio_v2.on` 全局回调，用 `request_index` 区分是录音还是播放结束。回调内禁止耗时操作。
4. **AMR_NB 采样率 8k**：`i2s_sample` 需与 codec 匹配（AMR_NB=8k / AMR_WB=16k），录音和播放要一致。
5. **/ram 掉电丢失**：websocket 传输前不能断电；传输完成后 `os.remove`。
6. **录音时长限制**：`max_record_time` 建议 60~120 秒，防 /ram 耗尽。
7. **文件名 ≤24 字节**：所有新增 Lua/图标文件按第五节命名清单，用 ASCII。
8. **exaudio 兼容**：若未来要叠加 TTS/其他音频功能，注意 audio_v2 与 exaudio 不要混用驱动。
