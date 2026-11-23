# 智能注塑车间 · 1# 产线监控总览（PLCUI / Air8607）

10 寸 1024×600 工控 HMI，工业拟物风格。四页：总览 / 趋势 / 报警 / 参数。
参考稿是 `工业HMI界面/hmi-prompt-lab/case-06.html`（1400×872），按 SKILL 的五环节流程落到 PLCUI。

## 一、目录

```
plcui_injection_hmi/
├── design/                  环节① 原型与文档（唯一视觉事实来源）
│   ├── index.html           1024×600 四页可交互原型（浏览器直接打开）
│   ├── theme.css            视觉唯一来源，index.html / sheet.html 共用
│   ├── sheet.html           49 张素材瓦片的排布页（导出脚本自动生成）
│   ├── spec.md              元素/资源/坐标/绑定变量对照表（脚本生成，别手改）
│   └── fallback.md          降级清单：做不到的效果改成了什么
├── tools/                   环节② 导出与自检
│   ├── tiles.py             49 条瓦片定义（唯一来源，sheet 与裁剪共用）
│   ├── export_assets.py     瓦片 → PNG；四页 → 背景图；JSON → main.xml
│   ├── spec_gen.py          main.xml + ui_vars.lua → design/spec.md
│   ├── preview.py           main.xml + 图片 → preview/device_*.png（PIL 合成）
│   ├── pc_verify.py         PC 模拟器端到端验证（真 LVGL 渲染 + 20 条断言）
│   ├── pc_verify/main.lua   上面那个脚本丢进模拟器里跑的探针
│   └── check.py             语法 / 规范 / XML / 取值域 / 字形 / 绑定表 / 文档 自检
├── code/                    环节③④ 真机工程（烧进 /luadb）
│   ├── main.lua             纯加载器（末尾 sys.run()）
│   ├── boot_app.lua         上电时序、显示/触摸初始化、两个定时器
│   ├── ui_app.lua           界面加载、切页、刷数、事件表 H
│   ├── ui_vars.lua          绑定表：组件 ← 变量
│   ├── data_app.lua         业务数据与工艺量模拟
│   ├── exd_air8607_rgb.lua  10 寸 RGB 屏驱动（板级）
│   ├── tp_app.lua           GT911 电容触摸（板级）
│   └── res/                 main.xml + 52 个资源（平铺，不分子目录）
├── preview/                 四页等效渲染图（设备上的样子）
└── build/                   中间产物（底图、瓦片拼接图），不参与烧录
```

## 二、界面功能

| 页 | 内容 | 可操作 |
|---|---|---|
| **总览 overview** | 4 个 KPI（当班产量 / OEE / 模温 / 节拍）、双机械仪表（模温、射胶压力）、4 条趋势曲线（温度 / 压力 / 设定）、3 张设备卡（状态灯 + 负载条 + 详情）、3 条报警摘要 | 启动 / 停止 / 复位 / 急停、选设备、确认报警、温度设定滑块 |
| **趋势 trend** | 大图 80 点三系列曲线、四个统计盒（当前 / 峰值 / 均值 / 设定偏差） | 温度设定滑块 |
| **报警 alarm** | 6 列 × 7 行报警表（时间 / 来源 / 描述 / 级别 / 状态 / 操作） | 一键确认、清除已确认、页签切页 |
| **参数 settings** | 6 个控制器参数输入框、3 个拨动开关、背光亮度滑块 | 输入确认 / 取消、开关、滑块、保存下发 |

四页共用一套机箱壳：顶栏（班次 / 时钟 / 状态灯 / 急停旗标）、底栏（累计产量 / 页签 / 设定值 / 旋钮）、左侧控制区（四键 + 管路流动 + 设定滑块）。

## 三、操作步骤

### 3.1 主控四键

| 键 | 效果 |
|---|---|
| **启动** | `st.running = true`，状态灯转绿、管路条纹开始流动、KPI 恢复实时值 |
| **停止** | `st.running = false`，状态灯转黄（待机）、条纹定格第 0 帧、OEE 与节拍显示 `—` |
| **复位** | 清急停标志，恢复运行态配色 |
| **急停** | **按两下**：第一下进「急停待确认」（按钮变按下态、顶部状态文字变成"急停待确认"），5 秒内再按一次才真正停机；超时自动解除 |

> 急停为什么是两下：网页版用的是模态弹窗二次确认，PLCUI 没有弹层组件，改成两级按。见 `design/fallback.md`。

### 3.2 设备卡

点任一张设备卡（`sel0/1/2`）→ 卡片进入选中态，右侧详情面板换成该台设备，再点一次取消选中回到「全线综合参数」。

### 3.3 报警

- 单条「确认」：该行按钮变灰不可点（`src-disabled`），未确认计数 -1，页签红点数字跟着减。
- 「一键确认」：所有未确认清零，页签红点与数字一起隐藏。
- 「清除已确认」：从表里移除已确认记录，后续记录上移。

### 3.4 参数页

