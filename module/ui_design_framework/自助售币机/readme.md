# 自助售币机 · AirUI 真机界面

LuatOS + AirUI（底层 LVGL9）六屏交互流程，与 `docs/自助售币机UI效果稿.html` 同一套视觉令牌落地到真机。

**双主题**：暗色「暖金 + 石墨黑」（默认）与亮色「米白 + 深棕金」，点顶栏右上角主题按钮即时重涂，
不重建页面 —— 键盘敲到一半的会员号、已选档位、进行中的订单都保住。

流程：登录（键盘 / 扫码）→ 选币档位 → 扫码支付 → 支付成功 → 自动回首页，
另有数字键盘弹层与全局 toast 提示。

## 目录结构（提交至 LuatOS/module/ui_design_framework/自助售币机/）

```
自助售币机/
├── code/       所有代码与图片、音频、视频等资源文件
│   ├── main.lua              启动编排：背光归零 → 屏 → airui → 触摸 → 状态 → 建页 → 点亮 → 主循环
│   ├── app_config.lua        硬件 / 节奏 / 布局尺寸 + 7 档字号，唯一改数值的地方
│   ├── app_state.lua         6 档位、会员态、订单、余额、fskv 落盘
│   ├── ui.lua                页面装配、切页过渡、主题回调、每帧 tick
│   ├── ui_widget.lua         唯一控件入口（box/group/bar/label/num/icon/qrcode/press…）+ 几何收敛
│   ├── ui_theme.lua          设计令牌真源（暗/亮两套）
│   ├── ui_icons.lua          全部矢量图元，无位图依赖
│   ├── ui_topbar.lua         品牌 / 会员胶囊 / 余额胶囊 / 时钟 / 主题按钮 / 发丝线
│   ├── ui_login.lua          登录页：金币主视觉 + 登录卡（键盘 / 扫码 / 先购币）
│   ├── ui_scan.lua           扫码登录：取景框四角 + 扫描线往返 + 60s 倒计时
│   ├── ui_tier.lua           6 档位网格（3×2）+ 选中态 + 汇总卡
│   ├── ui_pay.lua            支付页：二维码 + 120s 倒计时 + 订单明细 + 支付方式切换
│   ├── ui_success.lua        成功页：到账明细 + 10s 自动返回
│   ├── ui_kb.lua             数字键盘弹层
│   ├── ui_toast.lua          全局提示
│   ├── drv_lcd.lua           1024×600 RGB 屏初始化（display / lcd 双后端）
│   ├── drv_power.lua         背光 PWM + 复位时序
│   ├── drv_tp.lua            GT911 触摸初始化 + 绑定 airui
│   └── coin_hero.png         登录页金币位图 240×240（单 IDAT 块）
├── docs/       code 和 readme.md 之外的其余所有文件
│   ├── 自助售币机UI效果稿.html        UI 效果稿（浏览器直接打开，含深浅色切换，1024×600）
│   ├── handoff.md                     交接单：逐屏坐标表 / 令牌表 / 坐标系约定 / 动画节拍
│   ├── dump_nodes.py                  导出效果稿节点坐标
│   ├── check_layout.py                几何越界 + 对比度 + 最小字号校核
│   └── img/                           coin_hero.png 源图 + gen_assets.py（生成单 IDAT 块）
└── readme.md   本文件
```

## 调试硬件环境

| 项目 | 说明 |
| --- | --- |
| 主控 | Air8607（SoC：Air1603） |
| 屏幕 | 合宙官方 AirLCD_1100 10.1 寸 RGB 屏，1024×600，纯 RGB 时序（不做 IC 初始化） |
| 屏幕时序 | hbp140 / hspw20 / hfp160，vbp20 / vspw3 / vfp12，50MHz，复位脚 GPIO15 |
| 触摸 | GT911 电容触摸（I2C1，TP_RST=GPIO14 / TP_INT=GPIO51，下降沿），AirLCD_1100 自带 |
| 背光 | PWM3，1kHz；开机先 0% 占空比把界面搭完，再点亮避免看到搭界面过程 |
| 屏供电使能 | 未独立引出（`app_config.HW.screen.pin_pwr = -1`） |
| 供电 | USB 供电即可，屏幕由开发板排线供电 |
| 改板入口 | 全部设备参数集中在 `app_config.lua` 的 `HW`，换板只改这一处 + `drv_*.lua` |

