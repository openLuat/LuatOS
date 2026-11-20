# AIR KTV 点歌系统 UI · 一比一复刻规格书（make_airui）

> **复刻铁律**：本规格由 `docs/index.html`（单文件，1329 行）逐行逆向提取，并与 6 张界面截图逐项核对而成。
> 目标硬件：Air8603 WiFi 版本，屏幕 1024×600。
> **凡本文档未写明的元素、按钮、文案、颜色、效果，一律不得自行添加或想象；凡是写明的，必须一字不差、一值不改。**

---

## 0. 文档使用方式

1. 第 1–5 章是**全局视觉系统**：配色变量、背景、框架、图标、通用组件。先做这些，再填页面。
2. 第 6 章是**数据**：所有歌曲/歌手/歌单/榜单/拼音候选都按原值内嵌。
3. 第 7 章是**九个页面**：每页按"屏幕从上到下、从左到右"描述每一个可见元素、每一个按键及其功能。
4. 第 8 章是**两个弹窗**，第 9 章是**全部事件行为**。
5. 第 10 章记录用户历轮明确要求，第 11 章是验收标准，附录 A 是完整拼音表。

---

## 1. 总体硬性约束

| 项 | 规格 |
|---|---|
| 交付形态 | **唯一文件 `index.html`**；CSS、JavaScript、数据、SVG 图标全部内嵌；零外部依赖、零网络请求、零字体外链 |
| 画布 | `html,body{width:1024px;height:600px;overflow:hidden}`；`#app` 同尺寸；任何页面都不得出现滚动条 |
| viewport | `<meta name="viewport" content="width=device-width, initial-scale=0">` |
| 文档 | `<html lang="zh-CN">`；`<title>AIR KTV 智能点歌系统</title>`；`<meta charset="UTF-8">` |
| 字体栈 | `"Microsoft YaHei","PingFang SC","Heiti SC",sans-serif`，`body` 基准 `16px` |
| 最小字号 | **所有可见文字 ≥ 16px** |
| 全局 box | `*{box-sizing:border-box;margin:0;padding:0}`；`user-select:none` |
| 触摸 | 列表滚动条**长按 350ms 后才可拖动，短按无效**；所有滑块按住即可连续拖动 |
| 主题 | 深/浅双模式 × 蓝/紫/青三配色，全部互斥单选，且必须保留一个 |
| 页面 | 9 个：首页、歌曲分类、歌手分类、搜索、已点歌曲、排行榜、歌单推荐、正在播放、系统设置 |

---

## 2. 全局视觉系统

### 2.1 深色主题（`body` 默认，`:root`）CSS 变量全表

| 变量 | 值 | 变量 | 值 |
|---|---|---|---|
| --bg | `#10131D` | --sub | `#A7B0C0` |
| --nav | `#171C29` | --line | `rgba(255,255,255,.07)` |
| --topbar | `#141827` | --blue | `#477BFF` |
| --mini | `#161B29` | --blue-hover | `#5C8BFF` |
| --input | `#121624` | --purple | `#7B61FF` |
| --card | `#20283A` | --cyan | `#19D5D0` |
| --card2 | `#252E42` | --placeholder | `#5C6678` |
| --track | `#2C3550` | --op-hover | `#33405C` |
| --tag | `#28324A` | --del | `#FF7B8A` |
| --tag-text | `#CBD3E2` | --rank1 | `#FFD35C` |
| --func | `#2A3450` | --rank2 | `#C9D4E8` |
| --text | `#FFFFFF` | --rank3 | `#E7A46B` |
| --toast-bg | `rgba(20,26,42,.96)` | --sw-off | `#C6D0E0` |
| --glow-a | `rgba(71,123,255,.22)` | --glow-b | `rgba(123,97,255,.20)` |
| --glow-c | `rgba(249,87,166,.13)` | --grid | `rgba(180,205,255,.035)` |
| --glass | `rgba(32,40,58,.70)` | --shadow | `rgba(0,0,0,.35)` |
| --title-grad | `linear-gradient(100deg,#8FB4FF,#B79BFF 55%,#6FE6E1)` | --title-stroke | `rgba(255,255,255,.10)` |

### 2.2 浅色主题（`body[data-mode="light"]`）CSS 变量全表

| 变量 | 值 | 变量 | 值 |
|---|---|---|---|
| --bg | `#F2F4F9` | --sub | `#5A6680` |
| --nav | `#E8ECF5` | --line | `rgba(20,30,60,.10)` |
| --topbar | `#FFFFFF` | --blue | `#2F62E6` |
| --mini | `#FFFFFF` | --blue-hover | `#4A75EC` |
| --input | `#F4F6FB` | --purple | `#6649E8` |
| --card | `#FFFFFF` | --cyan | `#0E9E99` |
| --card2 | `#F0F3FA` | --placeholder | `#9AA5BA` |
| --track | `#DDE3EF` | --op-hover | `#DCE3F0` |
| --tag | `#E9EDF6` | --del | `#E0455C` |
| --tag-text | `#3A4560` | --rank1 | `#D9A400` |
| --func | `#E1E7F2` | --rank2 | `#8492AC` |
| --text | `#1A2233` | --rank3 | `#B8753A` |
| --toast-bg | `rgba(255,255,255,.97)` | --sw-off | `#C7D0E0` |
| --glow-a | `rgba(71,123,255,.30)` | --glow-b | `rgba(140,100,255,.24)` |
| --glow-c | `rgba(249,87,166,.18)` | --grid | `rgba(70,100,180,.07)` |
| --glass | `rgba(255,255,255,.78)` | --shadow | `rgba(40,60,110,.14)` |
| --title-grad | `linear-gradient(100deg,#2F62E6,#7B3FE4 55%,#0E9E99)` | --title-stroke | `rgba(255,255,255,.55)` |

### 2.3 配色变体（仅覆盖 3 个色相变量）

| 选择器 | --blue | --purple | --cyan |
|---|---|---|---|
| `body[data-mode="light"]` | #2F62E6 | #6649E8 | #0E9E99 |
| `body[data-theme="purple"]` | #7B61FF | #477BFF | #B98CFF |
| `body[data-theme="cyan"]` | #19A7CE | #477BFF | #19D5D0 |
| `[data-mode="light"][data-theme="purple"]` | #6649E8 | #2F62E6 | #9B5DE5 |
| `[data-mode="light"][data-theme="cyan"]` | #0E9E99 | #2F62E6 | #0BA8A3 |

> 主题实现：`setTheme()` 把 `state.theme` / `state.mode` 写入 `body` 的 `data-theme` / `data-mode` 属性。

### 2.4 画布背景与装饰层（截图中深色底不是纯黑）

| 层 | 精确规格 |
|---|---|
| `#app` 背景 | 三层径向渐变叠加：① `radial-gradient(760px 420px at 8% -12%, var(--glow-a), transparent 60%)`；② `radial-gradient(680px 440px at 100% 4%, var(--glow-b), transparent 58%)`；③ `radial-gradient(620px 380px at 46% 116%, var(--glow-c), transparent 60%)`；最底层 `var(--bg)` |
| `#app:before` 网格 | `inset:0`；`background-image: linear-gradient(var(--grid) 1px,transparent 1px), linear-gradient(90deg,var(--grid) 1px,transparent 1px)`；`background-size:40px 40px`；`mask-image:linear-gradient(180deg,rgba(0,0,0,.9),rgba(0,0,0,.25) 70%,transparent)`；`pointer-events:none;z-index:0` |
| `#bgdeco` | `inset:0;pointer-events:none;z-index:0;overflow:hidden` |
| `.glow.g1` | 360×360，left −90 top −120，`radial-gradient(circle,var(--glow-a),transparent 68%)`，`border-radius:50%`，`filter:blur(30px)`，`opacity:.55` |
| `.glow.g2` | 420×420，right −120 top 60，`radial-gradient(circle,var(--glow-b),transparent 68%)`，同上模糊与透明度 |
| `.glow.g3` | 380×380，left 340 bottom −200，`radial-gradient(circle,var(--glow-c),transparent 68%)`，同上 |
| `.ring.r1` | 240×240 圆环，`right:60px;top:96px;border:1px solid var(--line)`,`opacity:.5` |
| `.ring.r2` | 150×150 圆环，`right:105px;top:141px`,`opacity:.4` |
| `.note.n1` | 音符描边（i-note），`right:120px;top:120px;70×70;stroke:var(--cyan);stroke-width:1.8;opacity:.10` |
| `.note.n2` | 同上，`left:200px;bottom:110px;46×46;transform:rotate(-18deg)` |
| `.wave` | `left:0;right:0;bottom:56px;height:70px;opacity:.16`；SVG viewBox `0 0 1024 70`，一条 `stroke:var(--cyan);stroke-width:2` 的正弦路径 |

### 2.5 阴影与发光规范

| 场景 | 值 |
|---|---|
| 顶栏 | `box-shadow:0 6px 24px var(--shadow)`；底边 2px 蓝紫青渐变高光线 `linear-gradient(90deg,transparent,var(--blue),var(--purple),var(--cyan),transparent)`，`opacity:.6` |
| 封面 `.cover` | `inset 0 1px 0 rgba(255,255,255,.25), inset 0 -10px 22px rgba(0,0,0,.14), 0 3px 10px var(--shadow)`；`:after` 高光 `linear-gradient(135deg,rgba(255,255,255,.18),transparent 46%)` |
| 卡片 hover（qcard/songcard/newcard/cat-item/pl-card/setcard） | `0 8px 22px var(--shadow), 0 0 0 1px var(--blue), 0 0 18px rgba(71,123,255,.18)` |
| 侧栏选中 | `0 8px 20px rgba(71,123,255,.18), 0 0 0 1px rgba(71,123,255,.35)`；图标块额外 `0 8px 18px rgba(71,123,255,.55)` |
| 大磁贴 `.tile` | `0 10px 24px var(--shadow)`；hover `0 16px 32px var(--shadow)` 且 `translateY(-4px)` |
| 加号按钮 | `0 4px 10px rgba(0,0,0,.22)` |
| 滚动滑块 | `0 0 10px rgba(71,123,255,.35)` |
| Toast | `0 8px 24px rgba(0,0,0,.4)` |
| 弹窗 | `0 24px 60px var(--shadow)` |
| 主播放钮 | `0 8px 24px rgba(71,123,255,.35)` |

### 2.6 字体与文字渐变

- 以下元素使用**渐变文字**：`.phead h2`、`.sec-title h3`、`.artist-card .an`、`.feature .ftitle`、`.play-info .ptitle`、`.pl-card .pn`、`.pl-head .pinfo .pn`、`#mname`、`.mmeta .song-name`。
- 渐变值：`background:var(--title-grad);-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent;color:var(--blue);font-weight:800;letter-spacing:.3px`。
  - 深色：从 `#8FB4FF` → `#B79BFF`(55%) → `#6FE6E1`，整体 100°。
  - 浅色：从 `#2F62E6` → `#7B3FE4`(55%) → `#0E9E99`。
- `.ic` 通用：`20×20px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round;flex:none`；`.ic-fill` 为 `fill:currentColor;stroke:none`。

---

## 3. 全局框架逐元素（每个页面都可见）

### 3.1 DOM 结构树（层级固定）