- 点参数框 → 弹出数字软键盘（`kb_num`）→ 确认写入 / 取消回滚。
- 每个参数有量程，越界不落盘，界面回滚到旧值（日志 `参数写入被拒`）。
- 「保存下发」写入控制器（模拟），底部提示文字更新，数值来自 `data_app.commit_params()`。
- 背光亮度滑块拖动即时生效（PWM3 占空比直连）。

### 3.5 数据刷新节奏

| 定时器 | 周期 | 干什么 |
|---|---|---|
| `boot_app.refresh_tick_cbfunc` | 1000 ms | `data_app.step()` 推一步工艺量 + `ui_app.refresh()` 刷当前页 |
| `boot_app.flow_tick_cbfunc` | 200 ms | 管路流动条纹换帧（`flow_0..flow_3`） |
| `ui_app` 切页定时 | 40 ms | 切页后延时刷一次（PLCUI 要求，句柄要重新 find） |

## 四、接线（Air8607 整机）

| 功能 | 引脚 / 总线 | 说明 |
|---|---|---|
| 10 寸 RGB 屏 | `exd_air8607_rgb`（RGB 接口 + 内部 SPI 初始化） | 1024×600，`exd.setup({pin_rst = 15})` |
| 屏幕复位 DISP | GPIO15 | 上电拉高 |
| LCD 供电 | GPIO17 | **低有效**，上电拉低 |
| 背光 | PWM3 / 1 kHz | 占空比 = 亮度百分比，0 为全黑 |
| 触摸 GT911 | I2C1（`i2c.FAST`） | 复位由 `tp_app` 处理，中断默认接法见 `tp_app.lua` |
| 串口（接 PLC / 上位机） | UART1 | 本工程未启用，接真设备时在 `data_app` 里加收发 |

上电时序（`boot_app.power_on`）：关背光 → 给屏供电 → DISP 拉高 → I2C 初始化 → 等 120 ms → 屏初始化 → 载入界面 → 绑触摸 → **最后才点背光**（避免用户看到半张界面）。

## 五、资源清单

52 个资源，全部平铺在 `code/res/`，文件名（含扩展名）≤ 23 字节。完整表格见 `design/spec.md` 第三节。

| 类别 | 数量 | 例 |
|---|---|---|
| 整页背景（JPG，1024×600） | 4 | `bg_ov` / `bg_tr` / `bg_al` / `bg_st` |
| 机械仪表 | 2 | `nd_needle`（96×96 指针，绕 pivot 旋转）、`g_cap`（中心盖） |
| 状态点 / 指示灯 | 7 | `dot_run` / `dot_idle` / `dot_fault` / `dot_off` / `lamp_run` / `lamp_idle` / `lamp_alarm` |
| 按钮四态（含按下态） | 20 | `btnstart_n/p`、`estop_n/p`、`btnackall_n/p`、`btnsave_n/p`… |
| 页签选中 / 未选中 | 8 | `tab_ov_n/c`、`tab_tr_n/c`、`tab_al_n/c`、`tab_st_n/c` |
| 管路流动条纹（4 帧） | 4 | `flow_0` ~ `flow_3`（96×14 透明 PNG） |
| 负载条填充（三色） | 3 | `barfill_g` / `barfill_i` / `barfill_f`（296×6） |
| 其它零件 | 4 | `knobsp`（旋钮）、`thumb`（滑块帽）、`badge`（页签红点）、`flag`（急停旗标）、`arr_n/c`、`ack_n/p/d`、`sw_on/off` |

## 六、烧录

### 6.1 luadb 必须平铺

`code/res/` 只用于源码组织，**打包时所有文件要抹平到同一层**：

```
/luadb/main.lua
/luadb/boot_app.lua
/luadb/ui_app.lua
/luadb/ui_vars.lua
/luadb/data_app.lua
/luadb/exd_air8607_rgb.lua
/luadb/tp_app.lua
/luadb/main.xml
/luadb/bg_ov.jpg  ... 其余 51 个资源
```

`main.xml` 与图片必须同目录（`ui_app` 按 `/luadb/main.xml` → `/res/main.xml` → `/main.xml` 顺序找）。

### 6.2 两种烧法

1. **Luatools（最省事）**：先 `python tools/make_dist.py`，生成的 `dist/luadb/` 就是**已经铺平**的 61 个文件（7 个 lua + 54 个资源）。Luatools 新建项目时「选择目录」直接指 `dist/luadb`，选 Air8607 + 对应固件 → 下载。不用手工挑文件，也不会漏 `main.xml`。
2. **手工拖**：把 `code/` 下 7 个 `.lua` 与 `code/res/` 下所有文件**一起**拖进脚本区（不建子目录）。
3. **PC 模拟器**：见第七节 `tools/pc_verify.py`，它会自己铺临时目录，不用管这里。

### 6.3 前提

- 固件必须开启 `LUAT_USE_PLCUI`，否则 `plcui.init` 直接失败，日志打「plcui.init 失败」。
- PLCUI 与 AIRUI 互斥，同一固件不能同时开。

