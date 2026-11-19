# CDU-1200 液冷散热机组 · PLC 主控屏（PLCUI）

Air8607 / Air1603 + 10.1 寸 RGB 1024×600，用 **PLCUI**（XML 定布局 + Lua 更新数据）做的五页主控屏。
**深色工业风**，与同目录 `mmy_pack_plc`（浅色组态风）刻意区分：同一套框架，两种视觉语言。
整屏只有一张 4×4 透明 PNG 做点击热区，其余全是纯色块、原生表格与原生图表。

## 硬件与运行环境

| 项目 | 参数 |
|------|------|
| 主控 | Air8607（Air1603） |
| 屏幕 | 10.1 寸 RGB 1024×600 |
| 触摸 | GT911，I2C1 |
| 背光 | PWM3（GPIO13），默认 82% |
| 固件 | 需含 PLCUI 的 102 / 103 号固件（104 号已移除） |
| 开发验证 | `bsp/pc` PC 模拟器（PLCUI 1.0.2） |

## 目录

```
mmy_cdu_plc/
├── design/index.html      深色原型（1024×600，可点页签，#p3 深链）
├── code/
│   ├── main.lua           入口：工程信息 / 硬狗 / errDump / 装载 boot_app
│   ├── boot_app.lua       上电 → 显示 → 字形缓存 → 载入界面 → 触摸 → 背光 → 1Hz 任务
│   ├── data_app.lua       一二次侧回路、泵组、补水、能效的数据模型
│   ├── ui_app.lua         载入 / 按页刷数 / 三张曲线滚动 / 表格 / 事件
│   ├── ui_vars.lua        绑定表（按页分组）
│   ├── tp_app.lua         触摸
│   ├── exd_air8607_rgb.lua 显示 IC 初始化
│   └── res/
│       ├── main.xml       5 页布局，417 个组件
│       └── hit.png        4×4 透明热区
└── readme.md
```

## 五页

**总览** — 深色顶栏 + 状态条 + **双回路 P&ID**（一次侧冷冻水 → 板换 → 二次侧冷却液 → 机柜，P1 主泵 + 旁路 P2 热备）+ 机组实时四格 + 泵组 + 报警。

**回路** — 一次侧 / 二次侧各四个参数、换热与能效（换热量、COP、接近温差）、补水与液位、五项保护联锁。

**趋势** — 供回液温度、二次侧压差、泵频与阀位三张实时曲线（1 Hz 采样，30 s / 30 s / 50 s 窗口）。

**点位** — DI / DO / AI 三张表 + AO 三路给定 + 单片强制 + 扫描诊断。

**系统** — 设备信息、能效统计（换热量 / COP / PUE 贡献 / 运行时長）、背光滑块与三档、运行诊断、版本。

## 数据自洽

数值不是各自随机的，而是互相咬合的：

- 换热量按 `Q = 1.163 × 流量(m3/h) × 供回温差(K)` 反算，二次侧 105 m3/h × 8.2 K ≈ 1000 kW，与 KPI、状态条、能效卡三处一致
- 一次侧流量恒为二次侧的 1.26 倍（板换两侧的热平衡近似），一次侧温差 6.4 K
- 泵频随机房负荷（慢波）在 62~88 % 之间走，阀位随动，供液温度跟着负荷上升
- 液位按 130 s 周期缓慢起伏，补水阀在液位低时动作

## 深色风的几条落地约定

| 手段 | 原因 |
|---|---|
| 卡片 `background` + **1px `border-color`** | 深底上只靠色差分不清边界；`border-color`/`border-width` 是 PLCUI 支持的容器属性 |
| 标题左侧 4×18 青色小条 | PLCUI 没有列表符号，用一个 container 充当视觉锚点 |
| 字体层级只靠字号与灰度 | label 运行时没有 `set_color`，颜色写死在 XML |
| 状态色靠预制色块 + `set_hidden` | 同上：状态变化只能切显隐，不能改色 |
| 只有 image 可点 | `clickable` 只在 image 分支解析，页签/按钮都铺 4×4 透明图做热区 |

## 曲线实现（与 PACK-3 同一套机制）

