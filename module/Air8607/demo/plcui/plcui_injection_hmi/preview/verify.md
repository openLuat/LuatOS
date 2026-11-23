# 环节⑤ 验证记录

日期：2026-11-16　平台：Air8607（Air1603）/ 1024×600 / PLCUI

## 一、验证方式（以及边界）

这一轮把验证从「静态检查 + 自己画的仿渲染」推到「真的在 LVGL 上跑」：用本机 LuatOS PC 模拟器
（`C:\gitee\LuatOS\bsp\pc\build\out\luatos-lua.exe`）加载同一份 `main.xml`、同一份 `data_app` /
`ui_app` / `ui_vars`，跑完四页 + 23 个事件，并由模拟器出真实位图。

| 线 | 工具 | 验的是什么 | 覆盖不到什么 |
|---|---|---|---|
| **A. 静态自检** | `tools/check.py` | Lua 语法、代码规范、XML 合法性与**取值域**、字形覆盖、绑定表一致性、文档齐备 | 运行时行为 |
| **B. 模拟器端到端** | `tools/pc_verify.py` | 真实 PLCUI（LVGL）渲染 + 20 条交互断言 + 13 张设备分辨率位图 | 板级硬件（背光 PWM、GT911 触摸、RGB 上电时序） |
| **C. PIL 仿渲染** | `tools/preview.py` | 只读 XML 贴图/写字/画线，快速核坐标与字号 | 与 LVGL 的渲染差异 |

> B 线是本轮新增的，也是**唯一能抓到「文字变成 `table: 0x...`」这类问题**的手段：那是渲染出来才看得见的 bug。

## 二、A 线：静态自检（45 项通过 / 0 失败 / 1 警告）

完整输出见 `build/check_report.txt`。

- **语法**：7 个 `.lua` 全部通过 Lua 5.3 文法解析（luaparser）。
- **规范**：无匿名函数、无闭包、无 `local M`；模块表名 = 文件名；`main.lua` 是纯加载器且末尾 `sys.run()`。
- **XML 结构**：`<ui version="0.1">` 1024×600 entry=overview；4 页；52 资源 ID 唯一；185 个组件（上限 512）；组件 ID 页内唯一。
- **schema 取值域**（本轮新增，直译 `luat_plcui_xml.c` 的 44 条规则）：属性名白名单、`w/h ≥ 1`、`font_size 1..255`、`point-count 2..1024`、`rows 1..128 / columns 1..16`、`min < max`、`y-min < y-max`、`clickable` 与 `on-click` 配套、`fit=center` 与 `rotation/pivot` 配套、热区不越界、`col-widths` 段数 = `columns`、`rows × row-height ≤ h`、旋钮图必须正方形。
- **字形覆盖**（本轮新增）：固件 `hzfont` 缺 `— ▣ ⚠ ▶ ✓` 字形，代码里不得使用。
- **事件**：XML 里 23 个 `on-*` 全部在 `ui_app.handlers` 同名注册。
- **资源**：52 个文件存在且文件名 ≤23 字节；`src` / `knob-src` 无悬空引用。
- **绑定表**：79 个绑定变量全部由 `data_app.get()` 产出，无笔误。
- **警告（1 条，非缺陷）**：29 个 ID 跨页重名 —— 四页共用的机箱壳，符合「ID **页内**唯一」。

新增校验做过**负向测试**（把 XML 故意改坏再跑），4 个用例全部被拦住：
`h=0 键盘` / `非法属性 data-foo` / `font_size=300` / `缺 fit=center 的旋转指针`。

## 三、B 线：模拟器端到端（20/20 通过）

`python tools/pc_verify.py` 一次跑完，输出 `build/pc_verify.log` 与 `preview/sim_*.png`（13 张真实渲染）：

```
PASS rtos.bsp 是 PC                 PASS 首页是 overview
PASS ui_app.load 成功               PASS 切页 trend / alarm / settings / overview
PASS ack0 让未确认数减一             PASS 全部确认后未确认数为 0
PASS sw1 取反                       PASS 设定值改为 240
PASS 背光改为 55%                   PASS 参数 p1=250 写入成功
PASS 参数 p1=999 被拒绝              PASS tick_flow 连跑 5 次不报错
PASS 停机后 running=false           PASS 启动后 running=true
PASS 急停第一下只进入待确认          PASS 急停第二下真停机
PASS 复位后 estop=false             TOTAL pass=20 fail=0
```

对着真实位图核过的点：

| 页 | 结论 |
|---|---|
| overview | 双仪表指针角度与读数一致（222.3 ℃ / 93.6 MPa），指针旋转中心与中心盖同心；三色曲线在绘图区内，与背景左右双刻度对得上；KPI、设备卡负载条、报警摘要级别配色全对 |
| trend | 三条 80 点曲线连续，四个统计盒一行对齐，单位 ℃ / MPa / ℃ / ℃ 正确 |
| alarm | 表头与六列数据对齐；7 行（含表头）不溢出；`待处理` / `已归档` 文案正常 |
| settings | 六个输入框与标签、单位对齐；三个开关 on/on/off；滑块填充随值变化（55% 时旋钮与填充同时到位）；保存后提示行正确 |
| 急停 | 顶栏红牌、状态灯转红、三台设备全部「急停」、KPI 变 `--`、新增一条严重报警、底栏转「链路告警」 |

