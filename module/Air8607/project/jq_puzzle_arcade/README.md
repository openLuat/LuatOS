# 益智乐园（puzzle_arcade）

给 6~10 岁孩子玩的横屏益智游戏合集：**七款小游戏 + 一个成绩排行榜**，跑在 Air8607 + 10 寸 RGB 屏上。
纯 Lua + AirUI（LVGL 9 封装），**零图片素材**——所有画面（棋盘、卡片、徽章、图标）都由 `airui.shape` 的
line / dot / ring / rect / arc 图元每帧现算。

```
1024x600 横屏   GT911 电容触摸   30fps 主循环   掉电保存成绩
```

---

## 硬件与运行环境

| 项目 | 配置 |
| --- | --- |
| 主控 | Air8607 |
| 屏幕 | 10 寸 RGB 接口屏，1024x600，免初始化序列 |
| 触摸 | GT911 电容触摸（I2C1，400kHz） |
| 引脚 | LCD 复位 GPIO15 / LCD 供电 GPIO17（低有效）/ 背光 PWM3（GPIO13）/ 触摸 pin_rst=14 pin_int=51 |
| 依赖库 | `airui`、`display`（或 `lcd`）、`tp`、`fskv`、`mcu`、`pwm`、`gpio`、`i2c` |

引脚与 `module/Air8607/project/factory/config/eng_8607_10i_v0.lua` 对齐。
`fskv` 不可用时成绩只存在内存里（重启清零），日志会提示
`成绩榜: fskv 不可用，只在内存里保存`。

---

## 目录结构

```
code/
├── main.lua                入口：PROJECT/VERSION + require app_main + sys.run()
├── app/
│   ├── app_main.lua        板级初始化与启动编排（供电 / 显示 / 字体 / 触摸 / 主循环）
│   └── records.lua         成绩榜存储：每款游戏前 5 名（fskv 掉电保存 + 内存缓存）
├── drv/
│   └── lcd/exd_air8607_rgb.lua  RGB 屏初始化扩展库（1024x600 免序列，双后端自动降级）
└── ui/
    ├── theme.lua           设计令牌：配色 / 坐标 / 字号 / 按钮样式 / 刷新预算
    ├── fx.lua              绘图工具：图元对象池、颜色、缓动、图标
    ├── ui_main.lua         UI 入口：只暴露 build / run
    ├── ui_shell.lua        外壳：顶栏 HUD + 舞台页面调度 + 底部栏 + 触摸手势 + 主循环
    ├── ui_home.lua         大厅：4x2 八张卡（七款游戏 + 排行榜）+ 实时预览
    ├── ui_rank.lua         排行榜页：左侧 7 个游戏标签 + 右侧前 5 名
    ├── ui_overlay.lua      通用弹窗（全屏唯一一套，两个按钮）
    └── games/
        ├── g2048.lua       数字 2048（滑动合并）
        ├── g_puzzle.lua    数字华容道（SLIDE 15）
        ├── g_memory.lua    翻牌记忆（八对）
        ├── g_mines.lua     小扫雷（6x6 / 8 雷）
        ├── g_pipes.lua     接水管（6x6 连通）
        ├── g_simon.lua     记顺序（四色块序列）
        └── g_gomoku.lua    五子棋（11x11，人机 / 双人）
```

脚本按**裸文件名** require（`require "ui_shell"`），下载到设备时需把 18 个 `.lua` 全部平铺到同一目录。

---

## 启动流程

`main.lua` → `app_main.lua`：

1. `power_on()`：背光 PWM3 占空比 0（先黑屏）、LCD 供电/复位脚、I2C1
2. `exd.setup({pin_rst = 15})`：复位 + RGB 时序 + 帧缓冲
3. `airui.init(1024, 600)` + `font_load` 逐个加载 `theme.font_sizes`（11/13/16/22/26/30/48）
4. `math.randomseed`：每局出题不同
5. `ui_main.build()`：搭 HUD + 舞台 + 底部栏 + 弹窗，构建大厅页
6. `touch_init()`：GT911 初始化并 `airui.device_bind_touch`
7. 起一个 task 跑 `ui_main.run()`（30fps 主循环），最后 `backlight_on()` 防上电花屏

> 触摸绑定**必须**早于动画任务：先起动画再绑定，动画会抢在绑定完成前每帧 `set_items`，
> 表现为"日志说初始化完成但点不动"。

---

## 页面模型

切换页面只做 `container:set_hidden(true/false)`，**不销毁不重建**：

