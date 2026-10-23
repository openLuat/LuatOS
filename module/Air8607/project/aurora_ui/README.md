# AURORA UI · Air8607 炫酷界面演示

> Air8607 + 10 寸 RGB 屏（1024x600）+ GT911 触摸
> **零图片素材**：极光、3D 陀螺仪、频谱、3D 星云、触摸粒子场全部由 `airui.shape`
> 的 `line / circle / rect / ellipse` 图元每帧实时计算生成。

---

## 为什么它比 `module/Air8601/project/UI Store` 更"炫"

UI Store 的 7 个 demo（Beverage / BusFare / FactoryTwin / LuckyWheel / PetPark /
SmartHome / TrainControl）都是**图片素材 + 控件排版**的静态界面：
最高刷新率 25fps（LuckyWheel 转盘），最复杂的动画是 FactoryTwin 一条 220ms 的线性抽屉，
`airui.shape`（逐帧程序化绘制）**一次都没用过**，也没有任何 3D 透视或粒子系统。

本工程打的是完全不同的技术栈：

| 维度 | UI Store 上限 | 本工程 |
|---|---|---|
| 绘制方式 | `container / label / image / button` 拼图 | `airui.shape:set_items` 逐帧重算 130~200 个图元 |
| 3D | 无（最接近的是旋转 PNG） | 自由视角透视投影 + 拖拽轨道相机 + 深度着色 |
| 粒子 | 8 个移动小条 | 110 颗带物理与拖尾的粒子，触摸即发射 |
| 过渡动画 | 一条 220ms 线性抽屉 | 页面滑动 + 光带扫过 + 弹簧指示器 + 三次缓出 |
| 刷新率 | 25fps | 30fps（`frame_ms = 30`），背景层 10fps 降频 |
| 素材依赖 | 每页 1~100 张 jpg/png | **0 张** |
| 原生控件 | 未用 slider / switch / chart | 用了 `slider`（两处）、`switch`（两处）、`button` |
| 可观测性 | 仅 LuckyWheel 有 FPS 日志 | HUD 常驻 `FPS 脚本帧率 / LV 渲染帧率 / 图元数` |

---

## 四个页面

| # | 页面 | 主视觉 | 交互 |
|---|---|---|---|
| 1 | 核心 NEXUS | 三条不同倾角的 3D 轨道环 + 卫星 + 72 格刻度盘 + 弹簧进度弧 | 左半屏横向拖拽给陀螺仪加角速度，松手惯性滑行 |
| 2 | 声场 SPECTRUM | 30 段镜像频谱 + 峰值帽 + 45% 倒影 + 顶部瀑布 + 拍频冲击波 | 右侧滑块调音量 |
| 3 | 星轨 ORBIT | 84 颗粒子的双旋臂星云（真 3D 投影 + 近邻连线 + 盘面定位环） | 拖拽转视角（偏航/俯仰 + 惯性），滑块改视距 D |
| 4 | 星尘 STARDUST | 向心引力 + 切向涡流的粒子场，粒子带速度拖尾 | 手指划过即喷粒子，可切涡流/拖尾，可一键清空 |

底部 Dock 有 4 个页签 + 弹簧滑动指示器；无操作 20 秒自动轮播。

---

## 目录结构

```
module/Air8607/project/aurora_ui/
├── README.md
├── main.lua                  主程序入口（只做加载：PROJECT/VERSION + require app_main / ui_main）
├── app/
│   └── app_main.lua          应用主入口：硬件初始化 / 启动编排 / 动画任务
├── ui/
│   ├── ui_main.lua           UI 主入口：加载 ui_shell 并对外转发构建与动画接口
│   ├── ui_shell.lua          外壳：极光背景 / HUD / 玻璃卡片 / Dock / 页面过渡 / 主循环
│   ├── theme.lua             设计令牌：配色 / 布局 / 字号 / 帧率预算
│   ├── fx.lua                绘图工具库：图元池 / HSL / 缓动 / 3D 投影 / 复合图元
│   ├── view_nexus.lua        页面 1
│   ├── view_spectrum.lua     页面 2
│   ├── view_orbit.lua        页面 3
│   └── view_stardust.lua     页面 4
└── drv/lcd/
    └── exd_air8607_rgb.lua   10 寸 RGB 屏显示 IC 初始化扩展库（与 airui_showcase 同一份）
```

---

## 运行

1. 用 LuatTools / 量产工具，把本目录下**全部 .lua 平铺添加**到脚本区（不需要保留子目录），
   入口为 `main.lua`（`PROJECT = "aurora_ui"`）。
2. 烧录后上电：背光在上电时占空比为 0，等界面搭好才点亮，避免花屏。
3. 串口看到 `AURORA UI 已就绪，airui 版本 x.y.z` 即表示界面进入动画循环。

依赖：固件需开启 `LUAT_USE_AIRUI`（含 hzfont 矢量字库）与 `display` / `tp` 库。
引脚与 `module/Air8607/project/factory/config/eng_8607_10i_v0.lua` 对齐：

```
LCD 复位 pin_rst = 15      LCD 供电 pin_pwr = 17
背光 PWM3 (GPIO13)         GT911: I2C1 400kHz, pin_rst = 14, pin_int = 51
```

---

## 实现要点

