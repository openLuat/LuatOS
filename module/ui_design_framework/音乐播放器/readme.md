> [!IMPORTANT]
> **喇叭：4Ω / 3W 扬声器（由板载 HT6873 功放驱动，使用 5V 电源）。** 起播瞬间 DAC + 功放电流会突然增大，**必须先接独立 5V 电源，再按播放**。仅靠 **Luatools 烧入器（USB）** 供电可能**供电不足**，表现为**一按播放整机闪退**（`trace lost → ffffffff`）；实测改用独立 5V 电源直接供电后播放正常。排查“按播放就重启”第一步必须先换供电，不要先改音频代码。
>
> **硬件基线**：合宙 **Air8603-WiFi**（Air1603 主控）+ 1024×600 RGB 屏（pclk=50MHz，pin_rst=GPIO15）+ GT911 电容触摸（I2C1，RST=GPIO14 / INT=GPIO51）+ PWM3 背光 + 内置 DAC / **HT6873 功放 + 4Ω 3W 扬声器**（AUDIOPA_EN = GPIO73，高电平使能）+ 供电轨 GPIO12 / 56 / 44 / 52（5V / 9V / 12V / 5VOUT）。Luatools 建工程 / 选固件按 **air8603_wifi** 版本配置。

# 音乐播放器 HMI · AirUI 工程（Air8603-WiFi / 8603_music）

参考 `docs/index.html`（1024×600 双主题设计稿）1:1 移植到 LuatOS + AirUI。
四屏（播放 / 曲库 / 收藏 / 设置）+ 迷你播放条，深色 / 浅色双主题。
**工程基于 air8603_wifi 版本**，Luatools 新建项目 / 选固件时按该版本配置。

- 硬件：合宙 Air8603-WiFi（Air1603 主控），1024×600 RGB 屏 + GT911 电容触摸
- 开发方式：LuatOS（Lua 5.3）+ AirUI（基于 LVGL 9.4 封装）+ exwin 页面管理
- 数据：`mock.lua` 9 首演示曲目，第 1 首「试听1 / 无名氏 / 6s」为真实 MP3，其余为演示数据、不扫描真实 SD 卡
- 资源：**零 PNG 贴图**。图标优先使用 AirUI 内置 symbol，封面 / 频谱 / 进度 / 按钮由 `shape` 的 line / rect / circle 绘制
- 字号：正文 16~18，数值 20~27，最小 16

## 调试硬件环境

| 项目 | 说明 |
| --- | --- |
| 板卡 | 合宙 Air8603-WiFi（主控 Air1603） |
| 屏幕 | 1024×600 RGB，`display.init("custom", ...)`，pclk = 50MHz，pin_rst = GPIO15 |
| 触摸 | GT911（I2C1 轮询，TP_RST = GPIO14 / TP_INT = GPIO51）；RST 由内核 `tp_gt9xx_gpio_init` 完成，脚本不要重复拉低 |
| 背光 | PWM3 @1kHz，首帧上屏后再开；失败回退 `pwm.setup + pwm.start` |
| 供电轨 | 5V_EN = GPIO12，9V_EN = GPIO56，12V_EN = GPIO44，5VOUT_EN = GPIO52（顺序上电） |
| 模组使能与功放 | 网络模组 RST = GPIO72（低），SD_EN = GPIO74（高），AUDIOPA_EN = GPIO73（高） |
| 字库 | `airui.font_load{ type="hzfont", size=16, cache_size=1024, antialias=1 }`，必须在 `airui.init` 之后 |

## 内核固件

- 固件：按 **air8603_wifi** 版本选配 LuatOS 固件（Air1603，推荐 102 号脚本区固件）
- 必须包含：`airui`、`exwin`、`hzfont`；脚本区 / 文件系统需 `display`、`tp`、`i2c`、`gpio`、`pwm`
- AirUI 需支持 `airui.label(symbol)`、`airui.slider`、`airui.textarea`、`airui.keyboard`；缺少输入组件时搜索框只 toast 提示，不会回退到预设词循环
- Luatools 烧录时勾选 **“添加默认 lib”**（`exwin` 为扩展库）