- 三张图点数以 XML 的 `point-count` 为准（30 / 30 / 50），`add_point` 走固定长度环形缓冲，新点进最右、其余左移，天然滚动
- **采样按 1 Hz 入图**：200 ms 定时器只负责取数，每 5 拍才追加一次。温度这类慢量在 6 秒窗口里是一条直线，1 Hz × 30 点 = 30 秒窗口才看得出波动
- **`chart` 的 `hdiv`/`vdiv` 在 1.0.2 上不出横向网格**，改用三条 1px 容器画在图表底层，位置可控
- 启动后约 30 秒，环形缓冲被真实数据填满，XML 里的初值（一条平线）滚出窗口

## 字形踩坑（hzfont）

| 字符 | 结果 |
|---|---|
| `m³` 的上标 ³ | **缺字形，渲染成方框** → 全项目改 `m3/h` |
| 全角空格 U+3000 | **缺字形** → 只用 ASCII 空格 |
| `μ`（μS/cm） | 有，正常 |
| `℃` `·` `→` `○` `●` `°` `×` `±` | 有 |

hzfont 缓存默认 256 条，本工程 9 档字号、静态就有四百多个「字符 × 字号」组合，`boot_app` 在载入界面前把缓存调到 1024（失败退 512、再退默认）。

## 与浅色那套的差别

| | mmy_pack_plc | mmy_cdu_plc |
|---|---|---|
| 底色 | `#E9EDF3` | `#0B1017` |
| 卡片 | 白底无描边 | `#121A24` + 1px 描边 |
| 主色 | 电光蓝 | 青色 `#22D3EE` |
| 主画面 | 七工位阵列 | 双回路 P&ID |


## 真机烧录与固件兼容（2026-11-18 实测）

设备：**Air1603_A10**，固件 `LuatOS_V1031_Air160X`（build 2026-11-12，对应 PLCUI **1.0.1**）。

```bash
# 进 boot 模式
luatos-cli.exe device boot --port COM12
# 整机烧录（ROM + 脚本），固件用仓库里现成的 Air1603 102 号
luatos-cli.exe flash run ^
  --soc "LuatOS/module/Air1601_Air1602_Air1603_Air1604_Air1605/demo/ws2812/firmware/LuatOS-SoC_V1031_Air1603_102_20261112_022607.soc" ^
  --port COM12 --script "LuatOS/module/Air8607/project/<工程>/code" --tail-log-secs 8
```

踩到并已修掉的三处：

| 现象（真机日志） | 原因 | 处理 |
|---|---|---|
| `fopen not found /luadb/main.xml`、`/res/main.xml` | LuaDB 把 `code/` 的目录树**原样打包**，XML 落在 `/luadb/res/` 下；模拟器把脚本目录挂成根，所以只在真机暴露 | 候选路径补上 `/luadb/res/main.xml` |
| `Unsupported element ... slider` | `slider` / `animimg` 是 **PLCUI 1.0.2（2026-11-13）** 才加的，设备固件是 11-12 的 1.0.1 | 去掉滑块，背光改成「大号数值 + 三档按钮」 |
| `Unknown attribute: fit` | `fit` / `src-x` / `crop` 同样是 1.0.2 的属性 | 不依赖拉伸图，改纯标签显示 |

`E/pwm setup ch 3` 是**已知的虚假报错**：固件在 `LUAT_CONF_PWM_MAXID` 未定义时无条件打印，通道 ≤5 实际是成功的（见 `demo/plcui/plcui_injection_hmi/code/boot_app.lua` 的注释），背光正常。

**结论**：这套界面只用到了 1.0.1 就有的组件（container / label / image / table / chart），所以能在现成固件上直接跑；
若要使用 `slider`、`animimg`、图片裁剪旋转等能力，必须换 11-13 之后编译的固件。

## 在 PC 模拟器上跑

```powershell
cd bsp\pc
build\out\luatos-lua.exe --headless --agent-ctl=127.0.0.1:9966 ^
    ..\..\module\Air8607\project\mmy_cdu_plc\code
```

页签中心 x = 400 / 502 / 604 / 706 / 808，y = 48。
