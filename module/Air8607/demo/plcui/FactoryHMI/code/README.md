# FactoryHMI · 3# 配料灌装线（Air8607 / 1024×600）

由 `..\design\index.html` 原型导出的 PLCUI 工程，四页覆盖 PLCUI 全部 7 种组件。

## 目录

```text
D:\PLCUI\FactoryHMI\
  design\            ← 第①环 HTML 原型（index.html / spec.md / _svg 素材）
  tools\             ← PC 端工具：bake_assets.py（素材烘焙）
  plcui\             ← 本目录，烧录到 Air8607 的工程
    main.lua         ← 入口
    main.xml         ← 四页布局
    assets\          ← 59 张素材
```

> LuatOS 的 `require` 只按 `/luadb/xxx.lua` 这种扁平路径查找，**脚本不能放子目录**，
> 所以所有 `.lua` 都平铺在 `plcui\` 根下，靠文件名前缀区分职责（`*_app` 装配、`*_win` 页面）。
> PC 端工具已移出本目录，避免被一起打包进设备。

## 烧录 / 运行

**真机（Air8607，10 寸 1024×600 RGB 屏 + GT911）**：Luatools 新建项目，脚本目录选本目录
（`main.lua` 所在处），资源与 `assets\` 一起下载；固件需带 `LUAT_USE_PLCUI`。

**PC 模拟器**（GUI 版构建）：

```powershell
cd C:\gitee\LuatOS\bsp\pc\build\out
.\luatos-lua.exe D:\PLCUI\FactoryHMI\plcui
```

PC 上会自动按 flow → param → alarm → trend 截图，输出 `shot_<page>.bmp`；
运行时还会生成 `pclogs\`、`pcconf\`、截图，这些都是产物，打包/交付前删掉即可。

## 文件

| 文件 | 作用 |
|---|---|
| `main.lua` | 入口，只按顺序 require 各模块 |
| `main.xml` | 四页布局（1024×600），组件坐标与原型一一对应 |
| `boot_app.lua` | 启动编排：屏幕 → 触摸 → plcui → 界面 → 数据 → 背光 |
| `ui_app.lua` | plcui.load、handlers 注册、切页（延时 30ms 刷新）、刷新调度 |
| `ui_util.lua` | 组件安全访问（find 到 nil 不调用），避免切页异常打挂脚本 |
| `data_sim.lua` | 工艺数据模拟（温度惯性趋近、液位联动、超温报警、趋势） |
| `topbar.lua` | 四页共用顶栏与底部操作条 |
| `flow_win.lua` / `param_win.lua` / `alarm_win.lua` / `trend_win.lua` | 四个页面窗口模块 |
| `lcd_app.lua` / `tp_app.lua` / `exd_air8607_rgb.lua` | Air8607 板级显示与触摸初始化 |
| `assets\` | 59 张素材（共用背景 JPG + 画布 + 按钮/图元 PNG） |

重新生成素材（改了 `design\index.html` 之后）：

```powershell
python D:\PLCUI\FactoryHMI\tools\bake_assets.py all
```

## 素材与内存约束（已踩过的坑）

1. **整页背景只用一张 `bg.jpg`**，四页共用；工艺画布单独一张 `canvas.jpg`（996×294）。
   1024×600 的 PNG 在真机 HW 解码要 2.4MB，会 `malloc fail`；JPG 走 RGB565 只要 1.2MB。
2. **卡片底、输入框底、隔行线、报警页三个按钮全部用 `container` 画**（纯色 + 圆角），不出图。
3. **按钮图只用不透明像素**：竖向渐变 + 描边，**不做顶部高光**。
   低 alpha 的白色在设备端会被预乘（255×34/255≈34），渲染成一截深灰/黑的块。
4. 同理，行选中高亮、指示灯、勾选点、满箱液面都用实色，不用半透明。
5. 图库图标自带宽白底，烘焙时从四边泛洪抠掉（`knockout_white`）。

## 交互

- 底栏：四页导航 + 启动 / 停止 / 急停；急停后顶栏转红、生成 A-000 报警。
- 工艺页：顶栏状态胶囊切自动 / 手动；手动模式下可点 P-101、P-102、FV-101、FV-102；
  自动模式与急停只提示不动手；KPI 卡点击跳参数页 / 趋势页。
- 参数页：8 组设定值（textarea + 数字键盘，带范围校验），配方选中与应用。
- 报警页：8 行热区选中、单条 / 全部确认、报警复位兼解除急停。
- 趋势页：3 系列 60 点折线 + 当前 / 最高 / 最低统计。