## 页面结构（与 docs/index.html 逐段对应）

| 区块 | 内容 | 交互 |
| --- | --- | --- |
| 顶栏 | AUDIO 品牌、当前页副标题、SD CARD 音源点、蓝牙 / WiFi 符号、时钟、白天 / 夜间按钮 | 主题按钮原位换色；白天竖线在左、夜间在右；时钟按 24/12 小时制设置刷新 |
| 左导航 | 播放 / 曲库 / 收藏 / 设置四个 48×48 按钮，底部 `01 / 04` | 点击切屏；四屏预建，只做 `set_hidden`，不销毁控件 |
| 播放屏封面 | 300×300 区域，按 9 首曲目的 `art` 分支绘制专属构图 | 换曲联动封面配色与强调色 |
| 播放屏频谱 | 40 根柱，拆成 2 个 shape 各 20 根 | 100ms 刷新；关频谱 / 非播放屏直接跳过 |
| 播放屏进度 | 自绘轨道 / 填充 / 旋钮 + 透明 `airui.slider` | **可拖动**；程序回写用 `p_syncing` 防抖，拖动期间不误判 |
| 播放屏控制 | 模式、上一首、播放 / 暂停、下一首、音量、收藏 | 模式循环 / 随机用 AirUI symbol；音量 **可拖动**；收藏心形即时切换 |
| 播放屏队列 | 从当前曲目循环展示 5 行，当前行带 3 段小均衡器 | 行内点播；时间列固定左对齐 |
| 曲库屏 | 搜索框、格式筛选、排序下拉、重新扫描、6 行表格、分页 | 点搜索框弹出 **AirUI 键盘输入法**，提交后筛选生效，取消时键盘同步隐藏；排序菜单四项与“默认排序”按钮对齐 |
| 曲库屏加歌 | `+ 自定义曲目` 展开面板 | 字段为演示值，“添加并播放”追加曲目并立即播放；会话内生效 |
| 收藏屏 | 统计条（曲目数 / 总时长 / 占用空间）、播放全部、清空收藏、6 行移除 | 清空为二次确认，3 秒后自动复位；行内移除即时刷新 |
| 设置屏 | 外观：主题模式 / 强调色 / 频谱 / 24 小时制；音频：音源标签 / EQ / 断点记忆；存储：Micro-SD / 容量条；硬件信息与恢复默认 | 主题与强调色原位换色；关 SD 后曲库空态并停止播放；恢复默认后刷新当前页配色 |
| 迷你播放条 | 非播放屏出现：小封面、曲名、进度（可拖）、上一首 / 播放 / 下一首、音量 | 与播放屏共用播放状态和同步保护；夜间使用专用高对比色，轨道 / 按钮 / 图标 / 辅助文字均可读 |
| toast | 预建容器，只改文本 + 显隐 | 1900ms 后自动隐藏，不销毁 |

## 文件结构（按框架统一架构要求）

```
音乐播放器/
├── code/                   所有 Lua 源码
│   ├── main.lua            入口：看门狗 → 供电轨 → RGB 屏 → airui.init → 背光 → hzfont → GT911 → 音频 → 开页
│   ├── theme.lua           双主题配色 / 控件封装 / 颜色注册表 / 图标图元 / exwin 页面工厂
│   ├── mock.lua            9 首曲目（第 1 首试听1）、设置默认值、运行时状态、筛选与格式化工具
│   ├── page_music.lua      顶栏 + 左导航 + 四屏 + 迷你条 + toast + 全部交互与刷新循环
│   ├── app_audio.lua       音频后端：内置 6 秒 MP3 / exaudio.play_start（官方路径）/ audio 兜底
│   ├── exaudio.lua         音频扩展库（从 LuatOS/script/libs 复制，require "exaudio" 必需）
│   └── exair153x_wdt.lua   外置 Air153D 硬件看门狗驱动（来自 TMR_Batching_System）
├── audio/                  音频资源
│   └── demo_10s.mp3        6 秒示例 MP3（官方 sample-6s.mp3，文件名沿用旧名；曲库显示为「试听1」）
├── docs/                   code 和 readme.md 之外的其余文件
│   ├── index.html          1024×600 双主题设计稿（浏览器直接打开）
│   └── AirUI 六个项目复盘.md  含本项目的通用复盘与提示词参考
└── readme.md               本文件
```