```
#app
├─ #bgdeco（8 个装饰子元素，见 2.4）
├─ #topbar（logo / sys-name / top-right{clockbox{date,clock} + room}）
├─ #sidebar（5 个 .nav + 隐藏 .nav-foot）
├─ #stage（9 个 section.page，仅 .active 显示）
├─ #mini（mcover / mmeta{mname,martist} / mctrl{prev,toggle,next} / mbar / mtime / mfunc / mcnt / funcPop）
├─ #modalMask + #modal（modal-head + modal-body）
├─ #dim
└─ #toast
```

### 3.2 顶栏 `#topbar`（高 58，贯穿全宽）—— 对应所有截图最上方

| 元素 | 规格 |
|---|---|
| 容器 | `left:0;top:0;width:1024px;height:58px`；背景 `linear-gradient(180deg,var(--topbar),var(--bg))`；`border-bottom:1px solid var(--line)`；`display:flex;align-items:center;padding:0 22px;z-index:5` |
| `.logo` | 34×34，圆角 9，背景 `linear-gradient(135deg,var(--blue),var(--purple))`；内白**实心**音符 `#i-note` 22×22；`margin-right:12px` |
| `.sys-name` | 文字 **`AIR KTV`**，19px / 700 / 字距 1px；其下 `<small>` 16px 灰字，**当前源码内容为空**（不要填字） |
| `.top-right` | `margin-left:auto;display:flex;align-items:center;gap:18px` |
| `.clockbox` | `display:flex;align-items:center;gap:10px;white-space:nowrap`；**日期在左、时间在右，左右平齐**（不是上下） |
| `#date` | 16px，`var(--sub)`；初值 `----`，运行后 `YYYY-MM-DD 星期X`（如 `2026-11-18 星期三`） |
| `#clock` | 20px / 700 / 字距 1px，`line-height:1`；初值 `00:00:00`，运行后 `HH:MM:SS` |
| `.room` | 背景 `var(--card)`，`border:1px solid var(--line)`，圆角 16，`padding:6px 14px`，16px `var(--sub)`；文案 **`包厢 VIP 088`**，其中 `VIP 088` 为 `<b>`，颜色 `var(--cyan)` |

### 3.3 侧栏 `#sidebar`（对应截图最左一列 5 个彩色按钮）

| 属性 | 值 |
|---|---|
| 容器 | `left:0;top:58px;width:124px;bottom:84px`；背景 `linear-gradient(180deg,var(--nav),var(--bg))`；`border-right:1px solid var(--line)`；`padding:14px 16px 0 8px`；`display:flex;flex-direction:column;align-items:flex-end`；`z-index:4` |
| `.nav` 按钮 | 100×74，圆角 16，纵向排列，间距 `gap:4px`，`margin-bottom:9px`；底色透明，文字 `var(--sub)`，cursor pointer；`transition .15s` |
| `.nav .ni` 图标块 | 44×44，圆角 14，背景取各有 `--nc` 渐变，内图标 26×26 / `stroke-width:2` / 纯白；`box-shadow:0 6px 14px rgba(0,0,0,.3)` |
| `.nav-txt` | 17px / 700 |
| hover | 按钮底色 `var(--card2)`、文字 `var(--text)`、`translateY(-2px)` |
| 选中 `.active` | 按钮底 `linear-gradient(180deg,rgba(71,123,255,.26),rgba(123,97,255,.10))`；边框 `rgba(71,123,255,.42)`；发光见 2.5；图标块额外发光 |
| **对齐硬要求** | 5 个按钮**右对齐**排列，按钮**外框右边缘**落在 x≈107，对准顶栏 `AIR` 与 `KTV` 之间的缝隙（x≈108）；不得对齐内部图标中心 |
| `.nav-foot` | `display:none`（隐藏，不要显示包厢信息） |

**5 个按钮逐项（从上到下）**：

| 序 | data-nav | 文案 | 图标 symbol | `.ni` 背景渐变（135°） |
|---|---|---|---|---|
| 1 | `home` | 推荐 | i-home | `linear-gradient(135deg,#477BFF,#7B61FF)` 科技蓝 |
| 2 | `category` | 点歌 | i-cat | `linear-gradient(135deg,#7B61FF,#B98CFF)` 梦幻紫 |
| 3 | `search` | 搜索 | i-search | `linear-gradient(135deg,#19D5D0,#477BFF)` 青→蓝 |
| 4 | `ordered` | 已点 | i-list | `linear-gradient(135deg,#19A7CE,#19D5D0)` 深青→青 |
| 5 | `settings` | 设置 | i-set | `linear-gradient(135deg,#F2994A,#F45C43)` 橙→橙红 |

### 3.4 舞台与页面容器

| 元素 | 规格 |
|---|---|
| `#stage` | `left:124px;top:58px;right:0;bottom:0;overflow:hidden;z-index:1` |
| `.page` | `position:absolute;left:0;top:0;right:0;bottom:84px;padding:14px 16px;overflow:hidden;display:none`；`.page.active` 时 `display:block` |
| `.phead` 页面头 | `height:30px;margin-bottom:10px;display:flex;align-items:center` |
| `.pback` 返回键 | 34×34，圆角 9，背景 `var(--card)`，`border:1px solid var(--line)`，18×18 的 `i-back`，`margin-right:10px`；**首页不显示返回键**，其余页均显示且 `data-nav="home"` |
| 头部蓝竖条 | 4×18，圆角 2，`var(--blue)`，`margin-right:10px` |
| 头部标题 h2 | 19px / 700，渐变文字（见 2.6） |
| 头部描述 | 16px `var(--sub)`，`margin-left:12px` |
| 头部右侧 | `margin-left:auto`，16px `var(--sub)` |

> 九个页面头部文案速查（标题 / 描述 / 右侧）：
> 首页 `欢迎光临 / 今晚尽兴欢唱 / 点击磁贴开始欢唱`；分类 `歌曲分类 / 按风格与语种选歌 / 共 36 首歌曲`；歌手 `歌手分类 / 按歌手查找歌曲 / 华语 / 欧美 / 日韩`；搜索 `歌曲搜索 / 输入歌名 / 歌手 / 拼音首字母 / （无）`；已点 `已点歌曲 / 点歌队列管理 / 按点歌顺序演唱`；排行 `排行榜 / 大家都在点 / 数据为模拟展示`；歌单 `歌单推荐 / 按场景挑选歌单 / 共 6 个精选歌单`；播放 `正在播放 / 大功率高清音效 / 专业 KTV 控制台`；设置 `系统设置 / 参数调节与设备信息 / （无）`。

### 3.5 迷你播放条 `#mini`（对应所有截图最下方横跨全宽的条）

| 序 | 元素 | 精确规格 |
|---|---|---|
| — | 容器 | `left:0;right:0;bottom:0;height:84px`；背景 `var(--mini)`；`border-top:1px solid var(--line)`；`display:flex;align-items:center;gap:12px;padding:0 20px;z-index:3` |
| 1 | `.mcover` | 64×64，圆角 10；JS 动态写入背景 `linear-gradient(135deg, GRADIENTS[当前歌曲][0], GRADIENTS[当前歌曲][1])`，居中大号首字 28px / 800 白字 |
| 2 | `.mmeta` | 宽 170；歌名 `#mname` 20px/700 渐变文字，歌手 `#martist` 16px→**18px** `var(--sub)`，`margin-top:4px` |
| 3 | `.mctrl` | `display:flex;align-items:center;gap:18px;margin-left:12px` |
| 3a | 上一首 `.mc[data-act=prev]` | **52×52 实心圆**；背景 `linear-gradient(135deg,#FFB33D,#F57C24)`（橙色）；图标 `i-prev` 28×28，颜色 **`#0D1424` 深色**；`box-shadow:0 4px 12px rgba(245,124,36,.35)`；hover `brightness(1.12)` |
| 3b | 播放/暂停 `.mc.main[data-act=toggle]` | **58×58 实心圆**；背景 `var(--blue)`；图标 32×32 `i-pause`/`i-play`，颜色 `#0D1424` |
| 3c | 下一首 `.mc[data-act=next]` | 同 3a，`i-next` |
| 4 | `.mbar[data-act=seek]` | `flex:1;min-width:110px;height:10px;border-radius:5px;background:var(--track);cursor:pointer;overflow:hidden`；填充 `.mfill` `linear-gradient(90deg,var(--blue),var(--cyan))`；末端手柄 14px 橙黄圆点（见 5.4） |
| 5 | `.mtime` | 16px `var(--sub)`，宽 104 固定，居中 nowrap；文案 `当前 / 总时长`，如 `01:27 / 4:16` |
| 6 | `.mfunc[data-act=funcPop]` | 蓝紫玻璃药丸：背景 `linear-gradient(135deg,rgba(71,123,255,.28),rgba(123,97,255,.2))`，`border:1px solid rgba(71,123,255,.45)`，圆角 10，`padding:9px 12px`，16px `var(--text)`；内 `i-set` 图标 22×22 `var(--cyan)` + 文字 **`功能`** |
| 7 | `.mcnt[data-nav=ordered]` | 背景 `var(--card)`，圆角 10，`padding:9px 12px`，16px `var(--sub)`；文案 **`已点 <b>{n}</b> 首`**，数字 `var(--cyan)` |

> 截图中迷你条从左到右实际观感：蓝色封面方块（首字）→ 渐变歌名+歌手 → 橙圆上一首 / 蓝圆暂停 / 橙圆下一首 → 蓝青进度条 → `01:27 / 4:16` → 蓝色「功能」→「已点 9」。

### 3.6 快捷功能浮层 `.func-pop`（点「功能」弹出）

- `left:50%;bottom:210px;transform:translateX(-50%);width:620px`；背景 `var(--toast-bg)`；`border:1px solid var(--line)`；圆角 16；`padding:16px`；`box-shadow:0 16px 40px var(--shadow)`；`z-index:20`；`.show` 时显示。
- 标题行 `.fp-head`：**`快捷功能`**（19px/800）+ 右侧关闭 `✕`（20px `var(--sub)`，`data-act=funcClose`）；`margin-bottom:12px`。
- 内容：复用第 7.8 节 8 个功能磁贴，两行每行 4 个；此处 `.fcard` 高 62、行间距 10。

### 3.7 Toast `#toast`

- `left:50%;bottom:112px`；`background:var(--toast-bg)`；`border:1px solid var(--blue)`；圆角 30；`padding:16px 34px`；**22px / 700**；`z-index:20`；nowrap；`box-shadow:0 8px 24px rgba(0,0,0,.4)`。
- 显示：`.show` → `opacity:1;transform:translateX(-50%) translateY(0)`；0.2s 淡入淡出，**1.8 秒后自动消失**（`toast(msg)`）。

### 3.8 弹窗外壳

| 元素 | 规格 |
|---|---|
| `.modal-mask` | `inset:0;background:rgba(4,8,20,.6);z-index:28`；点击关闭（`data-act=modalClose`） |
| `.modal` | 居中 `left:50%;top:50%;transform:translate(-50%,-50%)`；宽 520；背景 `var(--toast-bg)`；`border:1px solid var(--line)`；圆角 18；`padding:18px 20px 20px`；`box-shadow:0 24px 60px var(--shadow)`；`z-index:29` |
| `.modal-head` | `margin-bottom:16px;justify-content:space-between` |
| `.modal-title` | 19px/800，渐变文字（同 2.6） |
| `.modal-x` | 关闭 `✕`，32×32 圆角 8，20px `var(--sub)`，hover 底色 `var(--card2)` |
| `.modal-body` | `display:flex;flex-direction:column;gap:16px` |

### 3.9 亮度遮罩 `#dim`

- `inset:0;background:rgba(0,0,0, (100-brightness)/250)`；`pointer-events:none;z-index:8`。
- 亮度 100 时透明度 0（不影响画面）；亮度 0 时约 0.4。

