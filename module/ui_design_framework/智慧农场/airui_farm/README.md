# 智慧养殖场大屏 · AirUI 工程（Air8603）

参考"完竣世界《智慧农业数据可视化大屏》(BV1yXdxYZEAK)"的 8 个页面设计，
**去掉每页中央的大幅地图/图片**，左右数据面板自适应铺满整个屏幕。
视觉风格与同目录 `preview.html`（浏览器 1:1 预览稿）保持一致：
深青绿底、薄荷绿四角括号面板、图标标题带、环形图/雷达图/进度条。

- 硬件：合宙 Air8603（Air1603 主控，RGB565 电容触摸大屏）
- 底层固件：**LuatOS-SoC_V1030_Air1603_102.soc**
- 测试硬件：**Air8603**
- 开发方式：LuatOS (Lua 5.3) + AirUI（基于 LVGL 9.4 封装）+ exwin 页面管理
- 数据：**虚拟模拟数据**（mock.lua 随机游走，每 1.5 秒刷新一次）

## 页面清单（与 preview.html 逐面板一致）

| # | 页面 | 面板内容（2列×3行 栅格） |
|---|------|--------------------------|
| 1 | 农场总览 | 基本信息(4指标卡) / 作物分布(环形) / 产量预测(双色柱) / 水肥监测(双色柱) / 土壤监测(双色柱) / 设备运行(列表) |
| 2 | 作物监测 | 生长状态(环形) / 环境数据(4指标卡) / 土壤墒情(双曲线) / 病虫害预警(列表) / 长势排行(柱状) / 实时告警(列表) |
| 3 | 环境监测 | 当前天气(3指标卡) / 温度趋势(渐变折线) / 湿度趋势(渐变折线) / 光照与CO2(2指标卡) / 土壤环境(3指标卡) / 环境告警(列表) |
| 4 | 资源优化 | 利用概览(3指标卡) / 消耗趋势(三曲线) / 土壤营养(雷达·动) / 灌溉状态(环形) / 优化指标(进度条×5) / 系统告警(列表) |
| 5 | 智能设备 | 数据概览(4指标卡) / 气象监测(3指标卡) / 设备状态(列表) / 设备负载(柱状) / 实时告警(列表) / 生长监测(渐变折线) |
| 6 | 生产运营 | 生产概览(3指标卡) / 资源使用(3指标卡) / 月度产量(双色柱) / 成本构成(柱状) / 种植日历(列表) / 价格趋势(渐变折线) |
| 7 | 市场销售 | 销售概览(3指标卡) / 利润分析(进度条×5) / 销售趋势(双曲线) / 产品排行(柱状) / 类别分析(环形) / 季节分析(柱状) |
| 8 | 质量追溯 | 产品信息(4指标卡) / 质量指标(列表) / 追溯统计(渐变折线) / 等级分布(柱状) / 溯源链路(进度条×4) / 认证预警(列表) |

顶部导航栏 8 个按钮切换页面（当前页薄荷绿高亮）。

## 文件结构

```
airui_farm/
├── main.lua           入口：加载字体、注册页面、打开第1页
├── theme.lua          主题配色 / 自适应布局 / 通用控件 / 页面切换
├── mock.lua           虚拟数据（随机游走）
├── page_overview.lua  页面1 农场总览
├── page_crop.lua      页面2 作物监测
├── page_env.lua       页面3 环境监测
├── page_resource.lua  页面4 资源优化
├── page_device.lua    页面5 智能设备
├── page_operation.lua 页面6 生产运营
├── page_market.lua    页面7 市场销售
├── page_trace.lua     页面8 质量追溯
└── img/               贴图资源（40 个 PNG，含目录一起烧录）
    ├── ic_*.png       33 个 emoji 图标（指标卡/面板标题）
    ├── donut1..4.png  4 张环形图底图
    └── radar1..3.png  雷达图 3 帧（animimg 自动轮播）
```

## 烧录步骤（Luatools）