## 烧录步骤（Luatools）

1. 电脑安装 Luatools 及 Air8603 板载 USB 转串口驱动；
2. Type-C 数据线接 Air8603-WiFi 的 **USB2** 口；
3. Luatools 新建项目，按 **air8603_wifi** 版本选择 Air1603 对应固件（需含 AirUI + hzfont）；
4. 脚本区添加 `code/` 下全部 7 个 `.lua` 文件（含 `exaudio.lua`），并勾选 **“添加默认 lib”**；
5. 把 `audio/demo_10s.mp3` 也加入 Luatools（脚本区或资源区均可，保持文件名 `demo_10s.mp3`；被拍平到 `/luadb/` 也能识别）；
6. 烧录运行：自动进播放屏；左侧导航切屏；搜索框弹键盘；音量 / 进度条可拖动；主题按钮切白天 / 夜间；
7. 第一首为「试听1 / 无名氏 / 6s」，按播放键应能听到声音；切到其他曲目会自动停止放歌；试听结束按当前模式自动切下一首。

## 实现说明

| 机制 | 做法 |
| --- | --- |
| 页面管理 | 单个 exwin；播放 / 曲库 / 收藏 / 设置四屏预建，切页只切 `set_hidden`；迷你条只在非播放屏出现 |
| 刷新驱动 | 单一 `sys.taskInit + sys.wait`：100ms 一帧刷频谱 + 进度条线条/圆点，每 10 拍推进 1 秒并刷文字时钟；起播后进度由 UI 任务推进，播放完成由 exaudio 回调收尾；**不用 `sys.timerLoopStart`** |
| 真实音频 | `app_audio.lua` 探测 `/luadb/audio/demo_10s.mp3` 等路径；按官方 Air1603 demo 走 `exaudio.play_start({type=0, content, cbfnc})`，不直调 `audio_v2.play/get_play_clock`（实测会播放后闪退）；音频已换成官方 6 秒示例（44.1kHz 单声道 / 56kbps）；旧 `audio` 只作兜底；只有 `mock.TRACKS[1].audio=true` 的「试听1」会出声 |
| 硬件看门狗 | 内部 `wdt.init(60000)` + 独立心跳 task 每秒喂狗；外置 Air153D 用 `exair153x_wdt` 驱动 GPIO57 自动喂狗，解决约 10 分钟周期重启；两者互不替代 |
| 异常隔离 | 刷新 task 每帧整体 `pcall`，单帧异常只打日志不退出循环；播放 / 切歌只刷可见页，其他页 `theme.defer` 延后，避免一次点击产生几十次 `set_items` |
| 图元刷新 | 动态图元统一走 `put()`：空表且已清空则跳过 `set_items`；文本用 `set_text()` 同值去重 |
| 图元上限 | 单 shape ≤32 图元；40 柱频谱拆成 2 个 shape，各 20 柱 |
| 主题切换 | `theme.apply()` 就地覆写同一张 `theme.C`，`theme.register()` + `theme.recolor()` 原位换色；不关窗、不重建整页 |
| 夜间迷你条 | `theme.PALETTES` 提供 `track2 / btn2 / mini / mini_border` 专用色；播放键整颗琥珀实色、播放/暂停符号固定白色，避免深色底上糊成一片 |
| 进度 / 音量 | 透明 `airui.slider` + 自绘轨道；`p_syncing` / `vol_syncing` 防止程序回写触发用户回调；音量有 `theme.slider` 回退 |
| 输入键盘 | `airui.textarea` + `airui.keyboard`；输入框和“收起键盘 / 搜索 / 取消”栏整体上移约一行键高，使用不透明背景，露出更多曲目行；“收起键盘”可隐藏键盘并切换为“展开键盘”；关闭时先 `hide()` 键盘，再 `theme.defer` 延迟销毁输入层 |
| 点击热区 | 可点区域最后压一层透明 `theme.hit`，避免子 label / shape 拦触摸导致“要点两下” |
| 事件外执行 | 销毁 / 重建动作统一 `theme.defer(fn, 30)`，内部 `pcall` 保护 |
| 页面工厂 | exwin 先 close 旧窗再 open 新窗；`bind_root` 存在才调用且 `pcall` 保护 |
| 容错 | 初始化、动态 setter、键盘 / 输入组件均用 `pcall` 兜底，缺组件时 toast 提示或降级 |