## 内核固件

- 固件文件名：`LuatOS-SoC_V1028_Air1603_102.soc`（与「智能家居」demo 同一套；Air1603 / 1601 / 1602 同编号固件内容一致）
- 烧录工具：合宙 **Luatools**（选中上述 .soc 固件 + 本工程 `code/` 目录脚本，底层下载即可）
- 脚本区/文件系统：102 号固件为脚本区 4096KB / fs 1536KB，本工程（18 个 `.lua` + `coin_hero.png` ≈ 110KB）远小于该预算
- 工程依赖的固件内置库：`airui`、`display`（无则退 `lcd`）、`tp`、`i2c`、`gpio`、`pwm`、`fskv`、
  `hzfont`（中文矢量字库，字号 12~255 全覆盖，本工程最小 16 号）、`io`、`mcu`、`sys`
- 二维码：由 `airui` 内建 `qrcode` 生成；固件未编进时 C 层给 nil（不抛错），页面退化为同尺寸占位块

## 烧录

1. `code/` 下 **18 个 `.lua` + `coin_hero.png`** 全部放进 luadb 根目录（图片必须与 `main.lua` 同批下发，
   放 `docs/` 里进不了真机）；
2. `main.lua` 为入口（`PROJECT = "coin_kiosk"`）；
3. 启动顺序：背光归零 → `drv_lcd`（RGB 1024×600）→ `airui.init` → 字号 7 档 → `drv_tp`（GT911）
   → `fskv` + `app_state.init` → `ui.build` → 背光淡入 → 50ms 主循环；
4. 主循环是**补偿式节拍**（`POLL_MS − 本帧耗时`，下限 4ms），传 `ui.tick` 的是**毫秒**。

硬件参数见上节「调试硬件环境」，数值真源是 `app_config.lua`：

| 项 | 值 |
|---|---|
| 屏 | 1024×600，hbp140 / hspw20 / hfp160，vbp20 / vspw3 / vfp12，50MHz，rst=15 |
| 触摸 | gt911，`HW.tp.i2c_id`，rst=14，int=51，下降沿 |
| 背光 | pwm3 / 1kHz，见 `drv_power.lua` |

## 分层

单向依赖：`main` 编排 → `ui` → `ui_*` 页面 → `ui_widget` 安全原语 → `airui`。

| 文件 | 职责 |
|---|---|
| `app_config.lua` | 硬件 / 动画节奏 / 布局尺寸 + `SIZES` 7 档字号，**唯一改数值的地方** |
| `app_state.lua` | 6 档位、会员态、订单、余额、fskv 落盘（没有 fskv 也不崩） |
| `ui_widget.lua` | 唯一控件入口：`box / group / bar / label / text_mid / text_right / num / num_w / shape / polyline / icon / image / qrcode / press` + 登记表与主题重涂（`register / repaint / set_pal / set_ona / set_color / opa`） |
| `ui_theme.lua` | 设计令牌真源（`P.dark` / `P.light`）+ 亮暗就地重涂 |
| `ui_icons.lua` | 全部矢量图元（金币、人像、扫码、太阳/月亮、对勾…），无位图依赖 |
| `ui_topbar.lua` | 品牌、会员胶囊、余额胶囊、时钟胶囊、主题按钮、发丝线 |
| `ui_login.lua` | 登录页：左侧金币主视觉 + 右侧登录卡（键盘 / 扫码 / 先购币） |
| `ui_scan.lua` | 扫码登录：取景框四角 + 扫描线往返 + 60s 倒计时 |
| `ui_tier.lua` | 6 档位网格（3×2）+ 选中态 + 汇总卡 |
| `ui_pay.lua` | 支付页：二维码 + 120s 倒计时 + 订单明细 + 支付方式切换 |
| `ui_success.lua` | 成功页：到账明细 + 10s 自动返回 |
| `ui_kb.lua` / `ui_toast.lua` | 数字键盘弹层 / 全局提示 |
| `ui.lua` | 页面装配、切页、主题回调、每帧 `tick` |
| `drv_*.lua` | lcd / tp / power 驱动 |