---

## 4. 图标库（SVG `<symbol>`，35 个，全部内嵌）

- 定义容器：`<svg style="position:absolute;width:0;height:0;overflow:hidden" aria-hidden="true">`。
- 所有 symbol `viewBox="0 0 24 24"`，路径见源码 455–489 行，**不得改写路径**。
- 构造：`function ic(id,cls){return '<svg class="ic '+(cls||'')+'"><use href="#i-'+id+'"/></svg>';}`

| ID | 图形 | 用途 | ID | 图形 | 用途 |
|---|---|---|---|---|---|
| i-note | 双音符 | logo/封面/背景 | i-home | 房屋 | 侧栏推荐 |
| i-cat | 四宫格 | 侧栏点歌/首页磁贴 | i-artist | 人像 | 首页歌手磁贴 |
| i-search | 放大镜 | 侧栏/搜索/首页磁贴 | i-list | 列表 | 侧栏已点/首页磁贴 |
| i-rank | 领奖台 | 首页榜单磁贴 | i-playlist | 列表+音符 | 首页歌单磁贴 |
| i-playing | 圆中播放 | 首页正在播放磁贴 | i-set | 齿轮 | 侧栏设置/首页磁贴/功能键 |
| i-play | 三角 | 播放按钮 | i-pause | 双竖条 | 暂停按钮 |
| i-prev | 上一个 | 上一首 | i-next | 下一个 | 下一首/切歌 |
| i-plus | 加号 | 所有加歌按钮 | i-trash | 垃圾桶 | 删除/清空 |
| i-pin | 图钉 | 置顶 | i-vol | 喇叭 | 音量行/设置卡 |
| i-clock | 时钟 | （备用） | i-fire | 火焰 | 空调制热 |
| i-star | 星星 | 主题卡标题 | i-back | 左尖括号 | 返回/空调左箭头 |
| i-check | 对勾 | 快捷操作卡标题 | i-moon | 月牙 | 深色模式 |
| i-sun | 太阳 | 浅色模式 | i-info | 信息圈 | 系统信息卡标题 |
| i-replay | 重播箭头 | 重唱 | i-mic | 麦克风 | 原唱/麦克风音量 |
| i-mute | 静音喇叭 | 静音 | i-eq | 均衡器 | 调音 |
| i-control | 滑杆 | 空调 | i-atmos | 灯泡 | 气氛 |
| i-snow | 雪花 | 制冷 | i-wind | 风 | 送风/风速 |
| i-drop | 水滴 | 除湿 | — | — | — |

---

## 5. 通用组件规格

### 5.1 封面 `cover(i,size,label,fill)`

- 取 `GRADIENTS[i % 18]` 双色；`border-radius:10px`；`background:linear-gradient(135deg,c0,c1)`。
- 内三层：① `.cv-glow` 左上径向高光 `radial-gradient(circle at 28% 22%, c0+'aa', transparent 62%)`；② `.cv-pattern` 取 `PATTERNS[i % 8]`，`viewBox 0 0 100 100`，铺满；③ `.cv-mark` 居中汉字 `label`（默认 `♪`），字号 `max(16, round(size*0.34))`、白色 `.96`、`font-weight:800`、`text-shadow:0 2px 10px rgba(0,0,0,.35)`。
- `fill=true` 时右下角追加 20×20 的白色半透明 `i-note`。
- 外层 `.cover:after` 斜向高光见 2.5。

### 5.2 加歌按钮 `.addbtn`

- 40×40 默认，圆角 10，背景 `var(--blue)`，白色 `i-plus` 20×20；hover `var(--blue-hover)`。
- 各页面会覆盖尺寸：歌曲卡 34×34、结果行 32×32、榜单 38×38、歌单行 36×36、首页横幅 44×44。

### 5.3 胶囊/按钮/选中

| 组件 | 规格 |
|---|---|
| `.chip` | `border:1px solid var(--line);background:var(--card);color:var(--sub)`；圆角 18；`padding:8px 16px`；16px；hover 文字 `var(--text)`、边框 `var(--blue)` |
| `.chip.on` | 背景 `var(--blue)`、白字、边框 `var(--blue)` |
| `.btn` | 无边框，圆角 9，`padding:0 18px`，高 40，16px 白字，背景 `var(--blue)`，内图标 18×18 |
| `.btn.ghost` | 背景 `var(--card)`、文字 `var(--sub)`、边框 `1px solid var(--line)`；hover 文字 `var(--text)` |
| `.sel` 选中歌曲 | `outline:2px solid var(--cyan);outline-offset:-2px` |

### 5.4 滑块与手柄

| 组件 | 规格 |
|---|---|
| `.pbar` 播放进度 | 高 8，圆角 4，`var(--track)`；填充 `.pbar-fill` `linear-gradient(90deg,var(--blue),var(--cyan))` |
| `.vtrack` 播放页音量 | 宽 240，高 8，圆角 4；填充 `.vfill` 纯 `var(--cyan)`；`overflow:hidden` |
| `.track` 设置页滑条 | 高 10，圆角 5；填充 `.fill` `linear-gradient(90deg,var(--blue),var(--cyan))` |
| `.mt` 弹窗滑条 | 高 12，圆角 6；填充 `.mf` 同上蓝青渐变 |
| `.mbar` 迷你条进度 | 见 3.5；填充 `.mfill` 同 `.pbar-fill` |
| **手柄（仅 pbar/vfill/mfill/fill）** | `:after` 定位在填充末端 `right:-7px;top:50%`，14×14 圆，`background:#FFB733;border:2px solid #FF9A3D`，`box-shadow:0 2px 7px rgba(0,0,0,.35)`，`translateY(-50%)`；**只要橙黄色，不要白色内芯** |
| `touch-action` | 所有滑块 `touch-action:none`；`pointerdown` 即按比例设值并持续拖动（`SLIDER_ACTS=seek,volume,setVol,setBri,pitch,micVol`） |

### 5.5 自定义滚动条（列表上那条蓝色可拖的线）

- `.yscroll`：`overflow-y:auto;overflow-x:hidden`；原生滚动条隐藏（`scrollbar-width:none!important` 及 `::-webkit-scrollbar{width:0!important}`）。
- `setupScrollBars()` 给每个 `.yscroll` 包一层 `.sb-wrap`（`position:relative;display:flex;min-height:0`），右侧加 `.sb-track`（宽 12，`margin-left:4px`，圆角 6，**背景透明**）+ `.sb-thumb`（宽 10，`left:1px`，圆角 5，背景 `var(--blue)`，`min-height:30px`，`box-shadow:0 0 10px rgba(71,123,255,.35)`）。
- 滑块高度 `max(30, clientHeight²/scrollHeight)`；内容不足时整个轨道 `display:none`。
- **只显示一条蓝色滑块，没有灰色轨道**。
- 交互：`pointerdown` 后计时 **350ms**，`holding` 仍为真才 `active=true` 并变 `var(--cyan)`、光标 grabbing；短按抬起不滚动；拖动按比例换算 `scrollTop`。

---

## 6. 数据模型（全部内嵌，逐值照抄）

### 6.1 `SONGS`（36 首）

字段：`n` 歌名、`a` 歌手、`d` 时长、`c` 分类数组、`l` 拼音首字母。

| # | 歌名 | 歌手 | 时长 | 分类 | 首字母 |
|---|---|---|---|---|---|
| 0 | 孤勇者 | 陈奕迅 | 4:16 | 流行歌曲/影视金曲/网络热歌 | G |
| 1 | 晴天 | 周杰伦 | 4:29 | 华语歌曲/经典老歌/流行歌曲 | Q |
| 2 | 海阔天空 | BEYOND | 5:26 | 粤语歌曲/经典老歌 | H |
| 3 | Shape of You | Ed Sheeran | 3:53 | 欧美歌曲/流行歌曲 | S |
| 4 | 起风了 | 买辣椒也用券 | 5:23 | 网络热歌/流行歌曲 | Q |
| 5 | 富士山下 | 陈奕迅 | 4:18 | 粤语歌曲/经典老歌 | F |
| 6 | 夜曲 | 周杰伦 | 3:48 | 华语歌曲/经典老歌 | Y |
| 7 | Dynamite | BTS | 3:19 | 日韩歌曲/流行歌曲 | D |
| 8 | 月亮代表我的心 | 邓丽君 | 3:29 | 经典老歌/华语歌曲 | Y |
| 9 | 可能 | 程响 | 4:12 | 网络热歌/流行歌曲 | K |
| 10 | 红日 | 李克勤 | 4:40 | 粤语歌曲/经典老歌 | H |
| 11 | Perfect | Ed Sheeran | 4:21 | 欧美歌曲/影视金曲 | P |
| 12 | 稻香 | 周杰伦 | 3:43 | 华语歌曲/流行歌曲 | D |
| 13 | 天花乱坠 | 郑秀文 | 3:35 | 粤语歌曲 | T |
| 14 | First Love | 宇多田光 | 4:18 | 日韩歌曲/经典老歌 | F |
| 15 | 演员 | 薛之谦 | 4:21 | 华语歌曲/流行歌曲 | Y |
| 16 | My Heart Will Go On | Celine Dion | 4:39 | 欧美歌曲/影视金曲 | M |
| 17 | 光辉岁月 | BEYOND | 4:58 | 粤语歌曲/经典老歌 | G |
| 18 | 芒种 | 音阙诗听 | 3:32 | 网络热歌 | M |
| 19 | Love Story | Taylor Swift | 3:55 | 欧美歌曲/流行歌曲 | L |
| 20 | 青花瓷 | 周杰伦 | 3:58 | 华语歌曲/经典老歌 | Q |
| 21 | K歌之王 | 陈奕迅 | 5:22 | 粤语歌曲/经典老歌 | K |
| 22 | 大鱼 | 周深 | 4:36 | 影视金曲/华语歌曲 | D |
| 23 | Bad Guy | Billie Eilish | 3:14 | 欧美歌曲/流行歌曲 | B |
| 24 | 朋友 | 周华健 | 4:13 | 经典老歌/华语歌曲 | P |
| 25 | 向云端 | 小霞 / 海洋Bo | 4:25 | 网络热歌 | X |
| 26 | 童话 | 光良 | 4:02 | 华语歌曲/经典老歌 | T |
| 27 | See You Again | Wiz Khalifa | 3:49 | 欧美歌曲/影视金曲 | S |
| 28 | 听海 | 张惠妹 | 4:56 | 华语歌曲/经典老歌 | T |
| 29 | 奢香夫人 | 凤凰传奇 | 4:35 | 网络热歌/流行歌曲 | S |
| 30 | Lemon | 米津玄师 | 4:17 | 日韩歌曲 | L |
| 31 | 吻别 | 张学友 | 5:12 | 华语歌曲/经典老歌 | W |
| 32 | 小幸运 | 田馥甄 | 4:22 | 影视金曲/流行歌曲 | X |
| 33 | 摇太阳 | 凤凰传奇 | 3:58 | 网络热歌 | Y |
| 34 | Yesterday | The Beatles | 2:05 | 欧美歌曲/经典老歌 | Y |
| 35 | 静夜思 | 李荣浩 | 4:08 | 华语歌曲/流行歌曲 | J |

### 6.2 `ARTISTS`（18 位，字段 n=姓名 t=类型 c=歌曲数 l=首字母）