## 七、自检与验证

```bash
# 语法 + 规范 + XML 取值域 + 字形覆盖 + 绑定表 + 文档 六段自检（全 OK 才算过）
python tools/check.py

# 重新导出素材瓦片（改过 tools/tiles.py 之后跑）
python tools/export_assets.py --sheet

# 重新导出四张底图 + main.xml（改过 design/ 之后跑）
python tools/export_assets.py --pages

# 重新生成 spec.md（main.xml 变了就跑一次）
python tools/spec_gen.py

# 按 main.xml 合成四页等效渲染图（PIL 版本，快）
python tools/preview.py

# 真·LVGL 端到端：四页 + 20 条交互断言 + 13 张真实渲染图
python tools/pc_verify.py
```

`check.py` 会核这些：7 个 `.lua` 语法解析、无匿名函数 / 无 `local M`、模块表名 = 文件名、`require` 只写文件名且目标存在、`main.lua` 是纯加载器且末尾 `sys.run()`、XML 根元素与页数、资源 ID 唯一、组件 ID 页内唯一、`font_size` 拼写、`hidden`/`clickable` 是 true/false、23 个事件全在 `ui_app.handlers`、`src` 全部已声明、文件名 ≤23 字节、chart 点数/系列数/值域、table 行高不溢出、textarea 的 keyboard 同页存在、绑定表的组件与变量都真实存在。

**`check.py` 里的「schema 取值域」那一段是照着固件源码 `luat_plcui_xml.c` 抄的**：属性名白名单 + 每个整型属性的上下限 + 一堆交叉约束（`clickable` 配 `on-click`、`fit=center` 配 `rotation`、旋钮图正方形…）。这些在设备上任意一条不满足都会让 `plcui.load` 返回 `E_SCHEMA`，**而日志只给一句 `Integer attribute is invalid or out of range`，不告诉你是哪个属性**——所以务必在 PC 侧先跑过。

`pc_verify.py` 直接调本机 LuatOS PC 模拟器跑真实 PLCUI：铺一个临时 app 目录（`data_app` / `ui_app` / `ui_vars` + 平铺的 `res/`），跑完四页与事件，把断言结果写 `build/pc_verify.log`，把模拟器出的位图转成 `preview/sim_*.png`。模拟器偶发启动崩溃（与本工程无关），脚本会自动清 `pclogs/*.dmp` 并重试 3 次。

## 八、上机日志怎么看

正常启动应有四条：

```
I/user.main plcui_injection_line 1.0.0
I/user.boot 启动 plcui_injection_line 1.0.0
I/user.exd_air8607_rgb 显示初始化完成 backend=display 1024x600
I/plcui.display RGB565 1024x600 draw=1228800 scan=2 cache=6291456
I/user.ui plcui 初始化完成 init({width,height})
I/user.boot 界面已就绪，四页可切换
```

两条**看着像错误、其实是噪声**的行，不用管：

| 日志 | 说明 |
|---|---|
| `E/pwm setup ch 3` | LuatOS 的 `luat_lib_pwm.c` 在 `LUAT_CONF_PWM_MAXID` 未定义时**无条件**打这行；通道 3 在 1..5 内，`pwm.setup` 实际成功，背光正常 |
| `W/gpio gpio setup fail pin=17 ret -1` | 本版固件 pinmux 把 GPIO17 关了（LCD 供电由硬件常使能），`gpio.setup(17,0)` 返回 0 属正常，代码已跳过 |
| `W/rgb_lcd rgb spi pins(cs/scl/sdi) not configured` | 本屏是 RGB 免序列屏，没有 SPI 初始化序列，跳过是对的 |

真出问题看这两行：

```
E/user.ui 加载失败 /luadb/main.xml <message> | code=... attr=... line=... col=...
E/user.boot 界面加载失败，请检查 main.xml 与图片是否同目录
```

`attr` 就是出问题的属性名（`ui_app` 已经把错误表的 `attribute/line/column` 一并打出来）。
最常见的三种：`w`/`h` 为 0、属性拼错、`pivot`/`rotation` 少了 `fit="center"`。

## 九、已知限制

完整清单见 `design/fallback.md`，最需要知道的三条：

1. **急停按两下**（无模态弹窗）。
2. **报警表固定 7 行**（含表头），无表内滚动，一屏看 6 条。
3. **曲线无面积填充、无阈值参考线**（阈值烘在背景图里，改阈值要重出底图）。

另外三条是上机后才知道的：

4. **`hzfont` 不是全字库**：`± · ℃ ° ■ ★ ▲ ① × ÷` 有字形，`— ▣ ⚠ ▶ ✓` 没有，用了会显示空心方块。改文案时要么用列表里有的符号，要么跑 `check.py` 让它拦。
5. **滑块旋钮图必须正方形**，边长等于滑块短边；改滑块高度就要重出 `thumb.png`。
6. **`table` 不能按行改颜色**，已确认行只能靠文字（`待处理` / `已归档`）区分。