**所有控件只走 `ui_widget`**，禁止裸调 `airui.button/container` 做热区或显隐。

`ui_widget` 内置几何收敛：容器创建时登记 `cw/ch = 外框 − 2×border_width`，子控件创建前把
`x/w`、`y/h` 夹进 `[0, cw] × [0, ch]`（再内收 1px），越界则收缩并按 tag 去重打日志（`[uiw] 越界已收敛`）。
真机日志出现这条，说明布局算错了，要回去改数字，不是靠兜底。

## 图片资源规格（硬门槛）

`docs/img/gen_assets.py` 生成 `coin_hero.png`：**240×240，单 IDAT 块**（整幅像素 → 一个 zlib 流 → 一个 IDAT）。

- 硬件解码只认单个 IDAT：`PIL` 默认会切出几十块 → 真机直接拒（日志 `multiple IDAT blocks`）；
- 解码内存 `240×240×4 = 230,400` 字节，远低于板级缓存，无「谁先加载谁显示」问题；
- 改图流程：改 `docs/img/coin_hero.png` → `python docs/img/gen_assets.py` → 覆盖 `code/coin_hero.png`。

**路径与降级**：登录页主视觉按候选路径依次试，`io.exists` 探到真实文件才建位图：

```
/luadb/coin_hero.png → /luadb/img/coin_hero.png → /luadb/docs/img/coin_hero.png → coin_hero.png
```

探不到才退化成同尺寸矢量金币（`ui_icons.coin`），并打 `[login] 主视觉位图缺失，退化为图元金币`。
之所以必须先探文件：`airui.image` 在文件不存在时**仍返回非 nil 对象**，只看返回值判断不出来。

## 布局与令牌（已逐条核对到叶子）

- 逐屏坐标表 + 令牌表（暗/亮两套、对比度实测）在 `docs/handoff.md`，改视觉先改效果稿，再回填该表；
- 6 屏 + 顶栏 + 键盘 + toast 的每个子控件都算过 `right ≤ cw`、`bottom ≤ ch`；
- 带 1px 描边的容器，子控件按 `外框 − 2` 摆放（这是真机滚动条的头号来源）；
- **坐标系约定**：子控件 `x/y` 原点是父容器**内容区**左上角，`ui_widget.fit()` 的边界是
  `[0, cw] × [0, ch]` 再内收 1px；`text_mid` / 热区**不再**叠加 `border_width`。
  旧写法把每个子控件整体右下移 1px，右缘压在内容区边界上 → 卡片/键帽每处各出滚动条。
  逐条对照表见 `docs/handoff.md` §4.1；
- 越界复查：`python docs/dump_nodes.py` 导出效果稿节点坐标 → `python docs/check_layout.py` 检查几何越界、
  块轮廓对比度与最小字号（当前输出 `VIOLATIONS: 0 / WARNINGS: 0`）；
- 令牌豁免的三个预留键（`panel` / `track` / `hl`）列在 `handoff.md` 末节。

## 主题切换

令牌真源是 `ui_theme.M.P.dark|light`（键名 = 效果稿 CSS 变量去掉 `--`）。点顶栏主题按钮 →
`M.toggle()` → `M.apply(theme, true)`，顺序是死的：

