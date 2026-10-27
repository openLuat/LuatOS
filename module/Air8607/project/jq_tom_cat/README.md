# 汤姆猫 TOM CAT（Air8607 / 10 寸 1024x600）

会捂爪子的触摸猫。点猫身上不同位置，两只前爪扑过去把那里捂住，停一下再弹回身侧，
同时**说一句中文**。

**工程内零图片素材**：猫的每一根线条都是 `airui.shape` 图元程序化绘制，不需要 png/jpg。

```
点头顶 -> "谢谢主人"     点肚子 -> "肚子好舒服"    点尾巴 -> "别拽尾巴"
点耳朵 -> "耳朵好痒"     点眼睛 -> "别戳眼睛"      点口鼻 -> "主人你好"
点前爪 -> "手也摸摸"     点后脚 -> "脚脚怕痒"      点空白/面板 -> 不响应
```

## 声音怎么出：两条路，自动选

`app/voice.lua` 启动时探测固件能力，按顺序选：

| 路径 | 条件 | 说明 |
|---|---|---|
| **A 本地 TTS** | 固件有 `audio.tts` / `audio_v2.tts` | `exaudio.play_start({type = 1, content = 文本})`，零资源、任意台词 |
| **B WAV 资源** | 固件**没有** TTS，但有 `exaudio` 流式播放 | 播 `res/voice/<key>.wav` 里预合成好的中文（16kHz/16bit/单声道），直接喂 PCM，**不需要任何解码器或 TTS 引擎** |
| 静音 | 两条都不满足 | 交互/气泡/动画照常，左侧状态行写明原因 |

**固件改不了也能说话** —— 走路径 B：WAV 是在 PC 上用系统中文语音（Microsoft Huihui）
提前合成好的，设备端只做 PCM 流式播放，这也是本工程默认的资源方案（8 句共 262KB）。

## 硬件与前提

| 项 | 值 |
|---|---|
| 板卡 | Air8607（`module/Air8607/project/factory/config/eng_8607_10i_v0.lua` 同款） |
| 屏幕 | 10 寸 RGB 免序列屏，1024x600，LCD 复位 `GPIO15`，供电使能 `GPIO17`(低有效)，背光 `PWM3` |
| 触摸 | GT911，I2C1 400kHz，`pin_rst=14` `pin_int=51`（`tp.init` 必须带 `w`/`h`，否则 AirUI 侧绑定会静默失败） |
| 声音 | 板载 DAC + HT6873 功放，`AUDIOPA_EN=GPIO73`（高电平开） |
| 固件要求 | `LUAT_USE_AIRUI`（含 `airui.shape`）+ `exaudio`。**TTS 可选**，没有就走 WAV 资源 |

## 目录

```
tom_cat/
├── main.lua                 入口：PROJECT/VERSION + require + sys.run()
├── app/
│   ├── app_main.lua         上电时序：供电→显示→AirUI→语音→界面→触摸→主循环→背光
│   └── voice.lua            语音：TTS 优先 / WAV+PCM 兜底 / 静音降级
├── ui/
│   ├── theme.lua            配色 / 布局 / 字号 / 帧率预算 / 音量与采样参数
│   ├── fx.lua               图元池 / 缓动 / 配色 / 多边形扫描填充
│   ├── cat.lua              猫的几何、静态层、动态层、命中测试、各部位台词
│   └── ui_main.lua          界面装配 + 交互状态机 + 主循环
├── drv/lcd/
│   └── exd_air8607_rgb.lua  RGB 屏驱动（display 优先，lcd 兜底）
├── res/voice/               8 句中文 WAV（路径 B 用，共约 262KB）
│   └── head/ear/eye/face/belly/paw/foot/tail .wav
├── tools/
│   └── make_voice_wav.ps1   改台词后重新生成 WAV（PC 上用系统中文语音合成）
└── README.md
```

## 上板

1. 8 个 lua **平铺**拷到设备脚本区根目录（`require` 只认裸文件名，不带子目录）：
   `main.lua / app_main.lua / voice.lua / theme.lua / fx.lua / cat.lua / ui_main.lua / exd_air8607_rgb.lua`
2. `res/voice/` 整个目录一起拷过去，设备上的路径是 `/res/voice/*.wav`
   （`voice.lua` 会依次尝试 `/res/voice/`、`/luadb/res/voice/`、`res/voice/`、`/voice/`，日志里会打印实际用的目录）。
3. 复位运行，日志里应看到其中一条：
   ```
   I/user.voice 语音就绪 本地 TTS 音量 40          <- 路径 A
   I/user.voice 语音就绪 WAV 播放（固件无 TTS）音量 40
   I/user.voice 语音资源就绪 267764 字节 目录 /res/voice/   <- 路径 B 资源加载完
   ```
   若看到 `缺少语音资源 head.wav`，是第 2 步没拷对目录。

## 实现要点