### 1、图元池（`fx.pool`）
每帧 130~200 个图元，如果每帧新建 Lua 表，一秒就是 4000+ 临时表，
GC 周期回收会带来肉眼可见的顿卡。池子复用同一批表，`finish()` 时把尾部残留置 `nil`
（`shape:set_items` 用 `lua_rawlen` 取长度，尾部留旧表会把上一帧的图元一起画出来），
并且每个写入方法都重写该图元的**全部字段**，不依赖"上一帧的默认值"。

### 2、分层降频
- 极光背景：全舞台 `992x438` 的 shape，**每 3 帧才重算一次**（≈10fps），省掉 2/3 的全屏重绘
- 主视觉：`628x422` 的 shape，每帧重算（30fps）
- 卡片与数值：**5Hz** 刷新，且 `set_text` 前先比较，避免 LVGL 反复重排文本
- 静态层（网格、刻度盘）只在 build 时画一次

实测每帧图元数（PC 上跑的统计，真机同量级）：

| 页面 | 峰值图元 | 说明 |
|---|---|---|
| NEXUS | 136 | 3 环 x22 段（前半环加光晕）+ 34 星尘 + 进度弧 |
| SPECTRUM | 171 | 30 柱 + 30 倒影 + 30 峰值帽 + 46 瀑布列 + 冲击波 |
| ORBIT | 129 | 84 粒子 + 42 连线 + 24 盘面环 |
| STARDUST | 201（平均 77） | 上限 110 颗粒子，只有高速粒子画拖尾 |

### 3、时间基准
`mcu.ticks()` 的单位依平台而变（PC 模拟器 1ms/tick，Air8607 主控约 20ms/tick），
必须经 `mcu.hz()` 折算成毫秒；而**动画步长**反而要用固定 `frame_ms`——
tick 分辨率比帧间隔还粗，拿 tick 差当 `dt` 只会得到 20/40ms 的抖动值，画面一顿一顿。

### 4、节拍补偿
`sys.wait(n)` 是"至少睡 n 毫秒"，实际周期 = 帧间隔 + 本帧耗时，
不补偿的话工作越重帧率越低、自我恶化。主循环按实测耗时把睡眠补回来：
`wait = frame_ms - cost`。

### 5、FPS 自证
HUD 右侧常驻两个数字：`FPS 30 / LV29 136`——
前者是脚本动画帧率，后者是 `airui.debug()` 给出的 LVGL 真实画面刷新率与当前图元数。
两者接近说明脚本没拖后腿；脚本高而 LV 低，说明瓶颈在渲染/刷屏侧。

---

## 调优旋钮

| 位置 | 参数 | 作用 |
|---|---|---|
| `theme.lua` | `perf.frame_ms` | 主循环节拍。30 = 约 33fps；吃力改 40（25fps）或 50（20fps），动作速度不变 |
| `theme.lua` | `perf.bg_every` | 极光背景降频倍数，调大更省 |
| `view_nexus.lua` | `SEG` / `DUST` / `ARC_SEG` | 轨道环段数 / 星尘数 / 进度弧段数 |
| `view_spectrum.lua` | `NB` / `WF_N` | 频段数 / 瀑布列数 |
| `view_orbit.lua` | `NP` / `ARM_A` | 粒子数 / 每臂粒子数 |
| `view_stardust.lua` | `MAXP` | 粒子上限（硬上限，乱划也不会爆表） |
| `ui_shell.lua` | `AUTO_SEC` | 无人操作自动轮播间隔，设为 `1e9` 即关闭 |

---

## 注意

- 屏幕分辨率固定 1024x600（`theme.screen` + `exd_air8607_rgb` 里的 RGB 时序都是这块屏的）。
  换屏需要同时改时序参数。
- 卡片质感靠"半透明底 + 顶部 1px 高光 + 1px 描边"三层叠出来。
  `airui.container` 的 `shadow` 参数在当前版本**不生效**，不要指望阴影。
- 触摸只转发给当前页面 `HERO` 矩形内的触点：
  右侧 `PANEL` 里的原生 `slider` / `switch` 要自己接收触摸，不能被粒子发射器抢走。
- 若真机出现"日志说初始化完成但点不动"，检查 `touch_init()` 是否早于动画任务启动
  （`app_main.lua` 里已经按"build → touch_init → taskInit(run) → 背光"的顺序排好）。

### 整型参数陷阱（会直接让 VM 退出）

`set_pos` / `set_color` 这类方法在 C 层是 `luaL_checkinteger`：传入 `123.45`
会抛 `bad argument #1 to 'set_pos' (number has no integer representation)`，
**整个 Lua VM 退出并重启**。而缓动算出来的位置天然是小数，所以：

- 页面过渡里的每一次 `set_pos` 都先 `math.floor`（见 `step_transition`）
- 图元表里的 `width / opacity / radius / segments / 坐标` 全部在 `fx.pool` 里取整
  （`fx.int`）。注意 `shape:set_items` 走的是 `lua_tointeger`，浮点会被**静默**转成 0
  —— 不报错，只是那个物件"凭空消失"，比崩溃更难查。
- 过渡动画单独 `pcall`，万一再出错只复位过渡，不会把整机跑重启。

同理，`airui.container` 的 `color / color_opacity / border_width / radius`
走的是 `airui_marshal_integer`（同样是 `lua_tointeger`），也别传小数。