周杰伦(男,42,Z)、陈奕迅(男,38,C)、邓丽君(女,31,D)、BEYOND(组合,26,B)、张学友(男,35,Z)、Ed Sheeran(男,19,E)、Taylor Swift(女,24,T)、BTS(组合,22,B)、薛之谦(男,28,X)、张惠妹(女,20,Z)、凤凰传奇(组合,18,F)、光良(男,15,G)、宇多田光(女,12,Y)、米津玄师(男,11,M)、周深(男,23,Z)、田馥甄(女,16,T)、Billie Eilish(女,14,B)、李荣浩(男,21,L)。

### 6.3 其他数据

- `CATS`（8）：华语歌曲、粤语歌曲、欧美歌曲、日韩歌曲、经典老歌、流行歌曲、网络热歌、影视金曲。
- `PLAYLISTS`（6）：经典怀旧(88,「那些年，我们一起听过的旋律」)、流行热歌(126,「当下最火的流行金曲」)、情歌对唱(64,「适合双人合唱的浪漫曲目」)、派对嗨歌(97,「点燃全场的动感节奏」)、欧美金曲(75,「经典英文歌精选」)、粤语经典(58,「港乐黄金年代代表作」)。
- `RANKS`（4 榜 × 8 首，值为 SONGS 索引）：热门点唱榜 `[0,1,4,2,15,8,12,22]`；新歌榜 `[25,9,18,31,33,30,20,5]`；飙升榜 `[26,4,9,0,35,14,29,19]`；经典金曲榜 `[8,2,6,24,32,1,34,16]`。
- `HOT`（8）：孤勇者、起风了、晴天、海阔天空、可能、芒种、稻香、向云端。
- `RECENT`（3）：演员、红日、小幸运。

### 6.4 `GRADIENTS`（18 组封面双色渐变，按索引循环取用）

| # | 起色 → 终色 | # | 起色 → 终色 |
|---|---|---|---|
| 0 | #477BFF → #7B61FF | 9 | #0F2027 → #2C5364 |
| 1 | #19D5D0 → #3B82F6 | 10 | #FF512F → #DD2476 |
| 2 | #F857A6 → #FF5858 | 11 | #3A1C71 → #D76D77 |
| 3 | #F7B733 → #FC4A1A | 12 | #1D976C → #93F9B9 |
| 4 | #11998E → #38EF7D | 13 | #C33764 → #1D2671 |
| 5 | #8E2DE2 → #4A00E0 | 14 | #F2994A → #F2C94C |
| 6 | #00C6FF → #0072FF | 15 | #5F2584 → #C06C84 |
| 7 | #EE0979 → #FF6A00 | 16 | #2B5876 → #4E4376 |
| 8 | #4568DC → #B06AB3 | 17 | #EB3349 → #F45C43 |

### 6.5 `PATTERNS`（8 种封面图案，按索引循环）

1. 唱片纹：三个同心圆（r=30/18/7，cx=72,cy=28），白描边 + 中心实心。
2. 双波浪：两条填充白色 10% 的 Q 曲线（y≈68 / 80）。
3. 斜线：三条 9px 宽斜线（−10,100→55,−10 等）。
4. 圆点：一大圆（cx=80,cy=22,r=26）白 12% + 一大圆（cx=18,cy=88,r=34）黑 14%。
5. 同心圆：r=34/25/16/5，白色描边递减 + 中心实心。
6. 音符：白色圆头音符路径 + 两个圆点。
7. 星芒：四角星路径 + 中心圆，白色 14%/24%。
8. 三线波浪：三条 `M0 30 Q25 12 50 30 T100 30` 式路径，白色 14%。

### 6.6 `PINYIN`

常用拼音音节 → 候选汉字表（约 250 个音节，每音节 1–20 字），用于中文候选。**完整逐条数据见附录 A，必须逐字照抄，不得增删。**
匹配规则：先按完整音节精确取候选；无果则取所有以该拼音开头音节的候选合并（最多 24 个）；再无果则回退拼音本身。

### 6.7 初始状态 `state`（初值必须一致）

| 字段 | 初值 | 字段 | 初值 |
|---|---|---|---|
| page | `home` | selected | `-1` |
| cat | `0` | artistFilter / artistLetter | `全部` / `全部` |
| ordered | `[{i:0,playing:true},{i:2},{i:12},{i:8},{i:5},{i:6},{i:24},{i:14},{i:19}]`（9 首，其余 playing:false） | playIndex | `0` |
| playing / progress | `true` / `34` | volume / brightness | `64` / `100` |
| mute / origin / atmos | `false` / `false` / `false` | pitch / micVol | `50` / `70` |
| acTemp / acOn | `24` / `true` | acMode / acFan | `cool` / `auto` |
| theme / mode | `blue` / `dark` | rank / plDetail | `热门点唱榜` / `-1` |
| query | `''` | kbSym / kbLower | `false` / `false` |
| ime / pinyin / candPage | `cn` / `''` / `0` | eqOpen / acOpen | `false` / `false` |

> `ordered` 初始顺序即切歌顺序：孤勇者 → 海阔天空 → 稻香 → 月亮代表我的心 → ……

---

## 7. 九个页面逐元素规格

### 7.1 首页 `p-home`（`renderHome`）— 对应截图 2

```
头部：欢迎光临 | 今晚尽兴欢唱 | 点击磁贴开始欢唱
├─ 今日主打横幅（整宽 × 96）
├─ 快捷入口标题行
└─ 磁贴大厅 4列×2行（8 个彩色大按钮）
```

**① 今日主打横幅** `.feature[data-song="0"]`
- `width:100%;height:96px;margin-bottom:14px; border-radius:14px; padding:11px`；
- 背景 **`linear-gradient(120deg,#1E3A8A,#4C1D95 60%,#831843)`**（深蓝→紫→玫红）；
- `color:#FFFFFF`；`box-shadow:0 10px 26px rgba(30,20,80,.35), inset 0 1px 0 rgba(255,255,255,.14)`；
- `:before` 右上 200×200 白色径向高光 `rgba(255,255,255,.20)` 渐隐；`:after` 右下超大 `♫` 水印，96px，`rgba(255,255,255,.07)`。
- 左侧封面 `cover(0,92,'孤',true)`（92×92，圆角 12）。
- 右侧信息区 `margin-left:14px`：
  - 标签 **「今日主打」**：背景 `var(--cyan)`、字色 `#06121A`、16px/700、`padding:3px 8px`、圆角 4、`margin-bottom:6px`。
  - 歌名 **「孤勇者」**：20px/800，渐变文字。
  - 副行 **「陈奕迅　·　高品质曲库，一键点唱」**：16px `#D8DFF0`，`margin-top:5px`。
- 右下加号 `.addbtn.fadd`：44×44，`data-act=add data-i=0`。
- **整块可点**（选中高亮）；点空白选中该歌，点加号加歌。

**② 快捷入口标题** `.sec-title`
- 高 20，`margin-bottom:6px`；青色 6px 圆点 + 标题 **「快捷入口」**16px/700（渐变文字）+ 右侧 **「常用功能一屏直达」**16px `var(--sub)`。

**③ 磁贴大厅** `.tile-grid`
- `display:grid;grid-template-columns:repeat(4,1fr);grid-template-rows:repeat(2,1fr);gap:14px;height:calc(100% - 182px)`。
- 每块 `.tile`：圆角 18，白字，纵向居中 `gap:10px`，`box-shadow:0 10px 24px var(--shadow)`，hover 上浮 4px；`:before` 右上 180×180 白色 12% 圆；`:after` 左下 120×120 白色 14% 描边圆环。
- 图标底 `.tic`：66×66，圆角 18，背景 `rgba(255,255,255,.20)`，内图标 36×36 / `stroke-width:1.6` / 白；内阴影 `inset 0 1px 0 rgba(255,255,255,.3)`。
- 标题 `.tt`：20px/800/字距 1；副标题 `.td`：16px/`opacity:.85`。

**8 块磁贴逐项（顺序：先第一行左→右，再第二行左→右）**：

| # | data-nav | 主标题 | 副标题 | 图标 | 背景渐变（135°） |
|---|---|---|---|---|---|
| 1 | category | 歌名点歌 | 按曲风选歌 | i-cat | #477BFF → #5B8CFF |
| 2 | artist | 歌手点歌 | 按歌手找歌 | i-artist | #7B61FF → #B98CFF |
| 3 | search | 全能搜索 | 歌名 / 歌手 | i-search | #19A7CE → #19D5D0 |
| 4 | rank | 热门榜单 | 大家都在唱 | i-rank | #F2994A → #F45C43 |
| 5 | playlist | 精选歌单 | 场景推荐 | i-playlist | #EE0979 → #F857A6 |
| 6 | ordered | 已点歌曲 | **`{已点数} 首待唱`**（动态） | i-list | #0EA5A0 → #38D6A0 |
| 7 | playing | 正在播放 | 播放控制 | i-playing | #4568DC → #7B61FF |
| 8 | settings | 系统设置 | 主题 / 音量 | i-set | #64748B → #94A3B8 |

> 截图对应：第一排 蓝 / 紫 / 青 / 橙，第二排 玫红 / 青绿 / 蓝紫 / 灰蓝；每块中间是半透明白圆角方块包白色图标，下方两行白字。

### 7.2 歌曲分类 `p-category`（`renderCategory`）— 对应截图 3

```
头部：歌曲分类 | 按风格与语种选歌 | 共 36 首歌曲
├─ 左列：8 个分类按钮（竖排）
└─ 右区：3×3 歌曲卡片（每卡 封面+歌名+歌手·时长+加号）
```

- 容器 `.split`：`display:flex;gap:12px;height:calc(100% - 40px)`。
- **左列** `.cat-col`：宽 104，纵向 `gap:7px`。
  - `.cat-item`：高 44，圆角 10，背景 `var(--card)`，`border:1px solid var(--line)`，`padding:0 12px`，16px `var(--sub)`，nowrap。
  - 选中 `.on`：背景 `linear-gradient(90deg,rgba(71,123,255,.3),rgba(123,97,255,.12))`，文字 `var(--text)`，边框 `rgba(71,123,255,.5)`。
  - 8 项自上而下：**华语歌曲、粤语歌曲、欧美歌曲、日韩歌曲、经典老歌、流行歌曲、网络热歌、影视金曲**；`data-act=cat data-i=0..7`。截图中选中「华语歌曲」。
- **右区** `.grid-right`：`flex:1;min-width:0`；`.cat-grid` 为 3 列、`grid-auto-rows:120px`、`gap:9px`、`align-content:start`、`height:100%`、`padding-right:8px`。
  - 卡片 `.cat-song`：120px 高，圆角 12，背景 `var(--card)`，`border:1px solid var(--line)`，`padding:8px`；hover `var(--card2)`。
  - 内容：`cover(i,60,首字,true)`（60×60）+ 歌名 `.song-name` 16px/600（右留 40px）+ 歌手·时长 `.song-artist` 16px `var(--sub)`（格式 `周杰伦 · 4:29`）。
  - 加号：右下 `right:8px;bottom:8px`，34×34 圆角 9，`data-act=add data-i`。
  - 只显示当前分类前 **9 首**（不足 9 首时回退显示索引 0–7）；点卡片空白选中（青色描边）。
  - **卡片从顶部依次贴紧排列，行高固定 120px，不留大块空白**。

### 7.3 歌手分类 `p-artist`（`renderArtist`）