```
W.set_ona(opa)      三个 alpha 令牌（disc / vline / edgeline）先就位
  ↓
W.set_pal(pal)      把新色板注入 ui_widget 的 PAL（控件登记的令牌名此时解析成新色）
  ↓
W.repaint(pal)      遍历登记表逐控件 set_color / set_border / set_items，返回下发条数
  ↓
M.on_apply(pal)     收尾：二维码静区等 set_color 刷不到的部分
```

要点：

- **不重建页面**：键盘敲到一半的会员号、已选档位、进行中的订单全部保住（重建会清空）；
- 创建控件时传**令牌名**（`ck = "pri"`、`skin = "card"`、`bskin = "edge"`）才会跟着变色，
  传写死的数值不会被重涂；
- `repaint` 返回 0 说明固件 `set_color` 全挂，退回 `on_rebuild` 整体重建，不做半新半旧的界面；
- 主题**落盘**（`ST.set_theme` → fskv），重启保持上次选择；fskv 不可用时上电回默认暗色；
- 块轮廓一律 `edge`（暗 1.72:1 / 亮 2.00:1），`divider` 只做分隔线；
- 会变的数字（金额、倒计时、余额、时钟）全部走 `W.num` 等宽格 —— hzfont 数字不等宽，整串
  `set_text` 会左右跳。

## 动画节拍

| 项 | 实现 | 为什么 |
|---|---|---|
| 主循环 | `sys.wait(budget − 本帧耗时)`，下限 4ms | 补偿式节拍：不补偿则实际周期 = 50 + 干活，帧率与业务时间同时变慢 |
| 动画步长 | `main` 传 **实测周期**（`mcu.ticks` 差值，夹到 4~200ms） | 恒传名义 50ms 时，负载一抖动画就慢一截 |
| 扫描线 | 浮点位置按 `75px/s` 累加，取整后变了才 `set_pos` | 每步清零余量 → 实际每 50ms 走一次 3px，慢 25% 且一顿一顿 |
| 切页过渡 | 新页从 `−48px` 滑到 `0`，150ms，三次缓出 | 位移恒 ≤ 0，右缘不越屏；过渡期间节拍临时提到 16ms（`ui.busy()`） |
| 点击反馈 | 按下即变色，90ms 复原（`press_ms`） | 触摸按下到松开的窗口内必须可见 |

## 验收要点对照

1. UI 效果见 `docs/自助售币机UI效果稿.html`（浏览器打开即是 1024×600 舞台，含深/浅色切换）；
2. HTML 与真机使用同一套视觉令牌（`ui_theme.lua` ↔ HTML CSS 变量），效果高度相符；
3. 六个页面全部可点到位，无「点了没反应」的死区；键盘、弹层、toast 均可用；
4. 主题切换不重建页面，键盘输入与已选档位不丢，fskv 记忆重启保持；
5. 最小字号 16 号（配置最小档 `SIZES[1] = 16`），全工程无低于 16 号文字；
6. 布局零越界：`python docs/check_layout.py` 输出 `VIOLATIONS: 0 / WARNINGS: 0`，
   真机容器边缘无滚动条细线；
7. 动画流畅：50ms 巡检（过渡期 16ms），扫描线匀速、切页 150ms 缓出、点击反馈 90ms 内可见；
8. 硬件环境与内核固件文件名见上文两节。

## 已知限制（真机接硬件/后端时改这几处）

- **会员登录**：固定码 `13800001234` 通过，其余按位数校验；真机需接会员后端；
- **扫码登录**：UI 只等 `SCAN.ok(code)` 一个回调，当前由「模拟扫码成功」按钮触发；真机需接扫码头；
- **支付**：二维码内容为订单串 `ARCADE|会员|档位|金额`，成功由「模拟支付成功」按钮触发；真机需轮询支付后端；
- **时钟**：无 RTC/SNTP 时显示 `00:00:00`；
- **60s 无操作自动登出**：公共设备防串号，页面停留超时回登录页并带提示。