**点了就有反应（响应速度）**
1. `on_touch` 里 `react()` 之后**立刻** `update + draw_dynamic()` 出一帧，不等主循环的 `sys.wait`。
   触摸回调本来就在 LVGL 的 indev 读里，同一轮 handler 就会刷屏，延迟从"最多一个帧周期"
   降到事件处理本身（几毫秒）。那一帧还推了 16ms 让爪子立刻有位移，不然 `ph=0` 时爪子还在原位。
2. 语音每句起播前只做一段短准备（`tts_prep`：`play_stop` → `setup` → `wait(60)`），
   约 60ms；画面前一帧已经刷出去了，听感上仍是"点了就出声"。
   **别把这一步省掉**：`setup` 只做一次时第二句以后会彻底没声，原因见下一条。
3. 每条播报都挂看门狗、回调带代次。音频库的"播完回调"（`cbfnc` / `REQUEST_END`）会丢，
   而 `voice.st.busy` 是单向闩锁：丢一次就永远走 `pending` 分支、连 `play_start` 都不再调用，
   现象正是"只有第一句会播报，之后怎么点都没声"。现在超时按台词字数估算，
   超时强制收尾并接上挂起的那句；`av2.on/aud.on` 的回调签名是 `(请求索引, 事件)`，
   少写一个参数会拿索引去比 `REQUEST_END`，同样会把 `busy` 焊死。
4. 路径 B 的 PCM 在后台逐句读进内存（每句 30~40KB），点的时候直接拼块写流，不碰文件系统；
   连点是直接换播放指针，等于即时打断。流缓冲设 2048 字节（约 64ms），块 512 采样（32ms）。
   流式写入连续失败（C 层请求被回收）会重开一次会话，否则同样是"第二句以后再没声"。
5. 爪子扑过去压到 0.10s，`reach` 抢在声音前面；张嘴/气泡时长按台词字数估，和语音对得上。

**三层渲染，动态层不是整屏**
`shStatic`（背景 + 猫本体，开机画一次）、`shDyn`（尾巴/瞳孔/眼睑/嘴/前爪/粒子/涟漪，每帧重算）、
原生控件（左面板、按钮、气泡）。动态层只覆盖猫舞台 `598x588`（`theme.stage`），
空闲时按 `perf.idle_every=2` 隔帧重算，静止时 CPU 只剩尾巴摆动。

**前爪状态机**
`idle -> reach(0.10s 缓出) -> hold(0.75s 带抖动) -> back(0.20s 回弹) -> idle`。
两只爪子的落点是"点击点 ± `spread`"，每个部位有自己的 `spread/dy`（`cat.lua` 的 `REGIONS`）——
摸脸时分开得比摸头更宽，否则爪子会把张开的嘴挡没（这是视觉上最容易翻车的点）。
只在 `TP_DOWN` 判定一次，按住不放不会反复触发。

**动画用实测帧间隔推进**
`sys.wait(n)` 是"至少睡 n 毫秒"，固定 dt 会让帧率一掉动作就整体变慢、嘴形和语音对不上。
主循环按实测 dt 推进（单帧上限 80ms），既跟得上真实时间又不会因为一次长阻塞跳帧。

## 想改什么改哪里

| 想改 | 位置 |
|---|---|
| 猫的颜色 / 背景 / 面板 | `ui/theme.lua` 的 `c` 表 |
| 猫的体型、部件位置 | `ui/cat.lua` 顶部的 `G` 表（绘制与命中同一份数据） |
| 各部位的台词、眯眼幅度、爪子分开距离 | `ui/cat.lua` 的 `REGIONS`（台词 ≤6 个汉字） |
| 台词音频 | 改 `REGIONS.say` + `tools/make_voice_wav.ps1` 里的 `$lines`，重跑脚本生成 WAV |
| 音量 / 功放引脚 / 采样率 / 块长 | `ui/theme.lua` 的 `audio` 表（`vol` 默认 40） |
| 爪子动画时长、粒子数量 | `ui/ui_main.lua` 的 `PHASE` / `spawn_particles` |
| 帧率 | `ui/theme.lua` 的 `perf.frame_ms`（20≈50fps 目标，33≈30fps，别低于 15） |

## 已知限制

- 路径 B 的台词长度受气泡宽度限制（`theme.bubble` 按 6 个汉字 @32 号留位），超了会溢出。
- WAV 是 16kHz/16bit/单声道，8 句共 262KB；脚本区紧张时可以重跑生成脚本改成 8kHz（体积减半，
  音质变"电话味"，同时把 `theme.audio.rate` 改成 8000）。
- 路径 B 的首句起播延迟主要来自音频流缓冲（约 64ms），脚本侧已压到最小。
- PC 模拟器需要 GUI 版（`bsp/pc/build_windows_32bit_msvc_gui.bat`）才有 AirUI；`app_main` 会跳过
  GT911 与背光，鼠标点击等价于触摸；PC 固件没有 `audio.tts`，会自动走路径 B。
- 面板文字用 hzfont，字号只能是 `theme.fonts` 里那几个（`airui.font_load` 按尺寸载入）。