- 头部：歌手分类 | 按歌手查找歌曲 | 华语 / 欧美 / 日韩。
- **筛选行** `.filterbar`：`display:flex;gap:8px;margin-bottom:12px;flex-wrap:wrap`。
  - 标签 **「歌手类型」**：16px `var(--sub)`。
  - 4 个胶囊 `.chip`：**全部 / 男 / 女 / 组合**，`data-act=af data-v`，选中 `.on` 蓝底白字。
  - A–Z 字母条 `.abc`（`margin-left:8px;gap:4px`）：首字母 **「全部」** 宽 44，其余 26 个字母各 26×26，圆角 6，背景 `var(--card)`、字 `var(--sub)` 16px；hover/选中 `.on` 背景 `var(--blue)`、白字；`data-act=al data-v`。
- **歌手网格** `.artist-grid`：6 列，`gap:10px`，`align-content:start`；`#p-artist .artist-grid` 高 `calc(100% - 116px)`、`padding-right:8px`，可滚动（自定义滚动条）。
  - 卡片 `.artist-card`：背景 `var(--card)`，圆角 12，`border:1px solid var(--line)`，`padding:10px 8px`，居中；`cover(idx+5,78,首字)` 圆形 78px，下 `margin-bottom:8px`。
  - 歌手名 `.an` 16px/600 渐变文字；下方 `.ac` 16px `var(--sub)` 文案 **`{c} 首歌曲`**。
  - 点击卡片 `data-act=artist` → toast「{歌手} · 共 {c} 首可点歌曲」。
  - 无结果时整行提示「暂无 X 开头的歌手，换个字母试试」。
  - 按「类型 + 首字母」双重筛选；点字母后列表滚回顶部。

### 7.4 搜索 `p-search`（`renderSearch`）— 对应截图 4

```
头部：歌曲搜索 | 输入歌名 / 歌手 / 拼音首字母
├─ 搜索栏：[放大镜 输入框 中文胶囊] [搜索按钮]
└─ 主体：[左 搜索结果框]  [右 键盘(候选栏 + 3 行按键)]
```

**① 搜索栏** `.searchbar`：`display:flex;gap:10px;margin-bottom:12px`。
- `.search-input`：`flex:1;height:48px;background:var(--input);border:1px solid var(--line);border-radius:10px;padding:0 14px;gap:10px`；左侧放大镜 20px `var(--sub)`；`input#sinput` 透明无边框、16px `var(--text)`、占位符 **「输入歌名 / 歌手 / 拼音」**（`var(--placeholder)`）。
- `.ime-pill[data-act=ime]`：高 32，最小宽 56，`padding:0 12px`，圆角 16，背景 `var(--func)`，字 `var(--cyan)` 16px/700；内容 **「中文」** 或 **「EN」**；hover 蓝底白字。
- 搜索按钮 `.btn[data-act=doSearch]`：高 48，`padding:0 26px`，蓝底白字 + 放大镜 + 文案 **「搜索」**。

**② 主体** `.search-body`：`display:flex;gap:12px;height:calc(100% - 100px)`。
- 左 `.result-box`：`flex:1;background:var(--card);border:1px solid var(--line);border-radius:12px;padding:10px 12px;overflow:hidden`。
  - 标题 **「搜索结果」**16px `var(--sub)`，`margin-bottom:6px`。
  - 结果行 `.result-row`：高 44，`gap:12px`，底边 1px `var(--line)`；序号 22px `var(--sub)` + `cover(i,32)` + 歌名 16px + 歌手 16px + 32×32 加号（`data-act=add`）；最多 4 条；hover 背景 `rgba(71,123,255,.08)`。
  - 无结果时居中提示 **「没有找到相关歌曲，换个关键词试试」**16px `var(--sub)`。
- 右 `.keyboard`：宽 **560**，`flex:none`，背景 `var(--nav)`，`border:1px solid var(--line)`，圆角 12，`padding:12px`，纵向排列，`align-self:center`。

**③ 候选栏** `.candbar`（键盘上方弹窗，对应截图 4 顶部那条）：
- 高 44，`margin-bottom:6px`，圆角 10，背景 `var(--card)`，`border:1px solid var(--line)`，`box-shadow:0 4px 14px var(--shadow)`。
- 左 `.cand-py`：最小宽 62，16px `var(--cyan)`/700/字距 1，右边框 1px `var(--line)`；显示当前拼音，无则显示 **「拼音」**。
- 左右箭头 `.cand-arrow`：36×44，22px/700 `var(--sub)`，文案 **`‹`** / **`›`**，`data-act=candPage data-v=-1/1`；hover 背景 `var(--op-hover)`、字 `var(--cyan)`。
- 中间 `.cand-list`：`flex:1`，`gap:2px`，`padding:0 4px`；每页 **8 个** `.cand-item`（19px/600，居中，flex:1），首个 `.on`（蓝紫渐变底白字：`linear-gradient(135deg,var(--blue),var(--purple))`），`data-act=cand data-v=汉字`；点选写入搜索框。
- 无拼音时显示 **「输入拼音后在这里选字」**16px `var(--placeholder)`。

**④ 键盘三行**（`.krow` 高 66、`gap:5px`、`margin-bottom:5px`；`.key` 高 100%、圆角 10、背景 `var(--card2)`、`border:1px solid var(--line)`、16px `var(--text)`；`.key.fp` 背景 `var(--func)`、字 `var(--cyan)`、`flex:1.5`；`.key.fw` `flex:2`；hover 蓝底白字）：

| 模式 | 第 1 行 | 第 2 行 | 第 3 行 |
|---|---|---|---|
| 中文/英文小写 | `1#`(SYM) Q W E R T Y U I O P 退格(DEL) | `中/EN`(IME) `abc/ABC` A S D F G H J K L 搜索(DO) | 空格(SPACE) Z X C V B N M 清空(CLEAR) |
| 符号（按 1#） | `中/EN`(IME) ABC 1 2 3 4 5 6 7 8 9 0 退格(DEL) | − / ; ( ) & @ . , ? 搜索(DO) | 空格 ! " : + * = _ 清空(CLEAR) |

- 中文模式下字母键自动小写并进入拼音缓冲（`state.pinyin`）；英文模式受 `kbLower` 控制大小写。
- `IME` 键切换中/英并清空拼音、候选页、符号模式；`ABC` 键在符号模式返回字母，否则切换大小写。
- `DEL` 中文模式先删拼音，拼音空才删已提交文字；`SPACE` 有拼音时提交首个候选，否则输入空格；`搜索(DO)` 有拼音先提交首候选，再 toast 命中数。

### 7.5 已点歌曲 `p-ordered`（`renderOrdered`）— 对应截图 5

```
头部：已点歌曲 | 点歌队列管理 | 按点歌顺序演唱
├─ 汇总条：已点 9 首 | 预计时长 37 分钟 | 当前演唱 孤勇者        [清空列表]
└─ 队列：5 行可见（可滚），每行 序号 封面 歌名/歌手 状态 置顶 删除
```

- **汇总条** `.sumbar`：高 56，`gap:26px`，背景 `var(--card)`，`border:1px solid var(--line)`，圆角 12，`padding:0 18px`，`margin-bottom:12px`。
  - `已点 <b>9</b> 首`、`预计时长 <b>37</b> 分钟`（`b` 为 20px `var(--text)`）；`当前演唱 <b style="color:var(--cyan)">孤勇者</b>`。
  - 右侧 `.btn.ghost[data-act=clearOrder]`：高 36，垃圾桶图标 + **「清空列表」**。预计时长 = 全部已点歌曲秒数求和 ÷60 四舍五入。
- **队列** `.order-list.yscroll`：`display:flex;flex-direction:column;gap:7px`；`#p-ordered .order-list` 高 `calc(100% - 100px)`、`padding-right:8px`，自定义滚动条。
  - `.order-row`：高 56，圆角 10，背景 `var(--card)`，`border:1px solid var(--line)`，`padding:0 12px`，`gap:12px`。
  - 正在播放行 `.playing`：背景 `linear-gradient(90deg,rgba(71,123,255,.18),var(--card))`，边框 `rgba(71,123,255,.45)`；序号变 `var(--cyan)`。
  - 每行从左到右：序号 `.num`（26 宽，16px/700 `var(--sub)`）+ `cover(i,42)`（圆角 7）+ 歌名 16px/600 + 歌手 16px `var(--sub)` + 状态胶囊 + 置顶 + 删除。
  - 状态 `.status`：16px，`padding:4px 10px`，圆角 12，背景 `var(--func)`、字 `var(--sub)`，文案 **「待唱」**；正在播放 `.status.on` 背景 `rgba(25,213,208,.16)`、字 `var(--cyan)`，文案 **「正在播放」**。
  - 置顶 `.op[data-act=pin]` 与删除 `.op.del[data-act=del]`：各 40×40，圆角 9，背景 `var(--card2)`，`border:1px solid var(--line)`，18px 图标 `i-pin`/`i-trash`，色 `var(--sub)`；hover 底色 `var(--op-hover)`，删除 hover 字色 `var(--del)`。
  - 空列表提示 **「点歌列表为空，去挑几首喜欢的歌吧」**16px `var(--sub)`。
- 置顶：非首位时移到队首并 toast；删除：移除并更新迷你条计数；清空：清空队列并计数归零。

### 7.6 排行榜 `p-rank`（`renderRank`）

- 头部：排行榜 | 大家都在点 | 数据为模拟展示。
- 榜单切换 `.tabs`：`display:flex;gap:10px;margin-bottom:12px`；4 个 chip：**热门点唱榜 / 新歌榜 / 飙升榜 / 经典金曲榜**，`data-act=rank data-v`。
- `.rank-list.yscroll`：`gap:6px`，高 `calc(100% - 91px)`，`padding-right:4px`，自定义滚动条（长按拖动）。
- `.rank-row`：高 **62px**，`flex:none`，圆角 11，背景 `var(--card)`，`border:1px solid transparent`，`padding:0 16px`，`gap:14px`；hover 边框 `var(--line)`。
  - 序号 `.rn`：34 宽，22px/800 `var(--sub)`；前三名分别 `.top1` `var(--rank1)` 金 `#FFD35C` / `.top2` `#C9D4E8` 银 / `.top3` `#E7A46B` 铜。
  - `cover(i,44)`（44×44，圆角 8）+ 歌名 18px/600 + 歌手 16px + 时长 16px `var(--sub)` + 38×38 加号（右下）。
  - **一屏约 5 首，8 首全部渲染，其余向下滚动**；加号 `data-act=add`。

### 7.7 歌单推荐 `p-playlist`（`renderPlaylist`）

**列表态**：
- 头部：歌单推荐 | 按场景挑选歌单 | 共 6 个精选歌单。
- `.pl-grid`：3 列 × 2 行，`gap:12px`，高 `calc(100% - 40px)`。
- `.pl-card`：圆角 14，背景 `var(--card)`，`border:1px solid var(--line)`，`padding:12px`，`gap:10px`，hover `var(--card2)`；`data-act=pl data-i`。
  - `cover(i+3,104,首字,true)`（104px，圆角 12）+ 信息区：歌单名 `.pn` 17px/700 渐变文字 + 描述 `.pd` 16px `var(--sub)` 两行截断（`line-clamp:2`，`line-height:1.4`）+ 青字 `.pc` 16px **`{c} 首歌曲 · 点击查看`**。

