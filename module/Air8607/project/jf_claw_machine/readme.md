# 欢乐抓娃娃（Claw Machine）

Air8607 大屏触摸"抓娃娃机"游戏 demo。在 7~10.1 寸触摸屏上模拟经典娃娃机玩法：
长按左右键（或点玻璃柜任意位置）移动爪子，对准台面上的娃娃按下"抓取"，
爪子下探闭爪、抓中就吊着摇摆运到出货口放下，抓空就抬爪提示再试。
纯 `airui.shape` 图元实时绘制，不依赖任何图片资源；音效由 Lua 合成 PCM
经 `exaudio` 流式播放，也不依赖音频资源文件。

## 硬件要求

| 项 | 要求 |
|---|---|
| 核心板 | Air8607（factory/core 支持 `air8607_10i` 档位；其他板走内置屏路径） |
| 屏幕 | RGB565 7~10.1 寸，1024*600（默认 `air8607_10i`，exd_jd9165ba_rgb 初始化） |
| 触摸 | GT911 电容触摸（点按/长按/拖动） |
| 音频 | 可选。板载 HT6873 功放（pa_ctrl=GPIO73），无音频后端时静默降级 |
| 显示接口 | 50PIN RGB LCD；PC 模拟器或非 air8607 板自动跳过整机 init 与背光 |

板级兼容行为与 `cqd_LuckyWheel` 完全一致（同一份 `board.lua` / `exd_jd9165ba_rgb.lua`）。

## 玩法

1. **移动爪子**：长按"左移/右移"按钮，或直接点按/拖动玻璃柜内任意位置（爪子自动移过去）。
2. **抓取**：按下"抓 取"。爪子下探 → 闭爪 → 判定 → 升起。
3. **判定**：爪子中心与娃娃中心距离在容差（capture_pad）内才有机会抓中；
   越接近正中成功率越高（基础 62% + 对准加成最高 33%）。抓中后娃娃随爪子
   弹簧摆动运到出货口，松爪下落入洞，"抓中"计数 +1。
4. **补货**：台面娃娃被抓完自动补货，可一直玩下去。
5. 右上角状态卡实时显示当前阶段、抓中/尝试次数与命中率；点击"音效"徽章可开关音效。

## 目录结构

```
cqd_ClawMachine/
├── readme.md
└── code/
    ├── main.lua                 入口：板级 init + 帧率守卫主循环
    ├── config.lua               布局常量 + 玩法调参 + 娃娃阵容
    ├── claw_model.lua           游戏状态机（纯 Lua，step(dt) 驱动）
    ├── ui.lua                   图元绘制 + 标签层 + 触摸交互
    ├── sfx.lua                  音效合成 + exaudio 流式播放
    ├── rng.lua                  随机数（trng 优先，LCG 兜底）
    ├── board.lua                板级兼容初始化（同 cqd_LuckyWheel）
    ├── exd_jd9165ba_rgb.lua     10.1 寸 RGB 屏初始化（同 cqd_LuckyWheel）
    ├── clock_ms.lua             时钟（真机/PC 统一毫秒，含回绕）
    ├── frame_pacer.lua          帧率控制器（固定步长 + 卡顿钳制）
    └── fx.lua                   图元池（同 air8607_demos/ui/fx.lua）
```

## 核心流程

```
main 帧循环（固定周期 40ms，sys.timerLoopStart，失败回退 deadline task）：
  now = Clock.now()
  due, skipped, late = pacer:due(now)      -- 迟到跳帧，不补偿渲染耗时
  model:step(Clock.elapsed(now, previous)) -- 纯逻辑推进（含 250ms 卡顿钳制）
  view:render(model:snapshot())            -- 只读快照渲染
触摸事件（airui.touch_subscribe）：
  TP_DOWN → 命中判定 → model:input(-1/1) / model:grab() / model:target(x)
  TP_HOLD → 柜内拖动跟手 model:target(x)
  TP_UP   → model:input(0) 松开
```

状态机：`IDLE → DROP → GRAB → LIFT → CARRY → RELEASE → RESULT → IDLE`，
抓取判定在 GRAB 闭爪完成瞬间执行；出货娃娃走独立下落物理，落洞即消失计分。

## 验收

- 上电后约 1 秒进入主界面：顶部标题/徽章、左侧玻璃柜（轨道、6 只娃娃、出货口）、
  右侧状态卡 + 三个按钮。
- 爪子初始在柜中上方轻微静止；长按左右按钮爪子平滑移动并限位。
- 点玻璃柜内任意位置，爪子自动移向该处。
- 按"抓 取"后完整播放：下探 → 闭爪 → 升起 →（抓中时吊挂摆动）→ 出货口松爪 →
  娃娃下落入洞 → 结果提示 → 回到 IDLE。
- "抓中/尝试/命中率"实时更新；娃娃抓完自动补货。
- 点"音效"徽章可切换静音；无 exaudio 后端时游戏正常运行且无报错。

## 调参

全部在 `config.lua`：

| 参数 | 含义 | 默认 |
|---|---|---|
| `claw_speed` | 爪子横移速度 px/s | 420 |
| `drop_speed` / `lift_speed` | 下探 / 回升速度 px/s | 520 / 380 |
| `grab_chance` | 对准后基础成功率 | 0.62 |
| `align_bonus` | 完美对准追加成功率 | 0.33 |
| `capture_pad` | 抓取判定容差 px | 18 |
| `result_hold_ms` | 结果提示停留 | 1400 |
| `toys` | 娃娃阵容（x/kind/color） | 6 只 |
| `sfx_vol` | 音效音量 0~100 | 30 |

## 实现要点（踩坑约定）

- **坐标全部取整**：LVGL 整数坐标，小数被 C 层截断会让图元凭空消失
  （图元池内部已统一 `math.floor`）。
- **shape 与 label 叠放**：LVGL9 后建的同级控件在上层，本工程先建 `airui.shape`
  再建 `airui.label`，文字天然压在图形之上（air8607_demos 的"shape 盖住 label"
  是因为其外壳先建 HUD 标签、后建舞台容器）。
- **文本缓存节流**：`set_text` 触发 LVGL 文本重排，逐帧刷新会拖慢帧率，
  UI 层对所有动态文本做了变化检测。
- **卡顿钳制**：`model:step` 把 dt 钳制到 250ms，菜单切回/调试断点不会让
  动画瞬移穿帮。
- **音效合成**：正弦滑频 + 指数包络生成 16kHz/16bit/单声道 PCM 一次性入队，
  `play_start` 忙时直接丢弃，绝不阻塞游戏循环。

## 相关文档

- `module/Air8607/project/cqd_LuckyWheel/readme.md`：同板级交互 demo 约定
- `module/Air8607/project/air8607_demos/readme.md`：图元动画合集与更多踩坑记录