## 四、真机日志（2026-11-16 15:56 首次上机）暴露的问题与修复

首次上机 `plcui.load` 直接失败。日志只有一行 `E_SCHEMA: Integer attribute is invalid or out of range`，
不给属性名；把同一份 XML 喂给 PC 模拟器后拿到完整错误表 `{attr=h, id=kb_num, line=251}`，
定位到软键盘的 `h="0"` —— 原型里软键盘是 `display:none`，`getBoundingClientRect()` 返回 0。

随后按「模拟器复现 → 改 → 再跑」的循环修完四处：

| # | 现象 | 根因 | 修复 |
|---|---|---|---|
| 1 | 整页加载失败 | `kb_num` 的 `w/h = 0` | 导出钩子对隐藏元素回退样式取值；导出器断言 `w/h ≥ 1`；`check.py` 补取值域校验 |
| 2 | `E_RESOURCE: Slider knob image must match its square knob dimensions` | 旋钮图 16×22 非正方形 | 改 24×24 圆钮（边长 = 滑块高），原型同步 |
| 3 | 满屏 `table: 0x02FFD4C0` | `refresh` 传了整个数据表给 `apply_bind` | 改 `v[b.var]` |
| 4 | `—` / `▣` / `⚠` 显示空框 | `hzfont` 缺字形（实测 `± · ℃ ° ■ ★ ▲ ① × ÷` 有、`— ▣ ⚠ ▶ ✓` 无） | 占位符 `--`、标题 `■`、告警前缀 `▲`、报警表 `已归档` |

两条日志属噪声，已在 `boot_app` 注释说明：`E/pwm setup ch 3`（LuatOS 遗留无条件日志，通道合法）、
`W/gpio ... pin 17 disable use`（固件 pinmux 已托管 GPIO17）。

## 五、与 SKILL 自检清单逐条对照

| 清单项 | 结论 |
|---|---|
| 参考资料优先，做不到的进降级清单 | ✅ 12 项降级 + 4 项上机修正，全在 `design/fallback.md` |
| 风格统一（一主色 / 四态 / 状态灯 / 栅格） | ✅ 四色 + 四态，栅格 4px |
| 素材走四级取用顺序，来源填在 spec | ✅ 全部「HTML+CSS 自画」 |
| 每个 `on-*` 都在 handler 表 | ✅ 23/23 |
| 组件 / 资源 / 页数 / 体积在上限内 | ✅ 185/512、52/256、4/16、27.6KB/256KB |
| 坐标、资源名、类型、事件名与 spec 一致 | ✅ spec.md 由脚本从 XML 生成 |
| 随数据变的都是活组件 | ✅ 见 spec.md「性质」列 |
| `font_size` 写法正确，文本 ≤511 字节 | ✅ 全下划线；最长单元格约 90 字节 |
| chart 点数合法、换算进 -1000~1000 | ✅ 0~100 归一化，60/80 点与数组等长 |
| table 行数含表头且不溢出 | ✅ 7×42=294 ≤ 300 |
| 切页走延时刷新 | ✅ `sys.timerStart(..., 40)` |
| 严格 boolean 没传 1/0/nil | ✅ `v == true` |
| `main.lua` 纯加载器 + `sys.run()` | ✅ |
| **模拟器跑通、交互实测** | ✅ PC 模拟器 20/20（真机仍待复测） |
| 语法检查通过 | ✅ 7/7 |

## 六、上机必做（本机无法替代的部分）

1. 固件确认 `LUAT_USE_PLCUI` 已开（与 AIRUI 互斥）。
2. 按 `code/readme.md` 6.1 把 7 个 `.lua` + `res/` 下 53 个文件**平铺**到 `/luadb`。
3. 上电应看到四条日志：`boot 启动 … 1.0.0` / `boot 显示就绪` / `ui plcui 初始化完成` / `boot 界面已就绪，四页可切换`。
4. 真机复测六项：页签切页、四键（急停按两下）、设备卡选中、报警确认、参数输入确认/取消、滑块拖动。
5. 重点看三处：仪表指针旋转中心是否偏（偏了说明瓦片 pad 补偿没算对）、管路条纹 4 帧连贯性、背光拖到 0 是否黑到看不见界面（按现场要求调 `data_app.set_bright` 下限）。

## 七、已知残留

- 真机只验证到「加载失败」这一步，修复后的版本**尚未在实机复测**；本轮结论来自 PC 模拟器 + 静态检查。
- PC 模拟器有约 30~50% 的启动竞态（`load/show` 偶发 `ACCESS_VIOLATION`，地址固定 0xBD16），
  `pc_verify.py` 已内置「清 `pclogs/*.dmp` + 最多重试 3 次」。这是模拟器自身问题，与工程代码无关。