**详情态**（点卡片进入）：
- 返回行 `.backbtn[data-act=plBack]`：`i-back` 18px + **「返回歌单列表」**16px `var(--sub)`，`margin-bottom:10px`。
- 头部 `.pl-head`：`cover(plDetail+3,110)` + 歌单名 `.pn` 22px 渐变字 + 描述 16px `var(--sub)` `margin-top:8px` + 青字 **「共 {c} 首 · 精选推荐」**；`margin-bottom:14px`。
- `.pl-songs.yscroll`：`gap:6px`，`flex:1`，`padding-right:8px`，自定义滚动条，**宽度 100% 铺满页面、滑块贴最右**。
- `.pl-song`：高 58，`flex:none`，圆角 10，背景 `var(--card)`，`padding:0 14px`，`gap:12px`；`cover(i,40)`（圆角 6）+ 歌名 + 歌手 + 36×36 加号（`data-act=add`）。共 12 行，索引 `(歌单索引*4+k)%36`。

### 7.8 正在播放 `p-playing`（`renderPlaying`）— 对应功能磁贴截图

```
头部：正在播放 | 大功率高清音效 | 专业 KTV 控制台
├─ 上部：左侧大封面 + 右侧(歌名/歌手 / 进度条+时间 / 控制键 / 音量行)
├─ 功能磁贴：两行 × 4 个（共 8 个）
└─ 播放队列：「即将演唱」+ 1 首放大的待唱歌曲
```

**① 上部** `.play-top`：`height:158px;gap:16px;flex:none`。
- 封面 `.play-cover`：156×156，圆角 14，`cover(playIndex,156,首字,true)`，`box-shadow:0 12px 30px rgba(0,0,0,.3)`。
- 信息区 `.play-info`：`flex:1;min-width:0;flex-direction:column;justify-content:center;overflow:hidden`；**所有子元素 `flex:none` 禁止压缩**（防止歌名被挤裁切）。
  - 歌名 `.ptitle`：22px/800，`line-height:1.25`，渐变文字，单行省略。
  - 歌手行 `.partist`：16px `var(--sub)`，`line-height:19px`，文案 **`演唱：{歌手}　·　{时长}`**。
  - 进度 `.progress`：`margin-top:3px`；`.pbar` 高 8（见 5.4，`data-act=seek`）；时间行 `.ptime` 16px `var(--sub)`，`margin-top:3px`，左当前 `01:27`、右总时长 `4:16`。
  - 控制键 `.controls`：`gap:14px;margin-top:4px`；上一首 `.cbtn[data-act=prev]` 42×42、主播放 `.cbtn.main[data-act=toggle]` 48×48 蓝紫渐变实心白图标（26px）、下一首 `.cbtn[data-act=next]` 42×42；普通键背景 `var(--card)`、`border:1px solid var(--line)`、22px 图标。
  - 音量行 `.vol-row`：`gap:12px;margin-top:5px`；`i-vol` 图标 20px `var(--cyan)` + `.vtrack[data-act=volume]` 宽 240 + 百分比 `#vtxt` 16px `var(--sub)`。

**② 功能磁贴** `.func-panel`：`display:flex;flex-direction:column;gap:6px;flex:none`。
- `.func-row`：`display:grid;grid-template-columns:repeat(4,1fr);gap:8px`；共 **两行**（`funcCards()` 默认）。
- `.fcard`：高 48，圆角 11，背景 `linear-gradient(145deg,rgba(71,123,255,.14),rgba(123,97,255,.08))`，`border:1px solid var(--line)`，居中 `gap:9px`，`data-act=func data-v`；hover 上浮 2px、底色加深、发光。
- 图标块 `.fi`：42×42，圆角 12，背景取每项 `--nc` 渐变，内图标 **27×27**、白、`stroke-width:2`；`box-shadow:0 4px 10px rgba(0,0,0,.22)`。
- 文字 `.ft`：16px/600。
- 激活 `.fcard.on`：背景 `linear-gradient(145deg,rgba(249,154,61,.28),rgba(244,92,67,.16))`，边框 `rgba(249,154,61,.6)`（橙色高亮）。

**8 个功能磁贴逐项**：

| 行 | data-v | 文字（动态） | 图标 | 图标块渐变（135°） | 功能 |
|---|---|---|---|---|---|
| 1 | next | 切歌 | i-next | #477BFF → #7B61FF | 按已点顺序切下一首 |
| 1 | toggle | 播放（暂停时变为播放图标） | i-play/pause | #7B61FF → #B98CFF | 播放/暂停 |
| 1 | replay | 重唱 | i-replay | #19A7CE → #19D5D0 | 进度归零从头开始 |
| 1 | origin | 原唱（关时显示**伴唱**） | i-mic | #F857A6 → #FF5858 | 原唱/伴唱切换 |
| 2 | mute | 静音 | i-mute | #F2994A → #F45C43 | 静音开关 |
| 2 | eq | 调音 | i-eq | #11998E → #38EF7D | 打开/关闭调音弹窗 |
| 2 | control | 空调 | i-control | #477BFF → #19D5D0 | 打开/关闭空调弹窗 |
| 2 | atmos | 气氛 | i-atmos | #F7B733 → #FC4A1A | 气氛灯开关（激活橙色高亮） |

- 高亮判定：toggle→`playing`、mute→`mute`、origin→`origin`、atmos→`atmos`、eq→`eqOpen`、control→`acOpen`。

**③ 播放队列** `.queue`：
- `background:var(--card)`，`border:1px solid var(--line)`，圆角 12，`padding:8px 14px`，`flex:1;min-height:0;overflow:hidden;display:flex;flex-direction:column`。
- 标题 `.qt`：**「播放队列 · 即将演唱」**16px/600，`margin-bottom:4px`。
- **只显示一首待唱歌曲**（`.qrow.big`，高 **78px**）：
  - 背景 `var(--card2)`，圆角 10，`gap:14px`，`padding:0 6px`，无上边框。
  - 序号 `.qn` 26 宽，20px/700 `var(--cyan)`；`cover(next.i,56)` 圆角 8；歌名 20px/700；歌手 16px `margin-top:5px`；右侧 **「待唱」**16px `var(--cyan)`。
  - 待唱歌曲 = 当前播放歌曲在 `ordered` 中的下一首（位次按已点队列编号）；**不包含正在播放那首，且随切歌联动变化**。
  - 无待唱时显示 **「暂无待唱歌曲」**16px `var(--sub)` 居中。

### 7.9 系统设置 `p-settings`（`renderSettings`）— 对应截图 1、6

```
头部：系统设置 | 参数调节与设备信息
└─ 2×2 四张卡片：音量与亮度 / 主题风格 / 系统信息 / 快捷操作
```

- `.set-grid`：`display:grid;grid-template-columns:1fr 1fr;grid-template-rows:repeat(2,1fr);gap:12px;height:calc(100% - 40px)`。
- `.setcard`：背景 `var(--card)`，`border:1px solid var(--line)`，圆角 14，`padding:16px;overflow:hidden`。
- 卡片标题 `h3`：16px/700，`margin-bottom:14px`，`gap:9px`；图标 19×19 `var(--cyan)`。

**① 音量与亮度**（图标 `i-vol`）
- 两个 `.setrow`（`margin-bottom:16px`）：
  - 标签行 `.sl`：`display:flex;justify-content:space-between`，16px，左 **「系统音量」**、右 `<span id=setVol>` **「64%」**（`var(--cyan)`/700）；`margin-bottom:10px`。
  - 滑条 `.track[data-act=setVol]`：高 10、圆角 5、`var(--track)`；填充 `.fill#setVolFill` 蓝青渐变，宽 `64%`，末端橙黄手柄。
  - 第二行 **「屏幕亮度」** / **「100%」**，`data-act=setBri`，填充宽 `100%`。

**② 主题风格**（图标 `i-star`）
- 两行 `.themes-row`（`gap:8px;margin-bottom:8px`）：
  - 行标签 `.theme-hint`：16px `var(--sub)`，宽 36；第一行 **「配色」**、第二行 **「模式」**。
  - `.themes`：`display:flex;gap:8px;flex:1`；每项 `.theme` `flex:1;height:48px;圆角10;cursor:pointer;border:2px solid transparent;display:flex;align-items:center;justify-content:center;gap:8px;16px`；选中 `.on` 边框 `var(--text)`。
  - 开关 `.tsw`：48×28，圆角 14，背景 `var(--sw-off)`，`border:1px solid var(--line)`；`:after` 白色 20×20 圆点，`top:3px;left:3px`，`box-shadow:0 1px 4px rgba(0,0,0,.35)`；选中时背景 `var(--tc)`、圆点 `left:23px`，0.22s 过渡。
  - 配色三项（`data-act=theme`）：
    | 文案 | data-v | 选中开关色 `--tc` |
    |---|---|---|
    | 科技蓝 | blue | `linear-gradient(135deg,#477BFF,#7B61FF)` |
    | 梦幻紫 | purple | `linear-gradient(135deg,#7B61FF,#B98CFF)` |
    | 清新青 | cyan | `linear-gradient(135deg,#19A7CE,#19D5D0)` |
  - 模式两项（`data-act=mode`）：**月牙 i-moon + 深色**（dark，`--tc` #477BFF→#7B61FF）、**太阳 i-sun + 浅色**（light，`--tc` #19A7CE→#19D5D0）。
  - 默认选中：科技蓝 + 深色。截图中选中的开关为蓝色/青色且圆点在右，未选中为灰色圆点在左。

**③ 系统信息**（图标 `i-info`）
- 标题 `h3` `margin-bottom:8px`；内容用 flex 纵向 `space-around` 填满 `height:calc(100% - 28px)`，**6 行完整显示不裁切**。
- `.info-row`：`display:flex;justify-content:space-between`，16px，`line-height:1.2`，底边 1px `var(--line)`（末行无）；左 `var(--sub)`、右 600 粗。
- 六行逐字（左 : 右）：
  1. 设备型号 : **Air8603 串口屏**
  2. 屏幕分辨率 : **1024 × 600**
  3. 系统版本 : **AirUI KTV V2.6.0**
  4. 曲库版本 : **2026.11 高清曲库**
  5. 音频输出 : **HDMI / 光纤 / 模拟**
  6. 网络连接 : **已连接 · 有线**
- > 备注：目标硬件为 WiFi 版本，但当前实现写死「Air8603 串口屏」，本规格按现状记录；如需改 WiFi 字样须同步改源码与本条。

**④ 快捷操作**（图标 `i-check`）
- 三个整行按钮（`display:flex;flex-direction:column;gap:6px`），各 `width:100%;height:36px`：
  1. **「查看已点歌曲」** `.btn` 蓝底白字，`data-nav=ordered`。
  2. **「进入排行榜」** `.btn.ghost` 灰底，`data-nav=rank`。
  3. **「恢复默认设置」** `.btn.ghost` 灰底，`data-act=reset`。

---

## 8. 弹窗内部规格

### 8.1 调音弹窗（`openModal('eq')`，标题「音效调音」）

三个 `.mrow`（背景 `var(--card)`、圆角 12、边框 `var(--line)`、`padding:12px 14px`；弹窗内 `gap:16px`）：
- 每行 `.ml`：`display:flex;justify-content:space-between`，16px，`margin-bottom:12px`；右侧数值 `<b>` 17px `var(--cyan)`。
- 滑条 `.mt[data-act]` 高 12（见 5.4）；下方 `.scale` 16px `var(--sub)`，`margin-top:8px`，两端对齐。

| 行 | 标签 | data-act | 初值 | 右侧显示 | 刻度文字 |
|---|---|---|---|---|---|
| 1 | 音调 | pitch | 50 | `50` | 低 / 标准 / 高 |
| 2 | 麦克风音量 | micVol | 70 | `70%` | 小 / 大 |
| 3 | 系统音量 | setVol | 64 | `64%` | 小 / 大 |