| 序号 | 页面 | 说明 |
| --- | --- | --- |
| 1 | 大厅 | 4 列 x 2 行，241x218 卡片；第 8 张是排行榜入口 |
| 2..8 | 七款游戏 | 顺序与 `ui_shell.GAMES` 一致 |
| 9 | 排行榜 | 不是 `is_home`，但有 `restart = refresh` |

- 大厅第 i 张卡 → `M.open(i + 1)`。
- 每个页面 = 一个容器 + 一个 `shape`（图元池）+ 一批 `label`；**shape 必须先建**（LVGL 后建的画在上层）。
- 每帧只有当前页 `update`，隐藏页的计时 / 动画 / 电脑思考自然冻结 →
  **回大厅再进来就是接着上次玩**；新开一局只能靠底部「重玩」或结算弹窗「再玩一次」。
- 页面对象约定：

```lua
M.build(root, W, H, host) -> o
o.update(P, t, dt)   -- 每帧把画面写进图元池
o.onTap(x, y)        -- 短按（扫雷另有 onLongTap 插旗，2048 用 onSwipe）
o.stats()            -> 两行 HUD 文字
o.restart()          -- 新开一局
o.onEnter()          -- 可选：进入页面时刷新文字
o.is_over()          -- 可选：外壳据此把底部提示换成"按重玩再来一盘"
```

`host` 由外壳注入（游戏不 require 外壳，避免循环依赖）：

```lua
host.best(key)                     -- 榜首成绩，没记录返回 0
host.save(key, value)              -- 越大越好，返回名次 1..5 / nil
host.save_min(key, value)          -- 越小越好，返回名次 1..5 / nil
host.win(title, body)              -- 绿色过关弹窗
host.lose(title, body)             -- 橙色结束弹窗
host.notice(title, body, btn, fn)  -- 黄色提示弹窗
host.confirm(title, body, ok, fn)  -- 红色二次确认（默认按钮是"先不清空"）
```

---

## 七款游戏与成绩方向

| 游戏 | 玩法 | 记录键 | 方向 | 榜单文案 |
| --- | --- | --- | --- | --- |
| 数字 2048 | 4x4 滑动合并，合出 2048 提示后仍可继续冲分 | `arcade_2048` | 越大越好 | `4096 分` |
| 数字华容道 | 4x4 推盘，1..15 排好且空位在右下 | `arcade_puzzle_moves` | 越小越好 | `45 步` |
| 翻牌记忆 | 4x4 十六张牌，八对全配上 | `arcade_memory_moves` | 越小越好 | `24 次` |
| 小扫雷 | 6x6 / 8 雷，28 个安全格全开（长按插旗） | `arcade_mines_sec` | 越小越好 | `01:23` |
| 接水管 | 6x6 旋转管口，水送到所有格子 | `arcade_pipes_moves` | 越小越好 | `18 步` |
| 记顺序 | 四色块序列越记越长，记错即结束 | `arcade_simon_round` | 越大越好 | `第 6 关` |
| 五子棋 | 11x11，黑先，五连即胜，人机 / 双人可切换 | `arcade_gomoku_moves` | 越小越好 | `18 手` |

每款游戏自己实现三个对外文案函数，大厅与榜单页共用、互不重复拼串：

```lua
M.format_value(v)   -- 榜单页："45 步" / "4096 分" / "01:23" / "第 6 关"
M.format_record(v)  -- 大厅卡片："最好 45 步"
M.rank_hint         -- 榜单页抬头："步数越少越靠前"
```

---

## 成绩与排行榜

存储格式是**紧凑字符串**，不用 json（裁剪固件去掉 json 库时写入会静默失败）：

```
fskv 键: arcade_2048
值:      "4096,1762185600;2048,1762099200"     -- 最多 5 段：值,时间戳
```

- `records.list(key)` 取前 5 名（按"更好"排好序），`records.best(key)` 取榜首。
- `records.submit(key, value, "max"|"min")` 返回名次，没进前 5 返回 `nil`。
- 排序方向写在 `records.POLICY` 里（只有 2048 与记顺序是 `max`），避免 8 个调用点各写一遍。
- 旧版本存的是单个数字，读到 number 会自动迁移成"1 条记录"，老玩家的成绩不丢。
- `os.time()` 未校时（机器还停在 1970）时日期显示 `--`，不显示误导人的 `01-01`。
- 清空走 `host.confirm` 二次确认，默认按钮是「先不清空」。

结算文案统一说人话：进榜就 `上榜啦，第 3 名！`，没进榜回落 `最好成绩 45 步`。

---

## 五子棋的 AI