## 踩坑要点（来自 theme.lua 头部，务必遵守）

1. `label` 文字在框内**顶部对齐** → `theme.txt` 统一下移 y 并把 h 收紧到 `size * 1.28`；
2. 只有 `container` 有 `set_hidden`，`label / shape / button` 没有 → 要隐藏就塞进容器；
3. 坐标 / 半径 / 线宽一律取整，小数会让整批图元被固件丢弃；
4. 不用 `arc / ellipse`（本批固件不渲染），弧线用多段 line 拼；
5. 单 shape 图元超过 32 会吞掉后半段，封面 / 频谱都按此拆批；
6. `set_items` 用整表重建，shape 容器范围必须盖住整块图形，否则被裁剪；
7. 无渐变能力，用纯色 + 多层低透明度圆 / 方块近似；
8. 点击回调里销毁 / 重建子树有 use-after-free 风险 → 一律 `theme.defer` 延后；
9. 子 label / shape 会拦触摸 → 可点区域最后压 `theme.hit`；
10. 部分固件 `exwin` 没有 `bind_root` → 必须 `if exwin.bind_root then pcall(...) end`；
11. 切页先 close 旧窗再 open 新窗；本工程正常切屏不重建，只在首次 `open()` 创建 exwin；
12. 禁用 `sys.timerLoopStart`：固定周期投递会积压，几分钟后触发 `task event too much`；
13. 中文宽度按 UTF-8 码点估算（中文 1、ASCII 0.55），不能按字节算；
14. 键盘关闭必须先 `hide()` 再销毁，否则取消后键盘残留；
15. 主题切换用颜色注册表原位换色，不要再走“关窗 → 重开”整页重建；
16. 外置 Air153D 必须用 GPIO57 独立喂狗，内部 `wdt` 喂不到它；不喂会约 10 分钟整机复位；
17. 音频文件落点不确定时按 `/luadb/audio/ → /luadb/ → /audio/ → /res/ → /` 依次探测，找不到时只走演示时钟，不要卡死；
18. **Air1603 不要直调 `audio_v2.play()/get_play_clock()`**：实测起播约 1~2 秒后整机复位（trace lost → ffffffff）；改用官方 `exaudio.play_start({type=0, content, cbfnc})` + 完成时回调，进度用 mcu 时基估算；
19. **音频格式必须贴近官方 `Air1601&Air1603/sample-6s.mp3`：44.1kHz / 单声道 / 56kbps**。之前用的 24kHz 立体声 MP3 即使平均码率降到 56kbps，仍会在 `change sample_rate to 24000` 后约 2 秒整机复位（trace lost → ffffffff）；现已直接换成官方 `sample-6s.mp3` 原文件，不做拼接/重编码。若仍复位，改用 AMR/WAV；
20. **Air1603 的 `mcu.ticks()` 约 20ms 一拍（`mcu.hz()=50`），不是毫秒**。曾改用 `mcu.ticks2(0)` 修进度，但那版开始一按播放就整机复位；现已回退到能完整播放的 `mcu.ticks()` 实现，UI 进度改由 `page_music` 自己的 100ms 任务按 10 拍=1 秒推进，不依赖音频时基；
21. 播放结束后仍有“滋滋”尾音的根因：`REQUEST_END` 回调里 `exaudio` 先把 `audio_v2_request_index` 清空，随后 `play_stop()` 因无有效请求直接返回，**里面的 `pm(SHUTDOWN)` 不会执行**。现用 `need_stop` 延迟到 `update()`，`play_stop` 后直接把 `GPIO73` 拉低关 PA 切断底噪；**不要再调 `exaudio.pm(SHUTDOWN)`**，它会 `deactivate` 音频驱动，导致下一次 `play_start` 闪退；起播时 `play_start` 会自动 `pm(RESUME)` 重新拉高 PA；
22. 音量拖动不要在 `on_change` 里逐个事件调用 `app_audio.set_volume()` / 刷文字 / 回写滑块：每个触摸事件都做会积压几秒，表现为“拖完约 3 秒声音才变”。改为拖动时只画音量线，100ms 任务里合并成一次 `soft_volume`，并跳过重复音量值；
23. **旧播放未结束就再次 `exaudio.play_start` 会在约 2 秒后整机复位**（log：`播放开始 0/1` 后 `trace lost → ffffffff`）。`M.play()` 发现 `playing/started` 时先 `play_stop`，再用 `restart_after` 延迟 300ms 起播；与官方 demo 两首之间留间隔的做法一致；
24. 即使换成官方 44.1kHz 单声道样本，在 1024×600 RGB 全亮背光 + 68% 音量下，按播放仍会在 DAC/PA 开启瞬间复位。现已按可运行的 8607 工程做法：开机 `GPIO73=0`（功放交给 `exaudio.setup` 接管）、`pa_delay=10` / `dac_time_delay=600`、默认音量 40、背光 85%，给电源和 DAC 启动留余量；
25. **官方文档明确 `exaudio.play_start/play_stop` 只能在 task 中调用**（<https://docs.openluat.com/air780epm/luatos/app/common/audio/>）。之前从 AirUI 点击回调直接调用会整机复位；现改为 `M.play()/M.stop()/M.pause()` 只投递 `pending_cmd`，由 `app_audio` 的 `audio_cmd_task` 在 task 上下文里真正调用 `do_play()/do_stop()`；
26. **按播放整机闪退的最终根因是外部供电不足/不稳**：改成直接连接电源后不再闪退。排查 DAC+PA 起播瞬间的 `trace lost → ffffffff`，第一步应先换供电/检查电源线和电流能力，不要先怀疑音频格式或 Lua 逻辑。上面第 18~25 条的软件改动仍保留，作为提高鲁棒性的措施，但不是这次复位的根因。