1. 电脑安装 [Luatools](https://docs.openluat.com/) 及 Air8603 板载 USB 转串口驱动；
2. Type-C 数据线接 Air8603 的 **USB2** 口；
3. Luatools 中新建项目，选择 **Air1603** 对应固件（需含 AirUI V1.1.6+ 与 hzfont 中文字库，Air8603 默认固件即可）；
4. **脚本区添加：本目录全部 `.lua` 文件 + `img` 文件夹（40 个 PNG，保持目录结构）**。
   下载后脚本位于 `/luadb/`，贴图位于 `/luadb/img/`（与 theme.lua 中
   `IMGDIR = "/luadb/img/"` 对应）。若 Luatools 不保留子目录结构，则把
   PNG 直接放到下载根目录并同步修改 `theme.IMGDIR`；
5. 烧录运行，触摸顶部导航按钮切换 8 个页面。

## 分辨率自适应

`theme.lua` 启动时从 lcd 驱动读取实际分辨率（`lcd.getWidth/getHeight`），
读取成功则按实际尺寸自动布局；失败则使用默认 **800×480**。
5寸/7寸 800×480、9寸/10.1寸 1024×600 均可直接运行；
如需强制指定，改 `theme.lua` 顶部的 `theme.W / theme.H` 即可。

## 替换为真实数据

所有动态数值集中在每个页面 `return function() ... end` 的刷新回调里，
数值全部来自 `mock.lua`。接入真实数据时：

- 串口传感器：`require "uart"` 收数据 → 写入 mock 的 state 或直接调
  `theme.set_metric / set_val / set_progress`；
- 4G/WiFi 云平台：`http`/`mqtt` 拉取 JSON → 同上更新；
- 曲线/柱状图用 `theme.set_chart(ch, 系列1, 系列2, ...)` 推送整数数组。

## 已知注意事项

- **核心库不允许 `require`**：固件内置的 C 语言核心库（`airui`、`lcd`、`sys`、
  `rtos` 等）在固件启动时已自动加载，脚本里直接用全局变量即可；
  Luatools 合并时会报"存在多余的 require 'xxx'，核心库不需要 require"。
  本工程已全部清理；
- **扩展库需要 `require`**：`exwin` 是 Lua 实现的扩展库，必须保留
  `require "exwin"`，且 Luatools 项目里要勾选 **"添加默认lib"**，
  否则合并时提示缺少 xxx.lua；
- **PNG 必须是单 IDAT 块**：Air1603 的 PNG 硬件解码器不支持多 IDAT 块，
  Chromium/浏览器导出的 PNG（>32KB 自动分块）会报
  `png hw probe failed: multiple IDAT blocks are not supported by hardware`
  且图片无法显示；本项目 img/ 下 40 个 PNG 已全部重编码为单 IDAT，
  以后新增贴图需同样处理（pngjs `chunkSize: 0x1000000` 重新打包）；
- **贴图必须预缩放到控件尺寸**：`airui.image` / `animimg` 不做缩放，
  按 PNG 原始尺寸从控件左上角开始绘制（官方 FAQ 实锤）。
  本项目 img/ 下：ic_*.png = 16×16、donut*.png = 193×143、radar*.png = 286×143，
  与 theme.lua 布局尺寸一一对应，改布局尺寸时必须同步重新缩放贴图；
- **chart 组件数据点数量要设为实际数据长度**：`point_count` 默认 120/24，
  只 set_values 前几个点会导致柱状图全部挤在绘图区左侧
  （`theme.set_chart` 已通过 `set_point_count(#vals)` 处理）；
  且 **set_values 只支持整数，小数点会不显示**（曲线断断续续），
  传入前必须 math.floor 取整；渐变填充用 `fill={enable,opa_start,opa_end}`，
  `fill_fade` 在部分固件上不生效；
- **C chart 的 x_axis/y_axis/legend 坐标不受控**（轴标签会画出面板外、
  图例是白色大块），theme.chart 已全部禁用并改为自绘刻度/图例/分类名；
- **exwin 切页必须"先 close 旧栈顶，再 open 新窗"**：先开后关会把旧窗
  留在窗口栈底，close 时焦点处理错乱导致白屏；
- **全局字号 ≥16**：本项目所有 label/button font_size 最低 16（大数值 21/24），
  chart 布局留白按此设计（左 44 / 上 22 / 下 18），改字号需同步调留白与控件高度；
- **环形图用纯 AirUI 组件绘制**（不用 PNG）：shape 无 arc 图元，且固件对
  粗描边 line（width>4 + 圆头）渲染不可靠（会画出畸形粗条），**不要用弦线拼弧**；
  可行方案是"珠链圆环"：沿圆周每 10° 一颗彩色 circle（渲染稳定），
  按图例 val 占比点亮，底环暗色珠链衬托 + 内外细描边增加层次，
  弧长/珠数按图例 val 数值占比分配（支持 "31.84%"/"68" 两种写法）。
  **shape 实心圆 width=0 会被固件丢弃**（图元不渲染），实心圆必须带 width>=1；
- **警惕多返回值函数直接内联传参**：`tonumber(string.gsub(s,p,r))` 会把 gsub 的
  第二个返回值（替换次数）传进 tonumber 的 base 参数直接抛错，
  导致页面构建中断（表现为后半页面空白、数据全 "--"、图表无数据）。
  多返回值函数必须先赋值取第一个结果；页面构建函数里的新绘制代码
  要用 pcall 包裹，避免单点异常拖垮整页；
- **控件坐标是根容器绝对坐标**：theme.panel/cell 返回的内容区 rect 是绝对坐标，
  派生的行坐标（如 donut/radar 图例 `ly = a.y + a.h/2 + ...`）必须带 `a.y`，
  漏加会导致文字整体跑到屏幕顶部导航区（本项目已踩坑并修复）；
  同时 label 宽度要给足，`w=40` 放不下 "42.3%" 会被折成两行；
  `i2c.setup(1, i2c.SLOW)` → `tp.init("gt911", {...})`（第一个参数必须是字符串型号）
  → `airui.device_bind_touch(dev)`，缺 `device_bind_touch` 则按钮 `on_click` 不触发；
- **Air8603 屏幕必须脚本侧点亮**：Engine 系列的 RGB 屏固件不自动初始化，
  必须按官方工厂固件顺序执行：供电轨（GPIO12/56/44/52）→
  `display.init("custom",{rgb时序})` → `airui.init(w,h)` → 背光 `pwm.start(3)` →
  `airui.font_load` → `tp.init`。
  **`airui.init` 之前创建控件会卡死、之前调 `font_load` 会总线错误死机**；
- `chart:set_values` 只支持整数，小数请先乘 10 取整或调整 y 轴量程；
- 环形图与雷达图为**预渲染贴图**（形状固定，中心数值/图例为动态控件）；
  雷达图由 3 帧贴图轮播模拟"数据跳动"效果。若需真·动态，可仿照
  `theme.progress` 的 `shape:set_items()` 方案自行扩展；
- 折线图网格为实线（AirUI chart 不支持虚线网格），效果略有差异；
- 渐变背景/文字光晕无法在 AirUI 中实现，用纯色/双色条近似；
- 页面切换通过 `sys.publish("SWITCH_PAGE")` 完成：先打开新窗口再关闭旧窗口，
  避免在按钮回调里直接销毁当前窗口导致 UI 异常；
- 若使用的固件未内置中文字库，需把 ttf 字体放到文件系统并修改
  `main.lua` 中的 `airui.font_load` 增加 `path` 参数。