- 候选点：已有棋子**切比雪夫距离 2 格**内的空位；空盘下天元。
- 评分：对每个候选点分别按"电脑下"（attack）和"对手下"（block）做四方向连通度评分，
  `score = attack + block * 0.9`；两端都被封死（含**棋盘边界**）的棋形打 12% 折扣。
- 取最优，但 **20% 概率故意选次优点**：会堵三连、也会偶尔看漏，孩子才有赢面。
- 电脑 0.4~0.7 秒后才落子（走 `aiTimer` 计时，不 sleep 阻塞主循环）。
- 悔棋：人机撤两步、双人撤一步；思考中、空盘、已结束时不可悔。
- 五连判胜并高亮连子，棋盘下满判和。

---

## 绘制与性能约定

- **图元对象池**：`P:reset()` → 一系列 `P:box / P:dot / P:ring / P:line / P:arc ...` → `P:finish()` 后 `shape:set_items(P.items)`。
  池子复用同一批表，避免每秒上万个临时表引发 GC 顿卡；`finish` 会把尾部残留置 `nil`
  （`set_items` 用 `lua_rawlen` 取长度，尾部留旧表会画出上一帧的图元）。
- 每个写入方法都**重写该图元的全部字段**，不依赖上一帧的默认值。
- 坐标一律 `math.floor` 取整（LVGL 用整数坐标，小数截断方向不一致会出现接缝）。
- 30ms 一帧（避开 LVGL 33ms 刷新拍频）；HUD 文字 200ms 刷一次（`set_text` 会重排文本产生脏区）。
- 文字做去重：只有内容变了才 `set_text`。
- AI、候选点缓冲等热点路径**预分配表**，不每帧新建。

---

## 字体与文案约束

- `hzfont` 没有中间点 `·`、度数 `°`、乘号 `×`、箭头 `→`、`『』` 等符号，用了会显示方框；
  界面只写 ASCII + 汉字，分隔统一用 `/`，时间写 `01:23`。
- 主题色（糖果色）直接当文字写会糊，必须 `fx.shade(color, -0.3)` 压暗再用。
- 用到的字号必须都在 `theme.font_sizes` 里，否则 `font_load` 没加载、文字不显示。

---

## 新增一款游戏

1. 新建 `ui/games/g_xxx.lua`，导出 `id / name / en / desc / tip / accent / record_key / rank_hint / rules`，
   以及 `format_value`、`format_record`、`preview(P,x,y,w,h,t)` 和返回页面对象的 `build`。
2. 在 `ui_shell.lua` 的 `GAMES` 末尾追加 `require "g_xxx"` —— 页面序号与大厅卡片会自动跟着排。
3. 若这款游戏"越大越好"，在 `records.POLICY` 里加一行 `arcade_xxx = "max"`。
4. 字号只能从 `theme.font_sizes` 取；卡片描述控制在两行以内（241 宽 ≈ 16 个 13px 汉字）。

---

## 常见坑

| 现象 | 原因 / 处理 |
| --- | --- |
| 初始化日志正常但点不动 | 触摸绑定晚于动画任务；`tp.init` 必须给 `w`/`h` |
| 页面文字被遮住 | `shape` 建得比 `label` 晚；先建 shape 再建 label |
| 想临时藏一个 label | LVGL label 没有 `set_hidden`，用 `set_text("")` 或藏外层容器 |
| 上一帧图元残留 | `finish()` 未截断尾部，或某方法没写全字段 |
| 结算后回到游戏又弹一次窗 | 会重复写成绩；用 `o.is_over()` 只改底部提示 |
| 回到游戏发现是新的一局 | 检查是否在切页路径里调了 `restart`；只有「重玩」才允许 |
| 文字显示方框 | 用了 hzfont 缺失的符号，或字号不在 `theme.font_sizes` |

---

## 上机检查清单

1. 大厅 8 张卡正好铺满、文字不溢出，第 8 张是排行榜。
2. 玩一局 → 结算出现「上榜啦，第 1 名！」→ 回大厅卡片成绩已更新。
3. 排行榜：左右切换跟手，第 1 名金底 + 金环，日期 `11-03`（未校时显示 `--`）。
4. 清空：弹窗「先不清空」不删、「确定清空」后 5 行清空；空榜显示「还没有成绩 / 快去玩一局吧！」。
5. 断电重启后榜单仍在（`fskv` 可用时）。
6. 任意游戏玩到一半回大厅再进来：棋盘、步数、用时都在；按「重玩」才是新局。
7. 五子棋：吸附落子、电脑 0.4~0.7 秒后回子、思考中不能悔棋、五连高亮、切换模式自动重开。