> 系统音量与设置页 `setVol`、播放页 `volume` 三者实时同步。

### 8.2 空调弹窗（`openModal('ac')`，标题「空调控制」）

从上到下四块 `.mrow`：

**① 电源行** `.ac-power`：`display:flex;justify-content:space-between`。
- 左 **「空调电源」**16px/600 `var(--text)`；右 `.ac-switch[data-act=acToggle]` 64×34 圆角 18，关时 `var(--sw-off)`、开时 `linear-gradient(135deg,#477BFF,#7B61FF)`；`:after` 白色 28×28 圆，`left:3px`→开时 `left:33px`，0.18s。
- 下方 `.ac-state` 17px `var(--sub)` 居中，**`acStatus()`**：关时 **「空调已关闭」**；开时 **「运行中 · 制冷 · 自动风 · 24°C」**（模式/风速/温度取当前值）。

**② 运行模式行** `.mrow#acModeRow`：
- 标签 **「运行模式」** + 右侧 `<b id=acModeLbl>` 当前模式名（青色 17px）。
- 卡片选择器 `.ac-cardsel`（`display:flex;gap:10px;margin-top:10px`）：
  - 左箭头 `.cs-arrow[data-act=acModePrev]`：**52×52 实心圆**，蓝紫渐变 `linear-gradient(135deg,var(--blue),var(--purple))`，白色 `i-back` 28×28 / `stroke-width:2.4`，`box-shadow:0 6px 14px var(--shadow)`；hover 亮度 1.16 + 放大 1.05。
  - 中间卡片 `.cs-card[data-act=acModeCycle]`：`flex:1;height:60px;圆角12`，背景 `linear-gradient(135deg,rgba(71,123,255,.3),rgba(123,97,255,.22))`，边框 `1px solid var(--blue)`，`box-shadow:0 0 14px rgba(71,123,255,.2)`；内含模式图标 28px `var(--cyan)` + 名称 20px/800 + 描述 16px `var(--sub)`；点击切换下一项。
  - 右箭头 `[data-act=acModeNext]`：同左箭头但 `transform:rotate(180deg)`。
  - 圆点 `.ac-dots`（`gap:8px;margin-top:8px`）：4 个 8px 圆点，背景 `var(--card2)`；选中 `.on` 宽 22、圆角 5、背景 `var(--blue)`；`data-act=acModeSet data-v=0..3`。
  - 四个模式：`制冷`(i-snow,快速降温) / `制热`(i-fire,温暖空间) / `送风`(i-wind,通风换气) / `除湿`(i-drop,干爽舒适)。

**③ 风速大小行** `#acFanRow`：结构与②完全相同，`acFanPrev/Cycle/Next/Set`，标签 **「风速大小」**。
- 四个选项：`自动`(i-wind,智能调速) / `低速`(i-wind,轻柔送风) / `中速`(i-wind,均衡送风) / `高速`(i-wind,强劲送风)。

**④ 温度设置行** `#acTempRow`：
- 标签 **「温度设置」** + `<b><span id=acVal>24</span>°C</b>`（青色 17px）。
- `.ac-ctl`：`display:flex;justify-content:center;gap:26px;padding:6px 0`。
- 减号 `.ac-btn[data-act=acDown]`：56×56 实心圆，蓝紫渐变，白字 **「−」** 30px/700，`box-shadow:0 6px 16px rgba(71,123,255,.35)`。
- 中间 `.ac-val-sm`：**「24°」** 34px/800 `var(--cyan)`，最小宽 80 居中。
- 加号 `.ac-btn[data-act=acUp]`：同减号，文案 **「＋」**。
- 范围 **16–30°C**；超出不变化。

- 空调关闭时，模式/风速/温度三行加 `.ac-temp-off`：`opacity:.45;pointer-events:none`（半透明且不可点）。
- 关闭方式：点遮罩、点标题 ✕、或再点一次「空调」磁贴；`closeModal()` 同步清除高亮并刷新播放页。

---

## 9. 交互逻辑（每个按键的完整行为）

### 9.1 导航 `go(page)`
- 所有 `[data-nav]` 元素（侧栏、首页磁贴、返回键、快捷操作按钮、迷你条已点）点击即跳页。
- 切换 `.page.active`；侧栏高亮映射：`artist→category`、`search→search`、`rank→home`、`playlist→home`、`playing→home`、`category→category`、`ordered→ordered`、`settings→settings`、`home→home`。
- 调用对应 render 函数 → `updateMini()` → `setupScrollBars()`。

### 9.2 切歌（按已点顺序，用户明确要求）
- `changeSong(step)`：在 `ordered` 中找当前 `playIndex` 位置 `cur`（<0 按 0），`next=(cur+step+len)%len`；只把 `ordered[next].playing=true`，其余 false；`playIndex=ordered[next].i`；`progress=0`；toast「播放：{歌名}」；刷新迷你条、播放页、快捷浮层。
- 迷你条上一首/下一首、播放页控制键、功能磁贴「切歌」全部走此逻辑；队列「下一首」随之联动。
- 默认顺序实测：**孤勇者 → 海阔天空 → 稻香 → 月亮代表我的心 → …**，到头循环；上一首逐级回退。

### 9.3 播放控制
- 播放/暂停 `togglePlay()`：翻转 `playing`，切图标，toast「继续播放/已暂停」。
- 重唱：`progress=0`，toast「重唱《X》已从头开始」。
- 静音/原唱/气氛：翻转状态并 toast；气氛激活时磁贴橙色高亮。
- 原唱/伴唱：标签在「原唱」「伴唱」间切换。
- 进度自动模拟：每 **1.5s** 若 `playing` 则 `progress=(progress+1)%101`，刷新进度。

### 9.4 加歌/队列操作
- `addSong(i)`：已在列表则 toast「《X》已在点歌列表中」；否则 push `{i,playing:false}`，toast「已添加《X》到点歌列表」，更新计数；在已点/首页/播放页则重渲染。
- 置顶 `pin`：仅非首位生效，移到队首并 toast；删除 `del`：移除并 toast、更新计数；清空 `clearOrder`：清空并 toast。
- 点歌曲卡片/横幅空白：`.sel` 青色描边选中；点加号才加歌（加号不触发选中）。

### 9.5 搜索与输入法
- `searchResult()`：`query` 去空格转大写，匹配歌名 / 歌手 / 拼音首字母；toast「找到 N 首相关歌曲」或「没有找到相关歌曲」。
- 中英切换：`toggleIme()` 翻转 `ime`，清空拼音/候选页/符号模式，重渲染键盘，toast「已切换中文拼音输入/已切换英文输入」。
- 候选：`candList()` 精确→前缀→回退；`commitCand(c)` 把字写入 `query`，清拼音，刷新结果；`‹›` 翻页（每页 8 字）。
- 物理键盘：中文模式下若输入内容是「已提交 query + 纯字母后缀」，把后缀当拼音；否则整体作为 query。
- 键盘所有按键行为见 7.4 ④。

### 9.6 滑块与滚动条
- 滑块：`SLIDER_ACTS=,seek,volume,setVol,setBri,pitch,micVol,`，`pointerdown` 即按比例设值并捕获指针，`pointermove` 持续更新，`pointerup` 结束。
- 滚动条：仅 `.sb-thumb` 可拖，长按 **350ms** 才进入拖动；短按无效；拖动按比例换算 `scrollTop`；滑块拖动时变青色。

### 9.7 主题/亮度/时钟
- 配色三选一：重复点当前项 toast「当前已选中该配色」；否则切换并 toast「配色已切换」。
- 深浅二选一：重复点当前项 toast「当前已是深色/浅色模式」；否则切换并 toast「已切换深色/浅色模式」。
- 亮度：按 `(100-brightness)/250` 设置 `#dim` 黑幕透明度。
- 恢复默认：volume=64、brightness=100、theme=blue、mode=dark，并 `setTheme()+setDim()+renderSettings()`，toast「已恢复默认设置」。
- 时钟 `tick()`：每秒刷新 `#clock`=HH:MM:SS、`#date`=YYYY-MM-DD 星期X。

---

## 10. 用户历轮明确要求与实现对照（全部保留）

| 用户要求 | 已实现 |
|---|---|
| 「改回去两行的」 | 功能磁贴恢复两行每行 4 个（`funcCards()` 默认） |
| 「只显示一个就行……只显示待唱，不要当前播放」 | 队列只显示一首待唱，放大为 78px，跳过正在播放项 |
| 「图案再改大一点，尽量占满」 | 磁贴图标块 34→42px、图标 20→27px、stroke 1.8→2 |
| 「按我已点歌来播放，孤勇者切换应该是海阔天空」 | 切歌按 `ordered` 顺序，队列下一首联动 |
| 「加一个可以滑动的线」「显示五首歌，不要7首」 | 排行榜 8 首全渲染 + 蓝色自定义滚动条，行高 62px，一屏约 5 首 |
| 「红圈区域删掉」「这些要贴住」 | 分类栏 150→104px，网格固定 120px 行高顶部贴紧 |
| 「把右边空占满」 | 滚动容器 `width:100%`，列表铺满、滑块贴右 |
| 「橙色实心，里面图形黑色」 | 上一首/下一首橙渐变实心圆 + `#0D1424` 深色图标 |
| 「字母给我绑定一下，也要跳转」 | A–Z + 全部绑定首字母筛选并高亮 |
| 「加中英文输入法」「键盘上方弹候选窗」 | 中/EN 切换 + 拼音候选栏（每页 8 字、翻页、选字搜中文歌） |
| 「最外边框对准 R 和 K 中间」 | 侧栏 124px、导航按钮右边缘 x≈107 对齐顶栏缝隙 x≈108 |
| 「左右按键调大、填满橙色」「模式/风速左右切换卡片」 | 52px 蓝紫渐变白箭头、电源开关、模式/风速卡片+圆点、温度 16–30°C |
| 「系统音量加到调音」 | 调音弹窗含音调/麦克风/系统音量三滑块并与设置页同步 |
| 「长按可滑动，短按无效」「只留蓝色滑块」 | 350ms 长按拖动、灰色轨道透明 |
| 「浅色深色开关只能开一个」「日期时间左右平齐」 | 深浅互斥开关 + 日期左时间右左右排列 |
| 「白色去掉只要黄色」 | 进度手柄仅 `#FFB733` + `#FF9A3D` 边框 |
| 「系统信息显示不全」 | 压缩行距，6 行含「网络连接」全部完整显示 |

---

## 11. 验收标准

1. 单文件 `index.html`，外部依赖数 = 0。
2. 1024×600 下深/浅两模式 × 9 页面：**真实溢出 0、字号 <16px 元素 0**（列表内部滚动项不计溢出）。
3. 交互全通过：导航/返回、加歌去重、置顶/删除/清空、按已点顺序切歌、播放/暂停/重唱、原唱/伴唱、静音、气氛、中英输入与候选、滚动条长按拖动、滑块拖动、三配色与深浅互斥、调音三滑块、空调开关/模式/风速/温度。
4. 深/浅主题截图与本文所述一致：背景有色彩与网格、封面有图案、渐变文字清晰、磁贴/按钮颜色与本文表格逐一对应、无裁切/重叠/对比度问题。

---

## 附录 A：`PINYIN` 完整拼音候选表（逐字照抄，不得增删）

