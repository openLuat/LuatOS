# 音乐播放器 HMI · AirUI 工程（Air8603-WiFi / 8603_music）

参考 `docs/index.html`（1024×600 双主题设计稿）1:1 移植到 LuatOS + AirUI。
四屏（播放 / 曲库 / 收藏 / 设置）+ 迷你播放条，深色 / 浅色双主题。
**工程基于 air8603_wifi 版本**，Luatools 新建项目 / 选固件时按该版本配置。

- 硬件：合宙 Air8603-WiFi（Air1603 主控），1024×600 RGB 屏 + GT911 电容触摸
- 开发方式：LuatOS（Lua 5.3）+ AirUI（基于 LVGL 9.4 封装）+ exwin 页面管理
- 数据：`mock.lua` 8 首演示曲目，进度按 1 秒步进推进；不含真实音频解码与 SD 扫描
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
| 播放屏封面 | 300×300 区域，按 8 首曲目的 `art` 分支绘制专属构图 | 换曲联动封面配色与强调色 |
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
│   ├── main.lua            入口：供电轨 → RGB 屏 → airui.init → 背光 → hzfont → GT911 → 开页
│   ├── theme.lua           双主题配色 / 控件封装 / 颜色注册表 / 图标图元 / exwin 页面工厂
│   ├── mock.lua            8 首曲目、设置默认值、运行时状态、筛选与格式化工具
│   └── page_music.lua      顶栏 + 左导航 + 四屏 + 迷你条 + toast + 全部交互与刷新循环
├── docs/                   code 和 readme.md 之外的其余文件
│   └── index.html          1024×600 双主题设计稿（浏览器直接打开）
└── readme.md               本文件
```

## 烧录步骤（Luatools）

1. 电脑安装 Luatools 及 Air8603 板载 USB 转串口驱动；
2. Type-C 数据线接 Air8603-WiFi 的 **USB2** 口；
3. Luatools 新建项目，按 **air8603_wifi** 版本选择 Air1603 对应固件（需含 AirUI + hzfont）；
4. 脚本区添加 `code/` 下全部 4 个 `.lua` 文件，并勾选 **“添加默认 lib”**；
5. 烧录运行：自动进播放屏；左侧导航切屏；搜索框弹键盘；音量 / 进度条可拖动；主题按钮切白天 / 夜间。

## 实现说明

| 机制 | 做法 |
| --- | --- |
| 页面管理 | 单个 exwin；播放 / 曲库 / 收藏 / 设置四屏预建，切页只切 `set_hidden`；迷你条只在非播放屏出现 |
| 刷新驱动 | 单一 `sys.taskInit + sys.wait`：100ms 一帧刷频谱，每 10 拍推进 1 秒播放时间与时钟；**不用 `sys.timerLoopStart`** |
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
15. 主题切换用颜色注册表原位换色，不要再走“关窗 → 重开”整页重建。

## 演示数据与实现状态

- 曲目、收藏、容量、硬件信息均为 `mock.lua` / 设置页演示数据，不接真实解码与 SD 扫描；
- 收藏占用空间按 `总秒数 × 0.16MB` 估算；容量条固定为 18.6GB / 32GB（62%）；
- 设置项（主题 / 强调色 / EQ / SD / 24 小时制等）只保存在内存，不写 localStorage / fskv；恢复默认即恢复 `mock.DEF`；
- 自定义曲目仅在本次会话内生效；搜索提交后参与筛选，当前界面不回显输入词；
- 播放进度按 1 秒步进推进，到末尾按当前播放模式自动切歌；
- 已完成：四个 Lua 文件、四屏 + 迷你条、搜索键盘、可拖进度 / 音量、原位主题换色、夜间迷你条高对比优化、全部演示交互；
- 实机待确认：中文字体渲染、触摸坐标、RGB565 色偏、AirUI 键盘在具体固件上的可用性。