## 延伸阅读

- `docs/AirUI 六个项目复盘.md`：六个 AirUI 工程的提示词、踩坑与验收方法；本项目对应第 2.6 节，包含“按播放偶发卡死”的完整根因与修复。

## 演示数据与实现状态

- 曲目、收藏、容量、硬件信息仍为 `mock.lua` 演示数据；曲库列表不扫描真实 SD 卡；
- 真实声音只来自第 1 首「试听1 / 无名氏 / 6s」（`audio/demo_10s.mp3`，文件名沿用旧名）；点播放或点该曲目会起播；
- 点第 2~9 首（如「晴天」）仍进入播放态、走 UI 演示进度但没有声音；只有第 1 首会调用 `exaudio.play_start` 出声；切到无音频曲目时立即停止真实输出，不会误触发音频；试听结束按当前模式自动切下一首或单曲重播；音量条实时生效；
- 收藏占用空间按 `总秒数 × 0.16MB` 估算；容量条固定为 18.6GB / 32GB（62%）；
- 设置项（主题 / 强调色 / EQ / SD / 24 小时制等）只保存在内存，不写 localStorage / fskv；恢复默认即恢复 `mock.DEF`；
- 自定义曲目仅在本次会话内生效；搜索提交后参与筛选，当前界面不回显输入词；
- 已完成：七个 Lua 文件、四屏 + 迷你条、搜索键盘、可拖进度 / 音量、原位主题换色、夜间迷你条高对比优化、第 1 首真实 6 秒 MP3 播放、切到其他曲目自动静音、内部 + 外置硬件看门狗、全部演示交互；
- 实机待确认：中文字体渲染、触摸坐标、RGB565 色偏、AirUI 键盘在具体固件上的可用性、外置看门狗 GPIO57 接线与实际超时档位。