```js
var PINYIN={
 a:['啊','阿'],ai:['爱','碍','艾','唉'],an:['安','按','暗','岸'],ba:['吧','把','爸','八','巴'],
 bai:['白','百','摆','败','拜'],ban:['半','伴','办','版','班','般'],bao:['保','包','报','抱','宝','饱'],
 bei:['北','被','背','杯','备','倍'],bi:['比','笔','必','毕','币'],bian:['边','变','便','遍','编'],
 biao:['表','标'],bie:['别'],bing:['并','病','冰','兵'],bo:['波','播','博','伯'],bu:['不','部','步','布','补'],
 cai:['才','菜','采','彩','猜'],can:['参','餐','残'],cao:['草','操'],ce:['测','侧','策'],
 cha:['茶','查','差','插'],chan:['产','禅','缠'],chang:['唱','长','常','场','畅','厂'],chao:['超','朝','潮'],
 chen:['陈','晨','沉'],cheng:['成','城','程','称','诚'],chi:['吃','尺','迟','赤'],chong:['重','充','冲','虫'],
 chu:['出','处','除','楚','触'],chuan:['穿','传','船','川'],chuang:['创','窗','床'],chun:['春','纯','唇','蠢'],
 ci:['词','次','此','刺','瓷','慈'],cong:['从','聪'],cu:['粗','促'],cuo:['错','措'],
 da:['大','达','打','答'],dai:['带','代','待','袋','戴'],dan:['但','单','淡','蛋'],dang:['当','挡','党'],
 dao:['到','道','岛','稻','倒','导'],de:['的','得','德'],deng:['等','灯','登','邓'],di:['地','低','第','底','迪'],
 dian:['点','电','店','典','殿','垫'],diao:['调','掉','钓'],ding:['定','订','顶'],dong:['动','东','懂','冬'],
 dou:['都','豆','斗'],du:['度','读','独','赌','毒','渡'],duan:['段','断','端','短'],dui:['对','队'],
 duo:['多','朵','躲'],er:['二','而','耳'],fa:['发','法','罚'],fan:['反','饭','范','烦','翻','凡'],
 fang:['方','房','放','防','芳'],fei:['飞','非','费','肥'],fen:['分','份','粉','奋'],
 feng:['风','峰','逢','锋','蜂','凤','丰'],fu:['福','服','复','富','父','夫','负','付','附'],
 gai:['该','改','盖'],gan:['感','敢','赶','干','甘'],gang:['刚','钢','港'],gao:['高','告','糕'],
 ge:['歌','个','各','哥','格','隔','革'],gen:['跟','根'],geng:['更','耕'],gong:['工','公','功','供','宫'],
 gou:['够','狗','构'],gu:['孤','古','故','顾','鼓','固','谷'],guan:['关','观','管','官'],guang:['光','广'],
 gui:['贵','归','规'],guo:['国','过','果','锅'],hai:['还','海','孩','害'],han:['汉','含','寒','喊'],
 hang:['行','航','杭'],hao:['好','号','豪','毫','浩'],he:['和','喝','合','河','何'],hei:['黑'],
 hen:['很','狠','恨'],hong:['红','宏','洪','虹'],hou:['后','厚','侯'],hu:['湖','虎','呼','护','胡','壶'],
 hua:['花','华','画','话','化'],huai:['坏','怀'],huan:['欢','还','环','换','幻','缓'],huang:['黄','皇','慌'],
 hui:['会','回','汇','辉','灰'],huo:['或','火','活','获','货'],ji:['几','机','记','计','级','极','急','集','季','济'],
 jia:['家','加','假','价','甲'],jian:['见','间','件','建','减','检','简'],jiang:['将','江','讲','奖'],
 jiao:['叫','教','交','角','脚','椒'],jie:['节','结','解','街','姐','借','接','杰'],jin:['今','金','进','近','紧'],
 jing:['京','惊','精','静','境','敬','竞','晶'],jiu:['九','酒','久','旧','救'],ju:['句','举','据','局','剧','具'],
 jue:['觉','决','绝'],jun:['军','君','均'],kai:['开','凯'],kan:['看','刊'],kang:['康'],kao:['考','靠'],
 ke:['可','科','客','课','克','刻','颗'],ken:['肯'],kong:['空','控','孔'],kou:['口','扣'],ku:['苦','库','哭','裤'],
 kuai:['快','块'],kuan:['宽','款'],kun:['困','昆'],kuo:['阔','扩'],la:['拉','啦','辣'],lai:['来','莱'],
 lan:['蓝','兰','懒','烂'],lang:['浪','郎','朗','狼'],lao:['老','劳','牢'],le:['了','乐','勒'],
 lei:['类','泪','累','雷'],leng:['冷'],li:['里','理','力','立','利','丽','历','粒'],lian:['连','脸','练','恋','联'],
 liang:['两','亮','辆','凉','量'],liao:['聊','料'],lie:['列','烈','裂'],lin:['林','临','邻','淋'],
 ling:['另','领','令','灵','零'],liu:['六','流','留','刘'],long:['龙','隆'],lou:['楼','漏'],
 lu:['路','陆','露','鲁','卢'],lv:['绿','旅','律','虑'],lun:['论','轮'],luo:['落','罗','洛'],
 ma:['吗','妈','马','码'],mai:['买','卖','麦'],man:['满','慢','漫','曼'],mang:['忙','芒','盲'],
 mao:['猫','毛','帽'],mei:['没','美','每','妹'],men:['们','门'],meng:['梦','猛','蒙'],mi:['米','迷','密','蜜'],
 mian:['面','免','棉'],min:['民','敏'],ming:['名','明','命'],mo:['莫','末','默','摸'],mu:['木','目','母','慕'],
 na:['那','拿','哪','纳'],nan:['难','男','南'],nao:['闹','脑'],ne:['呢'],nei:['内'],neng:['能'],
 ni:['你','泥','呢','逆','拟'],nian:['年','念'],niang:['娘'],nin:['您'],niu:['牛','扭'],nong:['浓','农'],
 nu:['努','怒'],nv:['女'],nuo:['诺'],ou:['欧','偶'],pa:['怕','爬'],pai:['排','派','牌'],pan:['盘','判','盼'],
 pao:['跑','泡'],pei:['陪','配','培'],peng:['朋','碰','棚'],pi:['皮','批','披'],pian:['片','偏','篇'],
 piao:['票','飘'],pin:['品','拼'],ping:['平','评','苹','瓶'],po:['破','迫','泼'],pu:['普','铺','谱'],
 qi:['起','七','期','气','汽','奇','骑','棋'],qian:['前','钱','千','签','浅'],qiang:['强','抢','墙'],
 qiao:['桥','巧','敲'],qie:['且','切'],qin:['亲','琴','勤'],qing:['晴','情','清','青','倾','轻','庆','请'],
 qiong:['穷'],qiu:['秋','求','球'],qu:['去','取','曲','区','趣'],quan:['全','权','泉','劝','圈'],que:['却','确','缺'],
 qun:['群'],ran:['然','燃'],rang:['让'],re:['热'],ren:['人','任','认','忍','仁'],reng:['仍'],ri:['日'],
 rong:['容','荣','融'],rou:['肉','柔'],ru:['如','入'],ruan:['软'],rui:['锐'],run:['润'],ruo:['若','弱'],
 san:['三','散'],sao:['扫'],se:['色'],sen:['森'],sha:['沙','杀','傻'],shan:['山','善','闪','删'],
 shang:['上','尚','伤','商'],shao:['少','烧','稍','绍'],she:['设','社','舍','射','奢'],
 shen:['深','身','神','什','审'],sheng:['生','声','升','胜','盛','圣'],
 shi:['是','十','时','事','世','使','始','式','识','诗','史','士','视','试','释','势','逝','适','侍','嗜','噬'],
 shou:['首','手','收','受','守','熟','瘦'],shu:['书','树','数','输','术','束','舒'],shua:['刷'],shuai:['帅','摔'],
 shuang:['双','爽'],shui:['水','谁','睡'],shun:['顺','瞬'],shuo:['说','硕'],si:['四','思','死','私','丝','寺'],
 song:['送','松','颂'],sou:['搜'],su:['速','素','诉','苏'],suan:['算','酸'],sui:['岁','随','虽'],sun:['孙','损'],
 suo:['所','锁','索'],ta:['他','她','它','塔'],tai:['太','台','抬','泰'],tan:['谈','弹','摊','炭'],
 tang:['糖','汤','唐','躺'],tao:['桃','逃','套','淘'],te:['特'],teng:['疼','腾'],ti:['提','题','体','替','踢'],
 tian:['天','田','甜','添','填'],tiao:['条','调','跳'],tie:['铁','贴'],ting:['听','停','庭','挺','厅'],
 tong:['通','同','童','铜','统'],tou:['头','投','透'],tu:['图','土','兔','突'],tuan:['团'],tui:['推','退','腿'],
 tuo:['脱','拖','托'],wa:['哇','挖','娃'],wai:['外','歪'],wan:['万','晚','完','玩','碗','湾'],
 wang:['王','网','望','忘','往'],wei:['为','位','未','味','胃','伟','卫','围','维'],
 wen:['文','问','闻','吻','温'],wo:['我','握','窝'],wu:['五','无','午','舞','务','物','雾','乌'],
 xi:['西','希','洗','喜','系','细','席','习','惜'],xia:['下','夏','吓','虾'],xian:['现','先','线','限','县','仙'],
 xiang:['向','想','相','香','乡','箱','详','享'],xiao:['小','笑','消','晓','校','效'],xie:['谢','写','些','鞋','协'],
 xin:['新','心','信','辛','欣','薪'],xing:['行','星','型','醒','幸','姓'],xiong:['兄','熊','雄'],
 xiu:['修','休','秀','绣'],xu:['需','须','许','徐','续'],xuan:['选','宣','悬','旋'],xue:['学','雪','血','穴'],
 xun:['寻','询','训','迅','巡'],ya:['呀','牙','压','亚','鸭'],yan:['眼','演','严','言','盐','颜'],
 yang:['阳','羊','样','洋','养','氧'],yao:['要','摇','药','邀','腰'],ye:['也','夜','叶','业','野'],
 yi:['一','以','已','意','衣','医','依','异','艺','忆'],yin:['音','银','引','饮','阴','印'],
 ying:['应','影','英','赢','硬','映'],yong:['用','勇','永','泳','拥','庸'],you:['有','又','右','友','油','游','优'],
 yu:['与','雨','语','鱼','于','玉','遇','余','渔'],yuan:['元','远','原','愿','圆','员'],
 yue:['月','越','约','乐','阅','岳'],yun:['云','运','韵','匀','允','晕'],zan:['赞','暂'],zao:['早','造','糟','澡'],
 ze:['则','责','择'],zen:['怎'],zeng:['增','赠'],zhan:['站','展','占','战'],zhang:['张','长','章','掌','丈'],
 zhao:['找','照','招','朝','赵'],zhe:['这','着','者','折','哲','浙'],zhen:['真','针','珍','阵','震'],
 zheng:['正','整','政','争','征','郑'],zhi:['之','知','只','直','制','指','纸','志','至','致'],
 zhong:['中','种','重','钟','终'],zhou:['周','州','舟','皱'],zhu:['主','住','注','助','祝','著','竹'],
 zhua:['抓'],zhuan:['转','专','砖'],zhuang:['装','壮','状'],zhui:['追'],zhun:['准'],zhuo:['桌','捉','卓'],
 zi:['子','字','自','资','紫'],zong:['总','纵','宗'],zou:['走','奏'],zu:['组','足','族','祖'],
 zuan:['钻'],zui:['最','醉','嘴'],zun:['尊'],zuo:['做','作','左','坐','座']
};
```
