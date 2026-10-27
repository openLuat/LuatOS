# air8607_demos — Air8607 工业场景 UI 演示

面向 Air8607 + 10 寸 RGB 屏（1024x600 + GT911 触摸）的工业风格 UI 演示合集，
用于展示 Air8607 在实际工业场景中的应用形态。全部视觉由 `airui.shape`
图元实时计算生成，不依赖任何图片资源。

## 目录结构

```
air8607_demos/
├── main.lua                入口：仅加载 app_main + ui_main
├── app/app_main.lua        硬件初始化 + 启动编排（供电/显示/触摸/背光）
├── drv/lcd/exd_air8607_rgb.lua   10寸 RGB 屏初始化扩展库
└── ui/
    ├── ui_main.lua         UI 薄入口（转发 build/run）
    ├── ui_demos.lua        演示外壳：HUD + 舞台 + 切换栏 + 自动轮播
    ├── fx.lua              图元池 / 配色 / 缓动 / 圆弧工具库
    ├── demo_power.lua      场景 1 智慧配电房电力运维
    ├── demo_pump.lua       场景 2 智慧泵站
    ├── demo_line.lua       场景 3 智能产线
    ├── demo_env.lua        场景 4 环保监测
    └── demo_energy.lua     场景 5 储能管理
```

## 场景 demo 契约

每个场景是**一个独立文档**，对外只暴露 3+2 个字段：

```lua
local M = { id = "power", name = "配电房", desc = "…" }

function M.build(root, W, H)   -- 在 root 容器内搭建静态控件，返回场景对象 obj
    ...
    return obj                 -- obj 含 shape/label 引用与 obj.n（图元计数）
end

function M.update(obj, t, dt)  -- 每帧刷新：obj.shape:set_items(P.items)
    ...
end

return M
```

新增场景只需：新建 `ui/demo_xxx.lua` 按契约实现，然后在
`ui/ui_demos.lua` 的 `SCENES` 表追加一行 `require "demo_xxx"`。

## 编写要点（踩坑记录）

- **坐标必须取整**：LVGL 整数坐标，小数在 C 层被截断，宽度/透明度归 0
  会让物件"凭空消失"。图元池内部已统一 `math.floor`。
- **数字单位字形**：hzfont 无 `³`、`₂` 等上/下标字形（显示为 `□`），
  单位写 `m3`、`ug/m3`、`SO2`；`℃`、`μ` 可用。
- **文字与能量条分行**：shape 图层会盖住 label，同一行横排"文字+能量条"
  必然叠画。规范为：文字一行（h=20）、能量条位于文字行下方 22px。
- **文本 250ms 节流刷新**：`set_text` 触发 LVGL 重排文本，逐帧刷新会拖慢帧率。
- **动画时间基准**：`tick 差 / mcu.hz()` 折算毫秒（真机 hz=50，PC 模拟器 hz=1），
  外壳已处理 uint32 回绕与固定步长补偿。

## 运行

真机烧录按 Air8607 工程惯例；PC 模拟器验证：

```powershell
# 启动无头模拟器（截图验证流水线，见 luatos-sim-verify 技能）
python <skill>/scripts/sim_run.py start --exe bsp\pc\build\out\luatos-lua.exe `
    --cwd bsp\pc --project module\Air8607\project\air8607_demos --port 18901
python <skill>/scripts/shot.py --port 18901 --out frame.png
python <skill>/scripts/sim_run.py stop
```

界面交互：底部 pill 按钮点击切换场景，"自动轮播"按钮控制 12s 自动轮播；
顶栏 HUD 显示当前场景名、动画 FPS / LVGL FPS、图元数与每帧计算耗时。
